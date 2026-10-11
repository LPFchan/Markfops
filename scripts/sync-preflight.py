#!/usr/bin/env python3
"""Validate sync destinations and render project-owned policy before writes."""

import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile


def refuse(message):
    raise ValueError(message)


def contained(root, target):
    return os.path.commonpath((root, target)) == root


def destination(root, value):
    target = os.path.abspath(root + "/" + value)
    resolved_root = os.path.realpath(root)
    resolved = os.path.realpath(target)
    if (os.path.isabs(value) or not contained(root, target)
            or not contained(resolved_root, resolved)):
        refuse("Refusing destination outside the repository: " + value)
    workflow = root + "/.github/workflows"
    for normalize in (os.path.abspath, os.path.realpath):
        path, protected = normalize(target), normalize(workflow)
        if os.path.commonpath((path, protected)) in (path, protected):
            refuse("Refusing workflow destination or ancestor: " + value)
    return target


def mappings(root, scaffold, name):
    manifest = scaffold / name
    if not manifest.is_file():
        return []
    result = []
    for line in manifest.read_text().splitlines():
        entry = line.strip(" ")
        if not entry or entry.startswith("#"):
            continue
        if entry == "AGENTS.md managed-section" and name == "manifest.txt":
            continue
        if " -> " not in entry:
            refuse("Refusing invalid manifest entry: " + entry)
        source = entry.split(" -> ", 1)[0]
        relative = entry.rsplit(" -> ", 1)[1]
        target = destination(root, relative)
        result.append((source, target, relative))
    return result


def file_mode(source):
    """Preserve source permissions with the established shell/Markdown rules."""
    mode = stat.S_IMODE(source.stat().st_mode)
    if source.name.endswith(".sh"):
        mode |= 0o111
    elif source.name.endswith(".md"):
        mode &= ~0o111
    return mode


def mode_entries(root, scaffold, source, target):
    source_path = scaffold / source
    if not source.endswith("/"):
        return [(Path(target), file_mode(source_path))]
    entries = []
    for path in [source_path, *source_path.rglob("*")]:
        if path.is_symlink():
            continue  # Archive copies preserve links; their modes are not chmod'd.
        relative = os.path.relpath(Path(target) / path.relative_to(source_path), root)
        installed = Path(destination(root, relative))
        if path == source_path:
            # rsync follows an internal destination-root directory alias while
            # preserving the link itself. Compare and repair its referent mode.
            installed = installed.resolve()
        entries.append((installed, stat.S_IMODE(path.stat().st_mode)))
    return entries


def different_mode(path, expected):
    try:
        return path.is_symlink() or stat.S_IMODE(path.stat().st_mode) != expected
    except FileNotFoundError:
        return True


def plan_modes(root, scaffold, temporary, managed):
    changed = []
    for source, target, relative in managed:
        entries = mode_entries(root, scaffold, source, target)
        if any(different_mode(path, mode) for path, mode in entries):
            changed.append(relative)
    (temporary / "mode-changes").write_text("".join(path + "\n" for path in changed))


def repair_legacy_modes(root, scaffold, managed):
    # A v2.0.0 reader already copied files before reaching the new shell tail.
    # Validate every path first, then restore the same modes a current copy uses.
    plans = [(source, target, mode_entries(root, scaffold, source, target))
             for source, target, _ in managed]
    changed = False
    for source, target, entries in plans:
        changes = [(path, mode) for path, mode in entries if different_mode(path, mode)]
        if not changes:
            continue
        if source.endswith("/"):
            # Archive sync preserves a destination-root alias but replaces
            # child aliases, just as the current shell directory branch does.
            subprocess.run(("rsync", "-a", "--delete", str(scaffold / source) + "/",
                            target + "/"), check=True)
        else:
            path, mode = changes[0]
            if path.is_symlink():
                descriptor, temporary = tempfile.mkstemp(
                    prefix=path.name + ".template-sync.", dir=path.parent)
                os.close(descriptor)
                try:
                    shutil.copy2(scaffold / source, temporary)
                    os.chmod(temporary, mode)
                    os.replace(temporary, path)
                finally:
                    if os.path.lexists(temporary):
                        os.unlink(temporary)
            else:
                os.chmod(path, mode, follow_symlinks=False)
        changed = True
    print(int(changed))


def dirty_paths(root):
    commands = (
        ("diff", "--name-only", "--no-renames", "-z"),
        ("diff", "--cached", "--name-only", "--no-renames", "-z"),
        ("ls-files", "--others", "--exclude-standard", "-z"),
        ("ls-files", "--others", "--ignored", "--exclude-standard", "-z"),
    )
    paths = set()
    for args in commands:
        output = subprocess.check_output(("git", "-C", root, *args))
        paths.update(os.fsdecode(path) for path in output.split(b"\0") if path)
    return paths


def protect_uncommitted(root, targets):
    # Compare both lexical and resolved paths, including dirty parent symlinks.
    # A file mapping owns only that file; a recursive mapping owns descendants.
    for relative in dirty_paths(root):
        dirty = root + "/" + relative
        for target in targets:
            for normalize in (os.path.abspath, os.path.realpath):
                path, managed = normalize(dirty), normalize(target)
                if os.path.commonpath((path, managed)) in (path, managed):
                    refuse("Refusing uncommitted sync destination: " + relative)


def version_header(source):
    """Return the first canonical header marker, excluding fences/body sections."""
    offset = 0
    fence = None
    for line in source.splitlines(keepends=True):
        content = line.rstrip(b"\r\n")
        match = re.match(rb"^ {0,3}(`{3,}|~{3,})(.*)$", content)
        if fence:
            if (match and match[1][:1] == fence[:1]
                    and len(match[1]) >= len(fence) and not match[2].strip()):
                fence = None
        elif match:
            fence = match[1]
        elif re.match(rb"^##[ \t]", content):
            break
        elif content.startswith(b"**Template version:"):
            marker = re.fullmatch(rb"\*\*Template version: ([0-9]+\.[0-9]+\.[0-9]+)\*\*",
                                  content)
            if not marker:
                refuse("Invalid canonical template version marker")
            return offset, offset + len(content), marker[1].decode()
        offset += len(line)
    refuse("Missing canonical header template version marker")


def render_policy(root, temporary, version):
    policy = Path(root) / "records/REPO.md"
    if not policy.exists():
        return
    source = policy.read_bytes()
    start, end, _ = version_header(source)
    replacement = f"**Template version: {version}**".encode()
    (temporary / "repo-version.md").write_bytes(source[:start] + replacement + source[end:])


def render_agents(root, scaffold, temporary):
    agents = Path(root) / "AGENTS.md"
    if not agents.exists():
        return
    source = (scaffold / "AGENTS.md").read_bytes()
    current = agents.read_bytes()
    end = b"<!-- template-managed:end -->"
    legacy_tail = b"## Repo-Specific Rules"
    if end not in source:
        refuse("scaffold AGENTS.md is missing the template-managed:end marker")
    managed = source[:source.index(end) + len(end)]
    if end in current:
        tail = current[current.index(end) + len(end):]
    elif legacy_tail in current:
        tail = b"\n\n" + current[current.index(legacy_tail):]
    elif b"## Code Review Rules" in current:
        start = current.index(b"## Code Review Rules")
        next_section = current.find(b"\n## ", start + 1)
        tail = current[next_section:] if next_section >= 0 else b""
    else:
        refuse("AGENTS.md has no template boundary; refusing sync")
    output = temporary / "agents-merged.md"
    output.write_bytes(managed + tail)
    shutil.copymode(agents, output)


def main():
    root, scaffold, temporary, version = sys.argv[1:5]
    root = os.path.abspath(root)
    scaffold, temporary = Path(scaffold), Path(temporary)
    render_only = sys.argv[5:] == ["--render-only"]
    repair_modes = sys.argv[5:] == ["--repair-modes"]
    if sys.argv[5:] and not (render_only or repair_modes):
        refuse("Invalid preflight arguments")
    agents = destination(root, "AGENTS.md")
    policy = destination(root, "records/REPO.md")
    if not render_only:
        managed = mappings(root, scaffold, "manifest.txt")
        mappings(root, scaffold, "seed-manifest-v2.txt")
        if repair_modes:
            repair_legacy_modes(root, scaffold, managed)
            return
        protect_uncommitted(root, [target for _, target, _ in managed] + [agents, policy])
        plan_modes(root, scaffold, temporary, managed)
    render_agents(root, scaffold, temporary)
    render_policy(root, temporary, version)
    (temporary / "preflight-ready").touch()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))

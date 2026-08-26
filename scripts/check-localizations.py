#!/usr/bin/env python3
"""Check UI localization key parity and format placeholders.

The source scan intentionally covers only APIs that create user-visible labels. Document
titles, Markdown content, diagnostics, HTML, file extensions, and system-image names are
not localization keys and are excluded from the scan.
"""

from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Markfops"
RESOURCE_ROOT = SOURCE_ROOT / "Resources"
LOCALES = ("en", "ko", "ja", "zh-Hans")

# These labels are supplied to AppKit menus/context menus rather than passed as a
# SwiftUI localization initializer, so the source scan cannot discover them.
LEGACY_UI_KEYS = {
    "Close",
    "Close Other Tabs",
    "Close Tabs to the Left",
    "Close Tabs to the Right",
    "Move Tab to New Window",
    "View",
}

UI_LITERAL = re.compile(
    r'\b(?:Text|Button|Label|Menu|CommandMenu|Section|Picker|TextField|Stepper|WindowGroup)'
    r'\s*\(\s*"((?:\\.|[^"\\])*)"'
)
HELP_LITERAL = re.compile(r'\.help\(\s*"((?:\\.|[^"\\])*)"')
NS_LITERAL = re.compile(r'NSLocalizedString\(\s*"((?:\\.|[^"\\])*)"')
CONDITIONAL_BUTTON_LITERAL = re.compile(
    r'Button\([^\n]*?\?\s*"((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"'
)
STRINGS_ENTRY = re.compile(
    r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$'
)
PLACEHOLDER = re.compile(r'%(?:[-+0-9.# ]*)[a-zA-Z@]')


def decode_swift_literal(value: str) -> str:
    """Decode the escapes relevant to source literals and .strings keys."""

    value = re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), value)
    replacements = {
        r'\"': '"',
        r"\\": "\\",
        r"\n": "\n",
        r"\r": "\r",
        r"\t": "\t",
    }
    for source, replacement in replacements.items():
        value = value.replace(source, replacement)
    return re.sub(r"\\U([0-9A-Fa-f]{4})", lambda m: chr(int(m.group(1), 16)), value)


def source_keys() -> set[str]:
    keys: set[str] = set()
    for path in SOURCE_ROOT.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        for pattern in (UI_LITERAL, HELP_LITERAL, NS_LITERAL):
            keys.update(decode_swift_literal(match.group(1)) for match in pattern.finditer(text))
        for match in CONDITIONAL_BUTTON_LITERAL.finditer(text):
            keys.update(decode_swift_literal(value) for value in match.groups())

    # SwiftUI stores this Int interpolation as a printf-style localized key.
    keys.discard(r"\(Int(fontSize))pt")
    keys.add("%lldpt")
    keys.discard("")
    return keys | LEGACY_UI_KEYS


def parse_catalog(path: Path) -> tuple[dict[str, str], dict[str, list[int]], list[str]]:
    values: dict[str, str] = {}
    locations: dict[str, list[int]] = defaultdict(list)
    malformed: list[str] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith(("/*", "*", "//")):
            continue
        match = STRINGS_ENTRY.match(line)
        if not match:
            malformed.append(f"{path}:{line_number}: {line}")
            continue
        key = decode_swift_literal(match.group(1))
        value = decode_swift_literal(match.group(2))
        locations[key].append(line_number)
        values[key] = value
    return values, locations, malformed


def placeholders(value: str) -> Counter[str]:
    return Counter(PLACEHOLDER.findall(value))


def main() -> int:
    expected = source_keys()
    catalogs: dict[str, dict[str, str]] = {}
    errors: list[str] = []

    for locale in LOCALES:
        path = RESOURCE_ROOT / f"{locale}.lproj" / "Localizable.strings"
        values, locations, malformed = parse_catalog(path)
        catalogs[locale] = values
        for line in malformed:
            errors.append(f"malformed catalog entry: {line}")
        for key, lines in locations.items():
            if len(lines) > 1:
                errors.append(f"{path}: duplicate key {key!r} on lines {lines}")
        missing = expected - values.keys()
        extra = values.keys() - expected
        errors.extend(f"{locale}: missing key {key!r}" for key in sorted(missing))
        errors.extend(f"{locale}: obsolete key {key!r}" for key in sorted(extra))
        for key in expected & values.keys():
            if placeholders(key) != placeholders(values[key]):
                errors.append(
                    f"{locale}: placeholder mismatch for {key!r}: "
                    f"key={placeholders(key)}, value={placeholders(values[key])}"
                )
        raw = path.read_text(encoding="utf-8")
        if r"\u{" in raw:
            errors.append(f"{path}: Swift-style \\u{{...}} escape is not valid in a .strings key")

    if catalogs.get("en"):
        english = catalogs["en"]
        for locale, values in catalogs.items():
            if set(values) != set(english):
                errors.append(f"{locale}: key set differs from en")

    if errors:
        print("Localization check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Localization check passed: {len(expected)} keys across {', '.join(LOCALES)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

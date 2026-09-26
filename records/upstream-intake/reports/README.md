# Upstream Intake Report Artifacts

Store completed upstream intake artifacts in this directory.
By default, each review window should create two separate files:

- one full internal record
- one lighter operator brief

Use separate folders for those artifacts:

- [internal-records/](internal-records/README.md)
- [operator-briefs/](operator-briefs/README.md)

## Recommended Naming

Use one paired set of files per review window.

Recommended pattern:

- `internal-records/UPS-YYYYMMDD-NNN-<scope>.md`
- `operator-briefs/UPS-YYYYMMDD-NNN-<scope>-operator-brief.md`

Examples:

- `internal-records/UPS-20260407-001-v1.2.3.md`
- `operator-briefs/UPS-20260407-001-v1.2.3-operator-brief.md`
- `internal-records/UPS-20260414-001-release-to-main.md`

## Expected Contents

Each review should leave behind:

- the full intake record in [internal-records/](internal-records/README.md) using [../weekly-upstream-intake-template.md](../weekly-upstream-intake-template.md)
- a separate concise operator-facing summary in [operator-briefs/](operator-briefs/README.md) using [../operator-weekly-brief-template.md](../operator-weekly-brief-template.md)
- links to any follow-up PRs, issues, ADRs, or notes

The child directory `README.md` files include the canonical example shapes to imitate.

Do not store one-off chat summaries here unless they have been normalized into the intake format.

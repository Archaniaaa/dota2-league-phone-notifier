# Contributing to Queue Ping

Thanks for helping improve the Dota 2 and League of Legends queue phone notifier.

## Before opening an issue

1. Read the [README](README.md), especially the limitations and troubleshooting sections.
2. Test the latest release.
3. Remove private information before attaching output. Never post an ntfy topic, `config.json`, a full publish URL, or unreviewed logs.
4. For League reports, first perform the documented manual foreground-transition test.

## Bug reports

Include:

- Windows version.
- Windows PowerShell 5.1 or PowerShell 7 version.
- Selected game mode.
- Whether the harmless manual foreground test worked.
- The exact error text with topics, URLs, usernames, and local paths removed.

Do not upload game files, memory dumps, packet captures, or account information. They are outside this project's design and are not needed for diagnosis.

## Pull requests

- Keep Windows PowerShell 5.1 compatibility in the main script.
- Do not add administrator requirements, automatic match acceptance, game input, memory reading, injection, traffic inspection, telemetry, advertising, or payment features.
- Avoid external PowerShell modules.
- Update the README and changelog when behavior changes.
- Parse the script with PowerShell's AST parser and run the relevant dry-run checks before submitting.

By contributing, you agree that your contribution is provided under the repository's MIT License.

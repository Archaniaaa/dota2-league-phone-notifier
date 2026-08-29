# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- Privacy-first GitHub Pages landing site with search metadata, structured data, sitemap, robots policy, FAQ, and accessible responsive layout.
- Original Queue Ping social-preview artwork and redesigned README introduction.
- Contribution guide, issue templates, and a community sharing kit.
- Additional discovery topics and project website metadata on GitHub.

### Security

- The public site loads no analytics, advertising, cookies, forms, external scripts, or payment services.
- Publication checks cover saved configuration secrets, local usernames, email addresses, credentials, and non-whitelisted files.

## [1.1.0] - 2026-08-29

### Added

- Per-run selection between Dota 2 and League of Legends.
- `-Game Dota2` and `-Game League` command-line modes.
- Experimental League foreground detection through `LeagueClientUx.exe`.
- Game-specific notification titles and messages.
- Privacy, security, troubleshooting, and release-download guidance.

### Verified

- Windows PowerShell 5.1 and PowerShell 7 syntax and dry-run behavior.
- Dota 2 foreground detection with a real match-found event.
- League foreground-profile behavior with an isolated transition simulation.
- ntfy delivery, bounded retry behavior, secret-safe logs, and both launcher branches.

## [1.0.0] - 2026-08-28

### Added

- Dota 2 foreground-transition detection and ntfy phone notifications.
- First-run secure topic generation, JSON configuration, logging, dry-run, testing, and continuous modes.
- Windows PowerShell launcher and complete setup/troubleshooting guide.

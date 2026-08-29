# Security Policy

## Sensitive information

An ntfy topic acts like a password. Never post a real topic, `config.json`, a full publish URL, or private logs in a public issue.

If a topic is exposed, immediately delete `%LOCALAPPDATA%\DotaMatchNotifier\config.json`, run the notifier to generate a replacement, and subscribe the phone to the new topic.

## Reporting a security issue

Use GitHub's private vulnerability-reporting feature when it is available for this repository. Do not include live credentials or topics in a public issue. A minimal reproduction should use placeholder values such as `dota-example-secret`.

## Scope

The notifier uses only Windows foreground-window APIs and an outbound HTTPS request to the configured ntfy server. It does not read game memory, inject code, inspect game traffic, alter game files, or send input to a game.

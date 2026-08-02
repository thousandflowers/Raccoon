# Security Policy

Raccoon (`rcc`) runs entirely on your Mac. It reads system state, reports
findings, and — only with `audit --fix` — changes system settings, backing up
every change first. There is no telemetry and no outbound connection beyond the
commands you explicitly invoke (e.g. `rcc git`, `brew upgrade`).

## Reporting a Vulnerability

If you find a security issue, open a
[GitHub Issue](https://github.com/thousandflowers/Raccoon/issues) with the label
`security`. Please don't disclose details publicly if the vulnerability could put
other users at risk — say so in the issue and we'll move to a private channel.

Because `rcc` can modify system configuration and run privileged commands, we're
especially interested in: unsafe `--fix` actions, command injection via untrusted
input, and backups that fail to restore. We aim to triage reports within 7 days.

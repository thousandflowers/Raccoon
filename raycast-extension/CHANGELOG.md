# Raccoon Changelog

## [Initial Version] - {PR_MERGE_DATE}

- Browse and run every `rcc` subcommand from a single list
- Dedicated commands for disk space, memory usage, open ports, battery health and the security audit
- Output streams into the view, so long commands show progress and can be stopped
- Nothing opens a Terminal
- Configure Admin Session installs a `visudo`-checked sudoers drop-in so Touch ID is asked once
  rather than once per privileged command; the duration is a preference
- The audit's fix offer becomes a confirmed Raycast action instead of a terminal prompt
- Guided Homebrew install when the `rcc` binary is missing

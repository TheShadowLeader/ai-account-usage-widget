# Security policy

## Reporting a vulnerability

Please do not open a public issue for credential exposure, command execution, unsafe parsing, or provider-authentication concerns. Use GitHub's private vulnerability reporting for this repository.

Include the affected version, reproduction steps, expected impact, and any suggested mitigation. Do not include live credentials, cookies, raw authentication files, or unredacted provider responses.

## Security model

AI Usage Widget is local-only and read-only. It invokes installed provider clients without a shell, bounds captured output, times out child processes, caches only normalized usage snapshots, and sends no analytics.

The app is not sandboxed because it must invoke user-installed authenticated command-line tools. Community builds are ad-hoc signed unless a maintainer publishes a notarized release.

# Contributing

Contributions are welcome when they preserve the app's central promise: provider-reported account-wide subscription usage with no local estimation.

## Before opening a pull request

1. Keep provider integrations read-only and credential-free.
2. Never substitute API billing, session token totals, transcripts, or local process activity for subscription usage.
3. Add a small fixture/self-check for parser changes.
4. Run the release build and parser check documented in the README.
5. Describe which provider client version you verified and redact all personal data.

Please keep dependencies at zero unless a native framework genuinely cannot meet the requirement.

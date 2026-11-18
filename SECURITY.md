# Security policy

globe-switch runs in the background with Input Monitoring and Accessibility
permissions, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately instead:
[Report a vulnerability](https://github.com/irfanmobin/globe-switch/security/advisories/new)
(the **Security** tab → **Report a vulnerability**).

Include what you found, how to reproduce it, and which macOS version you used.

## Verifying what you install

globe-switch is built from source on your own Mac by `install.sh`; there are no
prebuilt binaries. Install only from this repository
(`github.com/irfanmobin/globe-switch`), and read `main.swift` and `install.sh`
before running them — be wary of forks or copies that add network access,
downloads, or anything beyond the keyboard event tap and the caret lookup.

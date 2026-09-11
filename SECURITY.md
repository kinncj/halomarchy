# Security Policy

## Scope

This repository is a provisioning tool: shell scripts that install packages,
write systemd units, and fetch sources. It ships no long-running network
service of its own. The relevant attack surface is:

- **Elevated commands.** The installer calls `sudo` for pacman, systemd units
  and files under `/etc`. Every such call goes through a verb in
  `installers/_lib.sh`, so `--dry-run` shows exactly what would run.
- **Fetched sources.** `installers/webcam.sh` downloads the AMD ISP4 driver
  from the kernel tree and **verifies every file against a sha256 manifest**
  before use. A mismatch aborts the install; it will not build unverified code.
- **AUR packages.** `heimdall-*-bin` and `amdisp4-dkms` are built from the AUR
  via `yay`. AUR PKGBUILDs are user-submitted — review them as you would any.
- **Local services.** Ollama (`:11434`) and Lemonade (`:13305`) bind to
  loopback. Do not expose them to a LAN or the internet; neither authenticates
  by default.

## Reporting a vulnerability

**Open an issue:** https://github.com/kinncj/halomarchy/issues

No email, no private disclosure dance. This is a personal provisioning repo of
shell scripts — it ships no service, stores no user data, and holds no
credentials. A report here is a bug report.

Please include:

- what an attacker could actually do
- the file and line
- `./install.sh --dry-run --all` output, if the installer is involved
- your kernel and machine (`uname -r`, `rocminfo | grep gfx`)

There is no SLA, but security issues get looked at before features.

> If you ever do find something you would rather not post publicly, GitHub's
> [private security advisories](https://github.com/kinncj/halomarchy/security/advisories/new)
> are enabled on this repo and stay hidden until published.

## Things that are deliberately not secrets

- `local.conf` is gitignored because it holds an internal hostname, not a
  credential. It is not encrypted and does not need to be.
- The Heimdall helper runs as root by design so the network-facing daemon does
  not have to; it is read-only and speaks only to a `0660` local socket gated
  by the `heimdall` group. See [docs/services.md](docs/services.md).

## Hardening notes

- Nothing here disables Secure Boot, and the DKMS module is unsigned — if you
  run Secure Boot with module signing enforced, you must sign it yourself.
- `--overwrite` is used exactly once, scoped to a single icon file, to work
  around an Arch packaging conflict. See
  [docs/decisions.md](docs/decisions.md) §8.

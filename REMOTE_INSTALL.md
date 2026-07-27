# GitHub Remote Installation

This repository includes a self-contained `remote-install.sh` entry point for
installation directly from GitHub with `curl`.

The remote entry point does not replace, rewrite, or duplicate the installation
logic. It extracts a checksum-verified copy of the original CODELOCK package and
runs its unchanged `install.sh`. All installer options, platform checks, EULA
acceptance, protected-path safeguards, rollback behaviour, and exit codes remain
the same as a local installation.

## Upload to GitHub

Upload the complete contents of this directory to the root of a GitHub
repository. Keep `remote-install.sh` executable.

## Remote install

Replace `OWNER` and `REPOSITORY` with the GitHub account and repository name:

```bash
curl -fsSL "https://raw.githubusercontent.com/OWNER/REPOSITORY/main/remote-install.sh" | sudo bash
```

The Synaptics EULA prompt remains interactive. The remote entry point reconnects
the unchanged local installer to the terminal so the user can type `AGREE` just
as they would during a local installation.

## Remote compatibility check

```bash
curl -fsSL "https://raw.githubusercontent.com/OWNER/REPOSITORY/main/remote-install.sh" | sudo bash -s -- --check-only
```

## Forward local installer options

Arguments after `bash -s --` are passed directly and unchanged to `install.sh`:

```bash
curl -fsSL "https://raw.githubusercontent.com/OWNER/REPOSITORY/main/remote-install.sh" | sudo bash -s -- --reinstall
```

```bash
curl -fsSL "https://raw.githubusercontent.com/OWNER/REPOSITORY/main/remote-install.sh" | sudo bash -s -- --no-start
```

```bash
curl -fsSL "https://raw.githubusercontent.com/OWNER/REPOSITORY/main/remote-install.sh" | sudo bash -s -- --force-unsupported-kernel
```

## Branch name

The examples use GitHub's common `main` branch. If the repository uses another
branch, replace `main` in the raw GitHub URL with that branch name.

## Integrity behaviour

Before running anything from the package, `remote-install.sh` verifies:

1. the SHA-256 checksum of its embedded original package archive; and
2. the SHA-256 checksum of the extracted original `install.sh`.

It stops without running the installer if either check fails. Temporary files
are removed when the remote entry point exits.

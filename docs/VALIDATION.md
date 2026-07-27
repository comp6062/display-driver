# Validation record

Package: `aoc-i1659fwux-rpi-displaylink-driver-0.2.1`  
Validation date: 2026-07-26

## Passed checks

- Bash syntax for `install.sh`, `uninstall.sh`, `status.sh`, and the self-contained `remote-install.sh`.
- `BUILD_INFO.json` parsing.
- Executable permissions on all four entry-point scripts.
- Kernel-version comparison helpers.
- EVDI DKMS version parsing.
- ELF architecture gate: rejects x86 and accepts AArch64.
- Extraction-only processing of a synthetic vendor archive, including pinned
  checksum enforcement and discovery of the runtime and EVDI source.
- Atomic protected-path backup and restoration for files, directories,
  symbolic links, and paths that were absent before installation.
- Generated systemd unit structural verification with `systemd-analyze`.
- Vendor `.run` invocation audit: exactly one invocation and only with
  `--keep --noexec` extraction options.
- Static mutation scan found no command that changes login/autologin,
  authentication, SSH, the boot target, Wayland/X11 selection, display-manager
  configuration, gettys, Raspberry Pi boot configuration, or generic display
  configuration.
- Help and status-script smoke tests.
- Remote wrapper payload checksum verification and enforced `--check-only` before installation.
- EULA input through `/dev/tty` for `curl | sudo bash` and `wget | sudo bash` use.

## Validation limits

This environment did not contain a Raspberry Pi 4/5, an AOC I1659FWUX, or a
running Raspberry Pi OS graphical session. The proprietary ARM64 runtime was
not executed here. Therefore, physical USB enumeration, DKMS compilation
against the user's exact Raspberry Pi kernel, compositor attachment, EDID mode
reporting, firmware behaviour, and image output still require the hardware
checklist in `README.md`.

The installer is designed to fail closed and roll back driver-specific and
protected-system changes when any required validation fails. This reduces risk;
it is not a substitute for hardware validation on the target Pi.

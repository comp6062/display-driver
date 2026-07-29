# Validation record

Package: `aoc-i1659fwux-rpi-displaylink-driver-0.2.2`  
Validation date: 2026-07-28

## Passed checks

- Bash syntax for installer, uninstaller, status, repair, broker, requester,
  remote installer and standalone installer.
- Embedded remote payload size and SHA-256 verification.
- No placeholder GitHub URLs.
- Static scan confirms no command edits LightDM, autologin, PAM, passwords,
  users, SSH, boot targets, gettys, Wayland/X11 choice or Raspberry Pi boot
  configuration.
- No package-created `modules-load.d` EVDI preload.
- No package-created `initial_device_count=1` configuration.
- Simulated LightDM/greeter state: broker remains idle and does not call
  `modprobe` or DisplayLinkManager.
- Simulated authenticated desktop heartbeat: broker waits for stability, calls
  `modprobe evdi initial_device_count=0`, and starts DisplayLinkManager.
- Simulated logout: broker stops DisplayLinkManager and unloads EVDI.
- Early session-loss safety path creates a per-boot block to prevent repeated
  login loops.
- Existing protected-path backup and rollback logic remains enabled.

## Validation limits

No physical Raspberry Pi or AOC I1659FWUX was available in the build
environment. DRM hotplug, compositor acceptance, performance, firmware and
native mode output still require target-hardware testing.

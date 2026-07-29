# Side-effect boundary

## Added driver components

- Official AArch64 DisplayLink runtime under `/opt/displaylink`.
- Official bundled EVDI source registered through DKMS for the running kernel.
- Exact-device udev rule for AOC USB ID `17e9:ff10`.
- `aoc-i1659fwux-displaylink.service` and the post-login session broker.
- Package state and logs under the matching `/var/lib` and `/var/log` paths.

## Startup boundary

The system service may run at `graphical.target`, but it is only a broker. It
does not load EVDI or launch DisplayLinkManager at LightDM. Driver startup
requires all of the following:

1. `loginctl` reports a local, non-remote, active `user` session.
2. The session type is `wayland` or `x11`.
3. A compositor process owned by that session's UID is running.
4. The AOC `17e9:ff10` device is connected.
5. The same session remains continuously valid for 45 seconds.

EVDI is loaded as `modprobe evdi initial_device_count=0`, so no virtual display
is pre-created before authentication.

## Forbidden changes

The package does not change LightDM, GDM, SDDM, autologin, passwords, PAM,
users, sudo, SSH, the default boot target, gettys, `/boot` configuration,
Wayland/X11 selection, compositor settings, or per-user desktop settings. It
does not restart a display manager, log out the user, or reboot automatically.

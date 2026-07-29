# Side-effect boundary

## Driver-specific changes allowed

1. Install required Debian build/runtime dependencies and matching Raspberry Pi
   kernel headers when absent.
2. Extract the official AArch64 DisplayLink runtime to `/opt/displaylink`.
3. Build and register the bundled EVDI source through DKMS for the running
   kernel and build the matching `libevdi` user-space library.
4. Install the AOC-specific udev rule for USB ID `17e9:ff10`.
5. Install a root systemd broker that remains idle until an authenticated
   desktop sends a valid heartbeat request.
6. Install one display-specific XDG autostart entry and requester. The requester
   waits inside the authenticated desktop before signalling the broker.
7. Load EVDI with `initial_device_count=0` and run DisplayLinkManager only while
   that authenticated local graphical session remains active.
8. Store package state and logs under the package-specific `/var/lib` and
   `/var/log` paths.

## Explicitly not allowed

- Loading EVDI from `modules-load.d` or creating an EVDI device at LightDM.
- Running DisplayLinkManager directly from `graphical.target`.
- Editing LightDM, GDM, SDDM, autologin, passwords, PAM, users, sudo, SSH,
  systemd-logind or display-manager configuration.
- Switching Wayland/X11 or editing labwc, Wayfire, LXDE or Xorg settings.
- Changing the default target, gettys, `tty7`, Raspberry Pi boot configuration,
  HDMI settings, display placement, scaling, rotation or primary-display state.
- Restarting the display manager, logging out the user or rebooting
  automatically.

## Protected paths

The installer snapshots and verifies the existing login, authentication, SSH,
boot, X11 and desktop configuration paths listed in `install.sh`. A detected
change is restored before installation can report success.

The only intentional desktop-session addition is:

```text
/etc/xdg/autostart/aoc-i1659fwux-displaylink.desktop
```

It is directly related to the USB display and is removed by the uninstaller.

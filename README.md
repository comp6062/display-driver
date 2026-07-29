# AOC I1659FWUX DisplayLink driver for Raspberry Pi 4/5 ARM64

Version **0.2.3** installs the official Synaptics DisplayLink 6.3 ARM64 runtime
and the matching EVDI 1.14.15 kernel/user-space components for the AOC
I1659FWUX (`17e9:ff10`) on Raspberry Pi OS/Raspbian ARM64.

## Login-behaviour boundary

The driver does not edit LightDM, autologin, passwords, PAM, users, SSH,
Wayland/X11 selection, systemd's default target, or Raspberry Pi boot files.

EVDI and DisplayLinkManager are deliberately inactive at LightDM. A root broker
uses `loginctl` to locate a real local `x11` or `wayland` user session and
verifies that its compositor is running. The same session must remain active
for 45 continuous seconds before the monitor driver starts.

This corrects the 0.2.2 failure where Raspberry Pi OS labwc did not execute the
XDG autostart request helper. In that failure the desktop worked normally, but
the broker waited forever and the USB monitor remained off.

## One-line remote installation

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

The remote wrapper verifies its embedded payload and checks the installed
package state. On the affected 0.2.2 XDG-request build, it applies the direct
`loginctl` session-detection repair in place without rebuilding EVDI. On a
clean system, it runs the no-change safety check and installs the complete
package. It does not reboot or restart the login manager.

## Immediate 0.2.2 session-detection hotfix

After uploading this repository, an already installed 0.2.2 system can be fixed
without rebuilding EVDI:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/apply-session-detection-fix.sh | sudo bash
```

Keep the normal HDMI desktop logged in. The broker waits 45 seconds of
continuous desktop stability, then starts EVDI and DisplayLinkManager. The AOC
screen may take several additional seconds to initialise.

## Local install

```bash
sudo ./install.sh --check-only
sudo ./install.sh --reinstall
```

Use `--reinstall` only when this package is already installed. On a clean
system, use `sudo ./install.sh`.

## Status

```bash
sudo /var/lib/aoc-i1659fwux-rpi-displaylink/status.sh
```

The important broker states are:

- `waiting`: no eligible local graphical session or monitor is disconnected.
- `stabilising`: the desktop was found and is completing its 45-second guard.
- `starting`: EVDI and DisplayLinkManager are starting.
- `running`: the post-login driver is active.
- `blocked`: starting the driver was followed by an early session loss, so it
  will not retry until the next reboot.

## Uninstall

```bash
sudo /var/lib/aoc-i1659fwux-rpi-displaylink/uninstall.sh
```

The uninstaller removes only this package's service, broker, user-space files,
udev rule, recorded EVDI DKMS version/source, old package-owned autostart helper,
and old package-owned module-loading files. Dependency packages are retained.
It does not change login or desktop settings and does not reboot.

## Native resolution

The monitor's native mode is 1920x1080. The package does not force a global
resolution, primary-display choice, placement, scaling, or rotation. It checks
whether the EVDI connector reports 1920x1080 after DisplayLink starts.

## Hardware note

The I1659FWUX in the supplied diagnostics enumerated on a 480 Mbit/s USB path.
That does not prevent the broker from starting, but a direct USB 3 connection or
a properly powered USB 3 hub is preferable for bandwidth and power stability.

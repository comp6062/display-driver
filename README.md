# AOC I1659FWUX DisplayLink driver for Raspberry Pi OS ARM64

This repository installs the official Synaptics DisplayLink 6.3 AArch64 runtime
and its bundled EVDI source for an AOC I1659FWUX (`17e9:ff10`) on a Raspberry
Pi 4 or Raspberry Pi 5 running Raspberry Pi OS/Raspbian ARM64.

The package does **not** execute Synaptics' general-purpose installer. It
extracts only the AArch64 runtime, builds the matching EVDI kernel module and
`libevdi`, and installs an AOC-specific service and udev rule.

## Important login-safety design

Earlier repository revisions loaded EVDI before LightDM and ran
`DisplayLinkManager` at `graphical.target`. That made the USB monitor available
at the greeter, but it could also cause the authenticated desktop session to
terminate immediately and return to the login screen. That looks like an
incorrect password, but the password is normally accepted and the desktop
session is what failed.

Version 0.2.2 removes that startup design completely:

- no EVDI entry is added to `/etc/modules-load.d`;
- no `initial_device_count=1` option is added to `/etc/modprobe.d/evdi.conf`;
- EVDI and `DisplayLinkManager` remain inactive at LightDM;
- an XDG desktop autostart requester waits 25 seconds after an authenticated
  desktop begins;
- a root broker verifies the request for another 10 seconds, then loads EVDI
  with `initial_device_count=0` and starts `DisplayLinkManager`;
- the broker stops the manager and unloads EVDI when that desktop session ends;
- if the desktop disappears within 60 seconds after driver startup, the driver
  is blocked for the remainder of that boot instead of repeatedly causing a
  login loop.

The AOC monitor is therefore intentionally blank during boot and at the login
screen. It should appear about 35 seconds after the normal desktop has started.

## Behaviour that is preserved

The installer does not intentionally change:

- LightDM, autologin, passwords, PAM, users or authentication;
- SSH, sudo or networking;
- the systemd default boot target or gettys;
- Wayland/X11 selection, labwc, Wayfire, LXDE or Xorg configuration;
- Raspberry Pi boot configuration;
- primary-display selection, scaling, rotation or placement;
- HDMI configuration or unrelated device settings.

The one added desktop-session object is the display-specific XDG autostart
requester required to start the driver only after authentication.

## Files added

```text
/opt/displaylink/
/opt/displaylink/aoc-session-broker.sh
/opt/displaylink/aoc-session-request.sh
/usr/src/evdi-<version>/
/var/lib/dkms/evdi/<version>/
/lib/modules/<kernel>/updates/dkms/evdi.ko*
/etc/xdg/autostart/aoc-i1659fwux-displaylink.desktop
/etc/udev/rules.d/99-aoc-i1659fwux-displaylink.rules
/etc/systemd/system/aoc-i1659fwux-displaylink.service
/etc/systemd/system/graphical.target.wants/aoc-i1659fwux-displaylink.service
/var/lib/aoc-i1659fwux-rpi-displaylink/
/var/log/aoc-i1659fwux-rpi-displaylink/
```

The system service is only a request broker. Starting that service does not load
EVDI or start `DisplayLinkManager`.

## Repair a Pi already stuck in the login loop

Update the GitHub repository with this corrected bundle, then run the repair
from SSH or a text console such as `Ctrl`+`Alt`+`F2`:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/repair-login.sh | sudo bash
sudo reboot
```

The repair removes the old pre-login driver startup and the package's EVDI
installation. It does not edit LightDM, the password, autologin or PAM. After
the reboot, confirm that the original desktop/autologin behaviour is restored.

Then install the corrected package:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
sudo reboot
```

## One-command installation

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

The remote script verifies its embedded package, runs the no-change safety
check first, and starts installation only if that check passes. The Synaptics
EULA prompt remains interactive through `/dev/tty`.

## Local safety check and installation

```bash
sudo ./install.sh --check-only
sudo ./install.sh
sudo reboot
```

Options:

```text
--check-only                 Check compatibility without changing the system.
--reinstall                  Remove this package's prior installation first.
--no-start                   Install the broker but do not start it this boot.
--force-unsupported-kernel   Permit an out-of-range kernel for testing only.
```

## Status

```bash
sudo /var/lib/aoc-i1659fwux-rpi-displaylink/status.sh
```

The report shows the broker, desktop request heartbeat, boot safety block,
DisplayLinkManager, EVDI, DRM connector and native `1920x1080` mode.

## Uninstall

```bash
sudo /var/lib/aoc-i1659fwux-rpi-displaylink/uninstall.sh
sudo reboot
```

Dependencies are retained because another program may use them. The uninstaller
does not edit login or desktop configuration.

## Proprietary archive and EULA

The proprietary Synaptics binary is not redistributed in this repository. The
installer downloads the official DisplayLink 6.3 Ubuntu archive after the user
types `AGREE`, verifies its pinned SHA-256, and extracts it without running the
vendor installation routine.

For offline installation, place the unmodified archive at:

```text
vendor/DisplayLink-USB-Graphics-Software-for-Ubuntu-6.3.zip
```

## Compatibility and validation

Target environment:

- Raspberry Pi 4 or Raspberry Pi 5;
- Raspberry Pi OS/Raspbian Debian base;
- `aarch64` kernel and userland;
- systemd, LightDM or another local graphical login, and XDG autostart;
- Linux 4.15 through 6.15 unless explicitly overridden;
- matching headers for the running kernel.

The package has passed Bash syntax, archive-integrity, embedded-payload,
protected-path rollback and simulated greeter/authenticated-session/broker
checks. It still requires physical validation on the target Pi and monitor.

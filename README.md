# AOC I1659FWUX Driver for Raspberry Pi 4/5 (ARM64)

This package is a deliberately narrow installer for the **AOC I1659FWUX USB
monitor** on a **Raspberry Pi 4 or Raspberry Pi 5** running 64-bit Raspberry Pi
OS/Raspbian (`aarch64`).

It uses the official Synaptics DisplayLink Ubuntu 6.3 archive, but it does
**not** execute Synaptics' generic system installer. Instead, it extracts only:

- the AArch64 `DisplayLinkManager` runtime and its matching libraries/firmware;
- the bundled EVDI source, which it builds for the running Raspberry Pi kernel
  through DKMS.

That design keeps the change boundary small and avoids the display-manager,
TTY, X11/Wayland, and login changes that can be introduced by broad third-party
DisplayLink installation scripts.

## Validation status

The bundle has been statically reviewed and its Bash scripts pass syntax and
safety-pattern checks. It has **not** been run against every Raspberry Pi OS,
kernel, compositor, and physical I1659FWUX combination. Treat version 0.2.0 as
an engineering-validation package until it passes the hardware checklist below
on your own Pi.

The installer is fail-closed: it validates the platform, archive, CPU
architecture, kernel headers, DKMS result, and runtime library dependencies. If
an installation step fails, it removes the partial driver and restores the
protected system paths it snapshotted.

## Exact intended result

The Raspberry Pi should retain its existing:

- login or autologin behaviour;
- password and authentication configuration;
- SSH configuration;
- boot target and boot configuration;
- Wayland/X11 choice and compositor;
- desktop/session configuration;
- primary-display layout and resolution settings;
- network configuration.

The only intended functional difference is that the AOC USB monitor gains the
DisplayLink/EVDI software required to operate.

## Files and system objects added

The installer may add only the following driver-specific objects, plus required
Debian packages:

```text
/opt/displaylink/
/usr/src/evdi-<version>/
/var/lib/dkms/evdi/<version>/
/lib/modules/<kernel>/updates/dkms/evdi.ko*
/etc/modprobe.d/evdi.conf
/etc/modules-load.d/aoc-i1659fwux-evdi.conf
/etc/udev/rules.d/99-aoc-i1659fwux-displaylink.rules
/etc/systemd/system/aoc-i1659fwux-displaylink.service
/etc/systemd/system/graphical.target.wants/aoc-i1659fwux-displaylink.service
/var/lib/aoc-i1659fwux-rpi-displaylink/
/var/log/aoc-i1659fwux-rpi-displaylink/
```

The exact-device udev rule matches USB ID `17e9:ff10`; it does not start the
service from USB hotplug and does not install generic DisplayLink networking
rules. The isolated service is enabled only for the normal graphical target and
contains no `getty`, login-manager, or TTY conflict. DKMS also updates normal
kernel-module dependency metadata and may refresh an existing initramfs when the
system's own DKMS policy requires it; it does not change boot configuration.

## Explicitly prohibited changes

The installer does **not**:

- enable, disable, or reconfigure autologin;
- edit LightDM, GDM, SDDM, PAM, passwords, users, sudo, SSH, or systemd-logind;
- switch Wayland to X11 or X11 to Wayland;
- edit labwc, Wayfire, LXDE, or per-user desktop configuration;
- change `default.target`, disable a getty, or reserve `tty7`;
- edit `/boot/config.txt` or `/boot/firmware/config.txt`;
- install an Xorg configuration or force a display layout;
- blacklist `udl` or `udlfb` globally;
- change networking, USB power, or unrelated device rules;
- reboot automatically.

Before making driver changes, the installer snapshots protected login,
authentication, boot, X11, and desktop-session paths. It compares them before
reporting success and restores them if they changed.

See `docs/SIDE_EFFECT_BOUNDARY.md` for the complete boundary.

## Native resolution

The I1659FWUX panel's native mode is **1920 × 1080**. The package does not force
that resolution globally. It checks whether the EVDI DRM connector exposes the
native mode supplied by the monitor. Display placement, rotation, scaling, and
which screen is primary remain under the existing Raspberry Pi OS display
settings.

The package installs the kernel and user-space driver without changing the
current Wayland/X11 session. Whether a particular Raspberry Pi OS compositor
claims and presents the new EVDI connector must still be confirmed on the
physical Pi. If it does not, `status.sh` reports that condition rather than
silently switching sessions, restarting the display manager, or changing login
behaviour.

## Conservative compatibility target

- Raspberry Pi 4 or Raspberry Pi 5;
- `aarch64` kernel and userland;
- Raspberry Pi OS/Raspbian or its Debian base;
- systemd and a graphical desktop;
- Linux 4.15 through 6.15 by default;
- matching headers for the currently running kernel.

A kernel outside the conservative range is rejected unless the explicit
`--force-unsupported-kernel` testing option is used. This does not guarantee
that an unsupported kernel will work.

## Proprietary archive and EULA

The proprietary Synaptics binary is not redistributed inside this ZIP. During
installation, the script displays the Synaptics EULA page and requires the user
to type `AGREE` before any system changes occur. It then downloads the official
6.3 archive directly from Synaptics.

For an offline installation, place an unmodified copy at exactly:

```text
vendor/DisplayLink-USB-Graphics-Software-for-Ubuntu-6.3.zip
```

The installer checks that the ZIP is valid, verifies the pinned SHA-256 for
Synaptics build 6.3.0-48, and dynamically identifies the AArch64 binary. It will
stop and roll back if the archive checksum, layout, or contents are incompatible
with the package's expectations.

The official runtime contains device firmware. If the connected monitor needs a
firmware update, DisplayLinkManager may apply it automatically; the screen can
take several extra seconds to appear on the first connection afterward.

## Before installation

Remove any existing DisplayLink or EVDI installation first. The installer will
refuse to merge with another driver stack because doing so would make safe
rollback unreliable.

Run the no-change compatibility check:

```bash
unzip aoc-i1659fwux-rpi-displaylink-driver-0.2.0.zip
cd aoc-i1659fwux-rpi-displaylink-driver-0.2.0
sudo ./install.sh --check-only
```

## Install

```bash
sudo ./install.sh
```

Optional modes:

```text
--check-only                 Check compatibility without changing the system.
--reinstall                  Remove this package's prior installation first.
--no-start                   Install without starting the service this boot.
--force-unsupported-kernel   Permit an out-of-range kernel for testing only.
```

The installer does not reboot. If the monitor is already connected, it attempts
to start and verify the driver in the current boot. A normal manual reboot may
be needed so EVDI is present before the compositor begins; the script will say
so without changing the session configuration.

## Check status

From the extracted bundle:

```bash
sudo ./status.sh
```

After installation:

```bash
sudo /var/lib/aoc-i1659fwux-rpi-displaylink/status.sh
```

The status report includes:

- Raspberry Pi model, OS, architecture, and kernel;
- detection of USB ID `17e9:ff10`;
- EVDI module and DKMS state;
- isolated systemd-service status and recent log;
- current compositor/session process;
- EVDI DRM connectors and exposed modes;
- AArch64 runtime and shared-library resolution.

## Uninstall

```bash
sudo /var/lib/aoc-i1659fwux-rpi-displaylink/uninstall.sh
```

or, from the extracted bundle:

```bash
sudo ./uninstall.sh
```

The uninstaller removes only this package's recorded service, udev/module files,
AArch64 runtime, EVDI DKMS version, and source directory. If `/etc/modprobe.d/evdi.conf`
existed before installation, its exact prior copy is restored.

Dependency packages are intentionally retained because removing them could
break other software. The uninstaller does not change login/session settings or
reboot. If EVDI is still held by the running graphical session, its in-memory
copy disappears at the next normal reboot.

## Hardware validation checklist

1. Run `sudo ./install.sh --check-only` and resolve every reported conflict.
2. Record `systemctl get-default` and the Pi's current login/autologin behaviour.
3. Install with the AOC monitor disconnected.
4. Confirm the normal primary display reaches the desktop exactly as before.
5. Connect the I1659FWUX to a USB 3 port or a properly powered USB 3 hub.
6. Run the installed `status.sh`.
7. Confirm USB ID `17e9:ff10`, a running service, an EVDI connector, and
   `1920x1080` in that connector's modes.
8. Reboot once manually and confirm the original login behaviour is unchanged.
9. Test disconnect and reconnect without restarting the display manager.
10. Uninstall and confirm the original system behaviour remains intact.

## Logs and recovery data

```text
/var/log/aoc-i1659fwux-rpi-displaylink/
/var/lib/aoc-i1659fwux-rpi-displaylink/
```

If installation fails, the partial driver is removed and diagnostics are moved
to a timestamped directory under:

```text
/var/backups/aoc-i1659fwux-rpi-displaylink-failed-*
```

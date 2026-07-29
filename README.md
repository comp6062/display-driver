# AOC I1659FWUX boot-safe DisplayLink driver for Raspberry Pi ARM64

Version **0.4.0** is based on the user-supplied installer that already proves the official Synaptics DisplayLink driver can operate the monitor when the AOC is connected after the Raspberry Pi desktop has started.

This revision does not replace that working driver path. It reproduces the successful hot-plug sequence automatically while blocking the AOC and the DisplayLink service during boot and at the login screen.

## What this revision changes

The package:

- installs or adopts the official Synaptics DisplayLink 6.3 driver;
- keeps the baseline EVDI configuration that allowed the monitor to work;
- quarantines only USB device `17e9:ff10` during boot and at the greeter;
- overrides the generic vendor DisplayLink udev rule so it cannot start the driver before login;
- keeps the official DisplayLink service disabled at boot;
- adds a service condition requiring a post-login allow marker;
- clears the vendor service's tty/getty conflict without changing LightDM or the login configuration;
- waits for the existing authenticated local X11 or Wayland desktop;
- waits another 12 seconds, authorizes the AOC and starts the same official service used by the working baseline;
- stops DisplayLink and returns the AOC to quarantine before the desktop session ends;
- migrates away from the earlier `initial_device_count=0` experimental package that could leave the monitor dark;
- never edits passwords, PAM, users, SSH, LightDM, autologin, the default boot target or the chosen desktop session.

The AOC is intentionally unavailable at the login screen.

## Mandatory powered USB hub

The AOC I1659FWUX is powered through USB and is rated at approximately 8 W. A driver cannot prevent that physical power draw before the Raspberry Pi firmware and Linux have started.

Because this specific setup already stalls before SSH becomes available when the monitor is directly attached, use a **separately powered USB 3 hub on both Raspberry Pi 4B and Raspberry Pi 5**. The hub must carry USB 3 data between the Pi and the monitor while supplying the monitor's power from its own adapter.

The software can stop early USB configuration and DisplayLink startup. It cannot correct a pre-Linux brownout, inrush-current event or USB over-current condition.

## First installation

1. Boot the Pi with the AOC unplugged.
2. Connect HDMI so the original desktop remains available.
3. Upload this bundle's files directly to the root of `comp6062/display-driver`.
4. Run the remote installer.
5. After installation, connect the AOC through the separately powered USB 3 hub and reboot.

## GitHub one-line installation

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | bash
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | bash
```

The remote script contains a checksum-verified embedded package. It runs the no-change `--check-only` safety test before beginning installation.

The command may also be run through `sudo bash`, but running it as shown lets the installer identify the normal desktop user most reliably. The installer uses `sudo` only for required system changes.

## Local installation

```bash
unzip display-driver-boot-safe-0.4.0-github.zip
cd display-driver-boot-safe-0.4.0
./install.sh --check-only
./install.sh
```

The installer asks for exact confirmation of the powered-hub requirement and the Synaptics EULA.

## Expected boot sequence

1. The Pi boots using its original HDMI, login and autologin behaviour.
2. The AOC remains USB-deauthorized and DisplayLink remains stopped.
3. The normal local graphical session becomes active.
4. The broker waits 12 seconds.
5. The broker authorizes `17e9:ff10` and starts the official DisplayLink service.
6. The AOC appears as if it had been physically hot-plugged after login.
7. At logout, DisplayLink stops before the greeter returns.

## Status and emergency recovery

```bash
sudo /usr/local/sbin/aoc-i1659fwux-status
```

Emergency safe mode:

```bash
sudo /usr/local/sbin/aoc-i1659fwux-repair
sudo reboot
```

After the original desktop/login behaviour is restored:

```bash
sudo /usr/local/sbin/aoc-i1659fwux-repair --enable
```

## Uninstall

If this package adopted an official DisplayLink installation that was present before this project, the normal uninstaller removes only this package and restores the prior vendor service and udev-rule state:

```bash
sudo /usr/local/sbin/aoc-i1659fwux-uninstall
```

To remove the official DisplayLink driver as well:

```bash
sudo /usr/local/sbin/aoc-i1659fwux-uninstall --remove-official-driver
```

APT dependencies are intentionally left installed.

## Validation boundary

The package has been checked for shell syntax, embedded-payload integrity, archive integrity, permissions, prohibited login-setting writes and fail-closed platform behavior. It has not been physically validated on the target Pi/monitor combination. The powered hub is required before testing a boot with the monitor attached.

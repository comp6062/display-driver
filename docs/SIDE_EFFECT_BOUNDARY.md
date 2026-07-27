# Side-effect boundary

This package follows a fail-closed, minimal-change boundary.

## Driver-specific changes that are allowed

1. Install Debian packages strictly required to download, inspect, build, load,
   and run the DisplayLink/EVDI stack:
   `ca-certificates`, `curl`, `unzip`, `dkms`, `build-essential`, `binutils`,
   `libdrm-dev`, `libelf-dev`, `libusb-1.0-0`, `libstdc++6`, `usbutils`,
   and matching Raspberry Pi kernel headers when absent.
2. Extract the official AArch64 DisplayLink runtime to `/opt/displaylink`.
3. Place the official bundled EVDI source at `/usr/src/evdi-<version>` and
   register/build it through DKMS for the running kernel. DKMS writes its normal
   state under `/var/lib/dkms`, installs `evdi.ko` under the running kernel's
   module tree, updates module dependency metadata, and may refresh an existing
   initramfs according to the system's own DKMS policy.
4. Create `/etc/modprobe.d/evdi.conf` with one EVDI device and a Raspberry Pi
   VC4 soft dependency. Any pre-existing file at that exact path is backed up
   and restored during uninstall or rollback.
5. Create `/etc/modules-load.d/aoc-i1659fwux-evdi.conf`.
6. Create an access-only udev rule restricted to AOC USB ID `17e9:ff10` at
   `/etc/udev/rules.d/99-aoc-i1659fwux-displaylink.rules`.
7. Create and enable
   `/etc/systemd/system/aoc-i1659fwux-displaylink.service` under
   `graphical.target`, including its normal `graphical.target.wants` symlink.
   The unit has no TTY/getty/display-manager conflict.
8. Store driver state, diagnostics, status, and uninstall tools under
   `/var/lib/aoc-i1659fwux-rpi-displaylink` and logs under the matching
   `/var/log` directory.

The package does not execute Synaptics' generic `.run` installer. It invokes the
`.run` archive only with its extraction-only options and then installs the
necessary contents itself.

## Protected system state

Before driver installation, the script records and archives these paths:

- `/etc/lightdm`
- `/etc/gdm3`
- `/etc/sddm.conf` and `/etc/sddm.conf.d`
- `/etc/pam.d`
- `/etc/ssh`
- `/etc/systemd/logind.conf`
- `/etc/systemd/system/default.target`
- `/etc/systemd/system/display-manager.service`
- getty override directories for `tty1` and `tty7`
- `/boot/config.txt` and `/boot/firmware/config.txt`
- `/etc/X11` and `/usr/share/X11/xorg.conf.d`
- system-wide labwc, Wayfire, and LXDE session configuration

A post-install manifest is compared byte-for-byte and metadata-for-metadata.
Any difference is restored from the pre-install archive before success can be
reported. A restoration failure aborts the installation.

## Changes expressly forbidden

- Changing login, autologin, greeter, password, PAM, user, sudo, SSH, or
  authentication behaviour.
- Switching or configuring Wayland, X11, labwc, Wayfire, Xorg, or a display
  manager.
- Changing the default systemd target, disabling gettys, or claiming `tty7`.
- Editing Raspberry Pi boot configuration, command line, overlays, or firmware
  settings.
- Installing a forced resolution, primary-display, scaling, placement, or
  rotation configuration.
- Blacklisting `udl`/`udlfb` globally or changing unrelated kernel modules.
- Installing generic DisplayLink USB-Ethernet or networking rules.
- Changing USB power, network, firewall, audio, Bluetooth, or unrelated device
  behaviour.
- Automatically rebooting, logging out, restarting the display manager, or
  terminating the active graphical session.
- Removing dependency packages during uninstall.

## Conflict policy

The installer refuses to run over another DisplayLink/EVDI installation,
including an existing `/opt/displaylink`, EVDI DKMS registration/source,
DisplayLink package, service, or installer link. This is intentional: merging
with unknown state would make preservation and rollback claims unreliable.

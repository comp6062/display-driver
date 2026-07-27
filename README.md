# AOC I1659FWUX DisplayLink Driver for Raspberry Pi 4/5

A single-file Bash installer for the AOC I1659FWUX USB monitor on 64-bit Raspberry Pi OS/Raspbian running on a Raspberry Pi 4 or Raspberry Pi 5.

The main installer is preserved from the CODELOCK source bundle. The repository adds only the files needed for GitHub distribution and verified remote installation.

## Remote installation

### Using curl

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/install.sh | sudo bash
```

### Using wget

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/install.sh | sudo bash
```

The remote wrapper downloads the unchanged main installer, verifies its SHA-256 checksum, makes the temporary copy executable, and runs it. The downloaded temporary files are removed when the wrapper exits.

The installer displays the Synaptics DisplayLink EULA URL and asks you to type `AGREE` before it downloads or installs the proprietary DisplayLink payload.

For a non-interactive installation after you have reviewed and accepted the EULA:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/install.sh | sudo bash -s -- --accept-displaylink-eula
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/install.sh | sudo bash -s -- --accept-displaylink-eula
```

## Local installation

```bash
git clone https://github.com/comp6062/display-driver.git
cd display-driver
chmod +x install.sh aoc-i1659fwux-rpi4-single-file-installer.sh

./aoc-i1659fwux-rpi4-single-file-installer.sh --validate
./aoc-i1659fwux-rpi4-single-file-installer.sh --preflight
sudo ./aoc-i1659fwux-rpi4-single-file-installer.sh
```

You may also run the verified repository wrapper locally:

```bash
sudo ./install.sh
```

## Package behaviour

The installer:

- Targets Raspberry Pi 4 and Raspberry Pi 5 hardware running 64-bit ARM Raspberry Pi OS/Raspbian.
- Downloads and extracts the official DisplayLink 6.3 package without executing its Ubuntu installer.
- Installs the official unmodified AArch64 DisplayLink manager.
- Builds the matching EVDI kernel module with DKMS.
- Builds the matching `libevdi` from the same official bundled source.
- Uses Raspberry Pi OS's own `libusb` runtime instead of installing the Ubuntu-bundled copy.
- Corrects only the identified AOC/EVDI output to 1920×1080 when correction is needed.
- Includes built-in validation, preflight, diagnostics, resolution correction, rollback, and uninstall modes.
- Stops before installation if another DisplayLink or EVDI installation is detected.
- Does not reboot automatically.

## System behaviour that is not changed

The installer does not modify:

- LightDM, GDM, SDDM, PAM, autologin, or greeter configuration.
- Login-screen behaviour.
- Wayland/X11 session selection.
- `/etc/X11` or Xorg configuration.
- Raspberry Pi boot configuration.
- HDMI configuration.
- Primary monitor selection.
- Display position, rotation, mirroring, or desktop layout.
- Existing DisplayLink or EVDI installations.

## Commands

Validate the single-file package:

```bash
./aoc-i1659fwux-rpi4-single-file-installer.sh --validate
```

Run the platform and conflict preflight check:

```bash
./aoc-i1659fwux-rpi4-single-file-installer.sh --preflight
```

Install:

```bash
sudo ./aoc-i1659fwux-rpi4-single-file-installer.sh
```

Create a diagnostics report:

```bash
./aoc-i1659fwux-rpi4-single-file-installer.sh --diagnostics
```

Run the monitor-specific resolution helper manually:

```bash
./aoc-i1659fwux-rpi4-single-file-installer.sh --resolution
```

Uninstall or roll back only files owned by this package:

```bash
sudo ./aoc-i1659fwux-rpi4-single-file-installer.sh --uninstall
```

or, after installation:

```bash
sudo /usr/local/sbin/aoc-i1659fwux-driver --uninstall
```

## Installation options

```text
--accept-displaylink-eula   Confirm acceptance of the Synaptics DisplayLink EULA.
--driver-zip PATH           Use a previously downloaded official DisplayLink 6.3 ZIP.
--no-resolution-helper     Do not install the post-login 1920x1080 correction helper.
--force-unsupported-kernel Continue outside the officially verified kernel range.
--keep-download            Keep the downloaded official DisplayLink ZIP.
-h, --help                 Show installer help.
```

Arguments supplied to `install.sh` are passed unchanged to the main installer. For example:

```bash
sudo ./install.sh --no-resolution-helper
```

## Repository files

```text
README.md
install.sh
SHA256SUMS
aoc-i1659fwux-rpi4-single-file-installer.sh
```

- `aoc-i1659fwux-rpi4-single-file-installer.sh` is the complete CODELOCK installer.
- `install.sh` is the verified GitHub remote-install wrapper.
- `SHA256SUMS` contains checksums for the repository scripts.

## Verify downloads manually

```bash
sha256sum -c SHA256SUMS
```

The expected SHA-256 for the CODELOCK main installer is:

```text
272920d4c08a1b4759c30b6efcfb1b71b59c7778e7a1f597f49bfbc4e625d11e
```

## Important notes

- Connect the AOC I1659FWUX directly to a Raspberry Pi USB 3 port when possible.
- Log out and back in, or reboot when convenient, after installation.
- The installer does not automatically remove or overwrite another DisplayLink/EVDI installation.
- The proprietary DisplayLink payload remains governed by the Synaptics EULA and is downloaded from Synaptics during installation.
- This package has not been physically tested on every Raspberry Pi kernel, desktop session, and monitor combination.

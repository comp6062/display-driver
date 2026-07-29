# GitHub remote installation

The repository is already configured for:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

`remote-install.sh` is self-contained. It reconstructs a checksummed embedded
copy of the package, verifies it, runs `install.sh --check-only`, and proceeds to
the interactive installation only when the safety check passes.

The EULA response is read from `/dev/tty`, so `AGREE` can be entered even when
the script is piped to `sudo bash`.

## Existing login-loop revision

A Pi with the earlier pre-login EVDI revision must be repaired and rebooted
before installing this revision:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/repair-login.sh | sudo bash
sudo reboot
```

Then run the normal remote installation command and reboot once more.

## Upload layout

Upload all files from the ZIP directly to the root of the
`comp6062/display-driver` repository. In particular, these files must be at the
repository root:

```text
remote-install.sh
repair-login.sh
install.sh
uninstall.sh
status.sh
session-broker.sh
session-request.sh
```

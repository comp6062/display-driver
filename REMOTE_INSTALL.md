# Remote installation

Upload every file in this repository ZIP to the root of:

```text
https://github.com/comp6062/display-driver
```

Then run either:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/display-driver/main/remote-install.sh | sudo bash
```

The wrapper verifies its embedded package before running anything from it.

When it finds the installed 0.2.2 package with
`startup=post-login-xdg-autostart-root-broker`, it applies only the direct
session-detection hotfix. EVDI is not rebuilt and the display manager is not
restarted. The broker then observes the active local X11/Wayland session through
`loginctl`, waits 45 seconds for stability, and starts DisplayLink.

On a clean system, the wrapper runs `install.sh --check-only` before the normal
installation. It stops if the safety check fails.

# Technical design

## Baseline retained

The driver installation and runtime remain the official Synaptics DisplayLink 6.3 internal installer and official system service from the user-supplied working-after-hotplug baseline. Existing `/opt/displaylink/DisplayLinkManager` installations are adopted by default.

The package deliberately does not force `initial_device_count=0`. During an upgrade from revision 0.3.x, it restores the exact EVDI boot configuration that revision backed up. This preserves the EVDI behavior under which the monitor already produced video.

## Exact-device USB quarantine

`00-aoc-i1659fwux-quarantine.rules` matches only:

- USB vendor `17e9`
- USB product `ff10`

Without `/run/aoc-i1659fwux-displaylink/allow`, udev writes `0` to the device's `authorized` attribute. The device is therefore prevented from being configured and made available to drivers during boot and at the greeter.

When an initramfs already exists, the package copies the exact-device rule and policy helper into that initramfs. It does not create or enable an initramfs on a system that did not already use one.

## Vendor udev suppression

The official generic DisplayLink udev rule can explicitly start the vendor service when vendor `17e9` is detected. Merely disabling a service does not prevent an explicit start.

The package therefore backs up an existing `/etc/udev/rules.d/99-displaylink.rules` and installs a same-name `/dev/null` override. This suppresses the generic rule while the exact AOC rule remains under package control.

## Official service post-login guard

The vendor service is not replaced. A drop-in is added to the detected `displaylink-driver.service` or `displaylink.service`:

- clears the vendor tty/getty conflict;
- adds `ConditionPathExists=/run/aoc-i1659fwux-displaylink/allow`;
- leaves the service disabled at boot.

The official service can therefore start only when the broker has created the allow marker after authentication.

## Session broker

The broker starts at `multi-user.target` but performs no display action until it finds a local, active, non-greeter X11 or Wayland session belonging to the original desktop user.

It then:

1. waits 12 seconds for desktop stability;
2. creates the allow marker;
3. authorizes USB device `17e9:ff10`;
4. starts the official DisplayLink service;
5. monitors both the graphical session and service;
6. stops the service and deauthorizes the AOC before the session returns to the greeter.

A service failure is not retried repeatedly during the same desktop session.

## Upgrade migration

When an earlier package revision is found, the installer retains the original rollback metadata, including whether the official DisplayLink driver predated the project. It also restores the exact EVDI configuration backed up by revision 0.3.x and removes only package-marked interrupted overrides.

## Protected files

The installer snapshots and compares:

- LightDM configuration;
- the desktop user's AccountsService record;
- PAM configuration;
- SSH daemon configuration;
- tty1 and tty7 getty overrides;
- `default.target`;
- `display-manager.service`.

If any protected content changes, the installer restores the snapshot and fails closed.

## Hardware boundary

USB authorization is a Linux userspace/kernel control. It does not remove the 5 V physical power draw before Linux starts. A separately powered USB 3 hub is therefore required for a system that stalls before SSH becomes available with this 8 W monitor attached directly.

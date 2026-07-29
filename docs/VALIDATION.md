# Validation record for 0.2.3

The user-provided 0.2.2 status report showed:

- local session `1`, UID 1000, class `user`, type `wayland`, active and non-remote;
- compositor `labwc` running;
- the AOC device connected as `17e9:ff10`;
- EVDI installed but not loaded;
- DisplayLinkManager not running;
- no files in `/run/aoc-i1659fwux-displaylink`;
- broker log waiting for an XDG autostart request.

This proves the driver build and USB detection were present while the request
helper was the failed condition. Version 0.2.3 removes that condition and makes
the broker use the same verified `loginctl` session information directly.

Static and simulated tests are recorded in the release validation report beside
the downloadable ZIP. Physical Raspberry Pi and monitor testing remains
required.


An additional shell parsing defect was caught before release: because the
scripts intentionally use newline/tab as their global `IFS`, `read -r sid _`
did not split the space-separated `loginctl list-sessions` output. It treated
the complete line as the session ID. Version 0.2.3 now extracts the first field
with `awk` and reads one session ID per line. The corrected broker was simulated
against the user's exact three-session pattern and successfully transitioned
from `waiting` to `running`, then stopped and unloaded EVDI when the graphical
session ended.

# Embedded StikDebug integration

PocketJ Launcher 1.2 contains a modified, Objective-C integration derived
from the StikDebug on-device tunnel and DebugProxy workflow.

- Upstream: https://github.com/StikDebug/StikDebug
- Upstream license: GNU AGPL-3.0
- PocketJ changes: UIKit settings surface, current-process attachment,
  iOS 14-compatible availability boundaries, and bilingual UI.

The StikDebug RemotePairing workflow itself requires iOS 17.4 or later, a
valid pairing file for the current device, and a loopback route such as
LocalDevVPN. PocketJ remains launchable on iOS 14 through iOS 17.3, but the
embedded StikDebug feature is unavailable there.

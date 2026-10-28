# v1.5 update detection and release checklist

## Repository and version contract

- The pre-change v1.5 checker was byte-identical to v1.4 and queried
  `https://api.github.com/repos/EricoEC/PocketJLauncher/releases/latest`.
- v1.5 now queries the **same repository's public Releases API**, walks pages
  of 100, and selects the highest stable numeric launcher version. Accepted
  tags are `v1.5`, `V1.5`, `1.5`, `v1.5.1` and up to four numeric components.
  Drafts, prereleases, `pairing-tool-*`, beta/RC and malformed tags are excluded.
  `v1.5.0` and `v1.5` compare equal. Source order and the Latest badge do not
  determine the v1.5 result.
- Requests bypass URL caching, use no embedded GitHub credentials and have a
  12-second per-page timeout. A 20-page safety limit reports a failed check
  without overwriting cached state, rather than asserting an incomplete result.
- A bare Git tag is not a release. Publish the corresponding stable Release.
  Existing **v1.4 installations still use `/latest`**: mark launcher v1.5 Latest
  and leave pairing-tool releases non-Latest (preferably prerelease). This
  change cannot retroactively patch already-installed v1.4 code.

## Cache, prompts and manual checks

- Preserve existing `PocketJCachedRelease`, `PocketJLastKnownUpdateState` and
  installed-version cache keys. Success updates the last known state; network,
  HTTP, parsing and pagination failures leave it intact. Automatic errors are
  silent; manual errors produce feedback.
- Check on launcher creation and foreground activation. Do not run a launcher
  foreground check over a detached launcher controller while a game is running.
  A successful update decision (or cached update after automatic network
  failure) can show one prompt per foreground session, subject to policy.
- **Update Now** opens a native source selector with the two user-specified
  fixed destinations, not a URL supplied by remote release metadata:
  - GitHub Releases: https://github.com/EricoEC/PocketJLauncher/releases
  - 123 Cloud Drive: https://1842976282.share.123pan.cn/123pan/5B6UTd-KLi1A
- **Remind Me Later** persists a three-hour deadline for that version. It does
  not schedule an in-app timer to interrupt the user at three hours; the next
  foreground launch/check after the deadline can prompt again.
- **Skip This Version** persists its normalized version across launches. A
  different newer version remains eligible. Prompt suppression does not erase
  the fact that an update exists or conflate it with “up to date”.
- Manual Settings checks always request the API (or join a real in-flight
  request) and bypass both skip and cooldown when a newer release is returned.
  A current version shows “up to date”; failure shows an error. Banner taps also
  use the same three-action update UI. Duplicate/modal presentation is queued,
  with a native iPad popover anchor and bilingual strings.

## Verification and release boundary

Run `node Tests/update-tests.mjs` for deterministic tests; `--live` additionally
calls the actual unauthenticated GitHub API using the production checker.
On 2026-10-28 the live checker selected `v1.4`, correctly excluding the published
`pairing-tool-v1.0`. A v1.5 test app therefore currently should not advertise an
update. No fake release/tag was published to test the UI.

Deterministic coverage includes release filtering, version comparison, paging,
cache restore, offline/schema failures, exact three-hour boundary, persisted
skip, newer-version eligibility, manual override, concurrent requests, UI
action/source wiring, localization and iPad anchoring.

Build/test success is not a complete release acceptance claim. The user's last
reported 26.3 menu freeze has not yet received a successful device retest, and
the new alert/source-selection UI still needs interactive device acceptance.
No publication, push or dependency upgrade is part of this task.

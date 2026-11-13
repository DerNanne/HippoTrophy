# export

What HippoTrophy Desk, the web app for the big screen, takes from this app
instead of drawing or counting it a second time. Written by
`HippoTrophyTests/Export/DeskExportTests.swift`; the web app keeps a copy and
tests its own code against it.

- `outlines.json` — the body outlines of the muscle heat map, as SVG path
  data in a 200 × 440 box: each figure (male, female) from the front and the
  back. Draw `hairBehind`, then `body`, then `muscles`, then `hair`.
- `coverage-expected.json` — what the app makes of
  `HippoTrophyTests/Backup/CoverageBackup.json`, counted at `now` in UTC with
  weeks from Monday: each workout's sets, the sets a day, the sets per muscle
  group for every heat-map period (all categories, and Strength alone), and
  the progress points of every exercise for every metric it offers. Weights
  are in kilograms.

`exportIsCurrent` fails when the app counts or draws differently from these
files. If the change is meant, write them anew and take them over into the
web app:

```
TEST_RUNNER_WRITE_DESK_EXPORT=1 xcodebuild test -project HippoTrophy.xcodeproj \
  -scheme HippoTrophy -destination 'platform=iOS Simulator,name=iPhone 17' \
  '-only-testing:HippoTrophyTests/DeskExportTests/writeTheExport()'
```

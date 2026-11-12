# HippoTrophy

A workout log for hypertrophy and strength training, native for iPhone.
Everything stays on the device: no account, no server, no analytics. A
backup is a file you export yourself.

- Privacy policy: https://dernanne.github.io/hippotrophy-web/datenschutz.html
- Support: https://dernanne.github.io/hippotrophy-web/support.html

## Building

Requires Xcode 26.5 or later; the app runs on iOS 26.5 and up. There are no
package dependencies.

Open `HippoTrophy.xcodeproj` and run the `HippoTrophy` scheme in a
simulator. To run on a device, set your own team and bundle identifier
under Signing & Capabilities.

## Tests

```bash
xcodebuild test -project HippoTrophy.xcodeproj -scheme HippoTrophy -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

`HippoTrophyTests/` mirrors the folders of `HippoTrophy/`. Logic that turns
data into a decision (import merging, summaries, formatting) lives in plain
types without SwiftUI or `ModelContext`, and is tested there; views only
apply those decisions.

## Data on devices and in backups

Devices and backup files hold data from every earlier version of the app,
so both are versioned:

- **Store:** every change to a model is a new `SchemaV<N>` with a migration
  stage in `AppMigrationPlan`, and a store file written once and kept in
  `HippoTrophyTests/App/`. `StoreFixtureTests` opens every one of them.
- **Backup:** every change to the format raises
  `BackupFile.currentFormatVersion`, freezes the old format as its own type
  and converts it one step forward. `CoverageBackup.json` holds everything
  a backup can contain; older copies stay beside it as
  `CoverageBackup-v<N>.json`.

## Contributing

Issues are welcome. A pull request is accepted under two conditions, and
you confirm both by adding a `Signed-off-by: Your Name <email>` line to
each commit (`git commit -s`):

1. You wrote the contribution yourself, or have the right to submit it,
   and it is licensed under the GNU AGPLv3 like the rest of the code.
2. You grant Yannik Wölfl a non-exclusive, perpetual and irrevocable
   permission to distribute the contribution, changed or unchanged, as part
   of HippoTrophy on Apple's App Store and TestFlight under Apple's terms.

## License

Copyright © 2026 Yannik Wölfl

Everything in this repository is licensed under the
[GNU Affero General Public License v3.0 only](LICENSE)
(SPDX: `AGPL-3.0-only`): the source code, the exercise catalog, the
pictograms and other images, the documentation and the test data.

The one exception is the app's identity: the name HippoTrophy, the app icon
(`HippoTrophy/Resources/Assets.xcassets/AppIcon.appiconset`) and the hippo
(`HippoTrophy/Resources/Assets.xcassets/ReportAppMark.imageset`). They are
not licensed under the AGPL; under section 7(e) of the license, no rights to
them are granted. All rights reserved. A version you distribute needs a
name and an icon of its own.

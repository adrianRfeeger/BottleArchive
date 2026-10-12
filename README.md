# Bottle Archive

Bottle Archive creates CrossOver bottle backups with a native Mac interface, estimated archive size, compression choices, progress and cancellation. It requires macOS 15 or newer, an Apple silicon Mac and an installed CrossOver app.

Open `dist/Bottle Archive.app`, or unzip `dist/BottleArchive-1.1.1-arm64.zip` and open the app inside. You can move the app into Applications. This is a locally signed owner build.

## Create a backup

1. Close the selected bottle's Windows applications in CrossOver.
2. Choose the bottle and destination folder. The initial destination is `/Volumes/External/Crossover Archives`; the app remembers later choices.
3. Choose Fast, Balanced or Maximum compression, and a thread count. Automatic uses all but two available CPU cores when possible. The estimated size comes from a bounded sample and can differ from the final archive.
4. Choose Create Archive. The app reports creation and verification separately. Reveal in Finder opens the finished file.

Fast uses gzip level 1, Balanced level 6 and Maximum level 9. Each produces a `.cxarchive` file. Existing archives are kept, and each new filename includes the bottle name and date/time. The app streams to the destination without making an uncompressed copy of the bottle. Compression uses the bundled parallel gzip helper. More threads can speed up compression; source reading, destination writing and verification may still limit the total speed.

## Restore

In CrossOver, choose Bottle > Import Bottle Archive and select the completed `.cxarchive` file. The app's test suite creates and restores a disposable bottle with CrossOver itself at all three compression levels.

Symbolic links stay links. Files in linked folders outside the bottle are not included. For Skyrim, also back up `~/Documents/My Games/Skyrim Special Edition`, including saves and game INI files.

## Cancel or recover

Cancel stops this app's archive processes. Existing backups remain available. An interrupted job removes its own partial file when possible. If a drive disconnects, a hidden `.BottleArchive-….partial` file may remain on it; reconnect the drive and remove that incomplete file. A completed archive only receives the `.cxarchive` extension after verification.

If the app reports that the bottle is running, close its Windows applications through CrossOver before retrying. If the destination is unavailable, reconnect the drive or choose another folder. Keep the app open while archiving; it prevents idle system sleep during the job.

## Privacy

The app processes file contents locally and does not upload them. It stores selected folders, compression and window layout in its preferences, and small local result records under `~/Library/Application Support/BottleArchive/Results`. Diagnostics show technical status without file contents, full paths or account details. You preview them before copying.

## Development

```sh
./script/build_and_run.sh --verify
swift test --build-system native
BOTTLE_ARCHIVE_INTEGRATION=1 swift test --build-system native --filter CrossOverRoundTripTests
./script/package.sh
```

The project is independent of the bottles it archives. The build script stages a normal app bundle and refuses to rebuild while the running app has an active archive job. CrossOver is used from its installed location and is not included in this app.

The app uses macOS zlib and libarchive. Public libarchive headers are included because the macOS SDK ships the library without its headers; their BSD licence notices are preserved in `Sources/CArchive/headers`. The source does not depend on Homebrew at runtime.

Parallel compression uses pigz 2.8 by Mark Adler, built from the pinned official source and linked to macOS libraries. The upstream licence is included in the app and under `Vendor/pigz`.

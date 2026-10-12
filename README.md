# Bottle Archive

Spend less time compressing CrossOver backups. Bottle Archive puts your Mac's CPU cores to work, with a native interface for choosing speed or a smaller archive, tracking progress and creating a verified `.cxarchive` you can restore in CrossOver.

On an 18-core Apple M5 Pro, Balanced compression of a 256 MiB test fixture fell from **1.70 seconds to 0.14 seconds** with Automatic's 16 workers: about **12 times faster compression** than the original single-thread compressor.

| Compression test | Workers | Median time |
| --- | ---: | ---: |
| Original macOS gzip | 1 | 1.700 s |
| Bottle Archive, Automatic | 16 | 0.144 s |
| Bottle Archive, all available cores | 18 | 0.134 s |

The benchmark used equal portions of random and repeating data, three runs per case, and discarded output to isolate compression speed. Full backup time also depends on drive speed, bottle contents and verification. [Method and results](docs/verification.md#compression-benchmark).

The app also has a sampled size estimate, elapsed and remaining time, and cancellation. It verifies the compressed archive and bottle structure before publishing the finished file. Existing archives are kept.

## Download

[Download the universal macOS app](https://github.com/adrianRfeeger/BottleArchive/releases/latest). One app contains both Apple silicon and Intel executables, including the bundled parallel compressor. Published release builds are Developer ID signed and notarised.

## Requirements

- macOS 15 or later on Apple silicon or Intel.
- An installed copy of CrossOver. Compatibility has been tested with CrossOver 26.3.
- Xcode Command Line Tools and a Swift 6 toolchain to build from source.

CrossOver is an external dependency and is not included in this repository.

## Build and run

```sh
git clone https://github.com/adrianRfeeger/BottleArchive.git
cd BottleArchive
./script/build_and_run.sh
```

The script builds the app and its compression helper, signs them locally, and opens `dist/Bottle Archive.app`. You can move the app to Applications. Local builds are ad hoc signed and are not notarised.

To create a Release app and ZIP:

```sh
./script/package.sh
```

The current package is `dist/BottleArchive-1.1.1-universal.zip`. The packaging script builds both architectures and combines the app and compression helper. Build output is excluded from Git. The build script refuses to rebuild while this app has an active archive job.

For Developer ID signing and notarisation, provide your own certificate and an existing `notarytool` keychain profile:

```sh
BOTTLE_ARCHIVE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
BOTTLE_ARCHIVE_NOTARY_PROFILE="your-notary-profile" \
./script/package.sh
```

The script checks Apple's result, staples the accepted ticket to the app, checks Gatekeeper, then packages the app and writes a `.sha256` checksum file. Credentials stay in your Keychain.

## Create a backup

1. Close the selected bottle's Windows applications in CrossOver.
2. Choose a bottle and a destination folder. The app discovers the usual CrossOver bottle locations and also lets you choose a bottle manually.
3. Choose a compression level and thread count.
4. Choose **Create Archive**. The app reports creation and verification separately, then lets you reveal the finished archive in Finder.

The app remembers the selected folders, compression level and thread count. Its initial destination is `/Volumes/External/Crossover Archives`; choose another folder if that location does not exist.

| Compression | gzip level | Tradeoff |
| --- | ---: | --- |
| Fast | 1 | Less compression time, usually a larger archive |
| Balanced | 6 | A balance of compression time and size |
| Maximum | 9 | More compression work, usually a smaller archive |

Automatic uses two fewer compression workers than the available CPU cores when there are more than two cores. You can also select a count manually, up to the available core count. More threads can speed up compression, while reading the bottle, writing to the destination and verification may still limit the total time.

Size estimates use a bounded sample and may differ from the final archive. The app streams directly to the destination without making an uncompressed copy of the bottle. New filenames contain the bottle name and date/time, with a suffix if needed to keep an existing file.

## Restore a backup

In CrossOver, choose **Bottle > Import Bottle Archive** and select the completed `.cxarchive` file.

Symbolic links remain links. The archive does not include files in linked folders outside the bottle. Back up those files separately. For Skyrim, this can include saves and game settings under `~/Documents/My Games/Skyrim Special Edition`.

## Cancel and recover

Cancel stops this app's archive processes. It removes its incomplete file when the destination is still accessible, and keeps existing backups.

If a drive disconnects, a hidden `.BottleArchive-….partial` file may remain. Reconnect the drive and remove that incomplete file. The app assigns the `.cxarchive` extension only after verification succeeds.

If the app reports that the bottle is running, close its Windows applications in CrossOver before retrying. If the destination is unavailable, reconnect the drive or choose another folder. Keep the app open while archiving; it prevents idle system sleep during the job.

## Privacy

File contents are processed locally and are not uploaded. The app stores preferences and small result records under `~/Library/Application Support/BottleArchive/Results`. Diagnostics contain technical status without file contents, full paths or account details, and can be previewed before copying.

## Tests

```sh
swift test --build-system native
```

The CrossOver integration test is enabled separately. It creates a disposable bottle, exports all three compression levels with the bundled parallel compressor, restores each through CrossOver, and checks fixture hashes, permissions, empty files and symbolic links:

```sh
BOTTLE_ARCHIVE_INTEGRATION=1 swift test --build-system native --filter CrossOverRoundTripTests
```

The app's verification and benchmark record is in [docs/verification.md](docs/verification.md). The recorded compression benchmark uses synthetic data and does not measure a complete Skyrim backup.

## Licence

Bottle Archive's original code is available under the [MIT licence](LICENSE), copyright 2026 Adrian Feeger.

Included dependencies retain their own licences. Parallel compression uses [pigz 2.8](https://www.zlib.net/pigz/) by Mark Adler. The libarchive headers retain their BSD notices; the app links macOS's system zlib and libarchive libraries. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [Vendor/pigz/UPSTREAM.md](Vendor/pigz/UPSTREAM.md).

Bottle Archive is an independent utility and is not affiliated with CodeWeavers.

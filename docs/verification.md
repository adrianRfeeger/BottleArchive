# Verification record

Tested on Adrian's Apple silicon Mac on 12 and 13 October 2026 with the installed CrossOver 26.3.

## Automated checks

- Bottle scanning excludes CrossOver's `files` and `desktopdata`, counts hard-linked contents once and does not follow external symbolic links.
- Preflight rejects invalid bottles and destinations that resolve inside the bottle.
- Bounded size sampling covers compressible, incompressible and mixed files, levels 1/6/9, cancellation and a file replaced by a symbolic link.
- Subprocess tests cover exit status, bounded errors, orphaned pipes and cancellation that preserves unrelated processes.
- Archive tests reject corrupted/truncated gzip files, a missing bottle configuration and extra roots.
- Export tests cover successful verified publication, exporter/compressor failures, a missing destination, duplicate starts, cancellation and preservation of an existing archive.
- View-model tests cover defaults, remembered preferences, saved/manual selection, publication ordering, stale estimate rejection, missing destinations and busy cancellation.
- CrossOver created a disposable fixture bottle. The app exported it at all three compression levels, and CrossOver restored each archive into isolated temporary locations. File hashes, mode 0640, empty files, external link targets and the bottle configuration file were checked. The final engine was retested on 13 October. The parallel compressor restored Fast with 1 thread (122,506,466 bytes), Balanced with 16 threads (113,001,809 bytes) and Maximum with 18 threads (112,420,670 bytes). All three restorations passed.

## Interactive checks

- Inspected the actual native GUI in dark and light appearance using separate QA copies.
- Observed a 21 MB fixture estimate, Creating archive at 5% with written bytes/elapsed/remaining, cancellation returning Cancelled and removal of its partial file.
- A second GUI job displayed Verifying at 79%, then Archive complete with actual size and Reveal in Finder. The existing fixture archive was unchanged.
- Inspected Help and About, plus the enlarged window layout. Fixed a startup publication-order issue after a failing regression test.

## Delivery

- Built and signed a fresh Release app. Extracted its ZIP into a separate directory and validated identifier/version, macOS 15 minimum, arm64 executable, icon, all eight localisation resources, signature and system-only runtime dependencies.
- The ZIP is approximately 1.32 MB. The extracted app displayed its native window, estimate and compression controls, then created a verified 21 MB fixture archive. Reveal in Finder selected the finished file, which Finder identified as a CrossOver Bottle Archive.
- Restored the original Skyrim selection after the packaged-app test. No full-size Skyrim archive was created by these tests.
- Independent review found two material issues: a compression failure could leave the job waiting for a paused exporter, and the destination check lacked a test during an active job. The fix observes compression exit concurrently and stops the exporter on failure. A regression reproduced the original failure before the fix, then passed in under a second. A second test replaces the destination during export and checks the specific destination error, process exit, preservation of existing files and absence of a published archive.
- The final standard suite passed 39 regular tests. The declared integration test runs only with `BOTTLE_ARCHIVE_INTEGRATION=1`; its actual three-level restore result is listed above. The reviewer raised no minor findings.

## Implementation decisions

- Used a separate project worktree because this chat's worktree tool targets the Skyrim bottle. This requires local adoption into the Development project at delivery.
- Used SwiftPM's native build system for faster incremental checks on the installed toolchain. Its deprecated flag may need adjustment with a future Swift release.
- Included upstream BSD-licensed libarchive headers while linking the macOS library, because the SDK omits those headers. These declarations need maintenance if the system ABI changes.
- Kept presentation state in a small separate target for asynchronous state tests. This adds one target to the project.
- Used a debug-only light appearance preview for GUI checks. It adds a debug code path; the delivered Release follows system appearance.

## Parallel compression update

On 13 October 2026, the app added a Threads menu. Automatic uses 16 compression workers on this 18-core Mac. Manual counts from 1 to 18 are available. The setting is remembered, stays disabled during a job and does not restart the size estimate.

Four additional behavioral tests ran and failed before implementation, then passed. They cover automatic/manual limits, compressor arguments, end-to-end job forwarding and preference persistence without resampling. The actual CrossOver integration test forced the pigz helper at 1, 16 and 18 threads, and restored all three archives successfully. The extracted Release app completed a fixture archive at 18 threads and displayed verification and completion. The GUI menu and updated layout were inspected; the Skyrim selection and Automatic setting were restored after testing.

A focused independent review found no material issues. It confirmed that vendored sources exactly match the pinned official pigz archive, the packaged helper is arm64 with system-only libraries, and the app's deep/strict signature passes.

The bundled pigz helper is an additional maintained dependency. Its original source and licence are included; a future update requires checksum, build, signature and compatibility checks.

### Compression benchmark

A disposable 256 MiB fixture contained equal portions of random and repeating data. Each case used Balanced compression, three runs and discarded output to isolate compression speed. These figures do not measure a full Skyrim backup or its verification.

| Compressor | Threads | Median time |
| --- | ---: | ---: |
| Original macOS gzip | 1 | 1.700 s |
| Bundled pigz | 1 | 1.758 s |
| Bundled pigz | 16 | 0.144 s |
| Bundled pigz | 18 | 0.134 s |

Automatic was about 11.8 times faster than the original compressor in this test. Reading the bottle, writing to the destination and verifying the archive can limit the total backup speed.

The delivered app and helper matched the extracted GUI-tested Release byte for byte. The final source suite passed after adoption into the Development project. Version 1.1 (2) includes both signed arm64 executables and all eight language resources.

## App relocation fix

Version 1.1.1 (3) fixes an error after moving the running app into Applications. The helper was embedded correctly, but the archive job cached its old location. Helper resolution now happens when each job starts and uses the running executable's current filesystem path, with the bundle and development locations as fallbacks.

Two regression tests failed before the fix, including the exact `Could not start pigz: No such file or directory` failure. They now pass, and the standard suite reports 40 declared tests (39 regular tests and the separately enabled CrossOver integration case).

The fixed installed app in `/Applications` created and verified a 21 MB fixture archive with Automatic (16) threads. Its app and helper executables matched the extracted 1.1.1 ZIP byte for byte, and the signature passed. Skyrim selection and normal launch settings were restored after the test. The actual running process path was independently checked after a temporary app moved; native UI automation could not address that moved process, so the live-move behavior is covered by the regression tests rather than an interactive acceptance claim.

## Universal GitHub release

The 1.1.1 universal release contains `arm64` and `x86_64` slices in both the app and the pigz helper. Both slices target macOS 15. The exact ZIP was extracted and checked for its bundle metadata, icon, eight localisations, licences, system-only libraries, checksum and both executable architectures.

The app and helper are Developer ID signed with hardened runtime and a secure timestamp. Apple accepted notarisation, the ticket was stapled to the app, and the extracted ZIP passed strict signature, staple and Gatekeeper validation (`source=Notarized Developer ID`).

The standard Apple silicon suite passed 39 regular tests, with the separately enabled CrossOver integration case skipped. This Xcode installation's SwiftPM test loader is arm64-only, so it could not load the compiled x86_64 test bundle. Intel validation therefore used the exact Release app under Rosetta: its running CPU type was independently confirmed as x86_64, and its GUI created and verified a 21 MB fixture archive. Both helper slices ran successfully. The same extracted app also created and verified a fixture archive in arm64 mode. Native Intel hardware was not available for testing.

Release ZIP: `BottleArchive-1.1.1-universal.zip`, 1,672,700 bytes. SHA-256: `02a3f6f16198d5a761abda507a546ae183b54264d72c7adb5e635ec480a089d1`.

# Verification record

Tested on Adrian's Apple silicon Mac on 12 October 2026 with the installed CrossOver 26.3.

## Automated checks

- Bottle scanning excludes CrossOver's `files` and `desktopdata`, counts hard-linked contents once and does not follow external symbolic links.
- Preflight rejects invalid bottles and destinations that resolve inside the bottle.
- Bounded size sampling covers compressible, incompressible and mixed files, levels 1/6/9, cancellation and a file replaced by a symbolic link.
- Subprocess tests cover exit status, bounded errors, orphaned pipes and cancellation that preserves unrelated processes.
- Archive tests reject corrupted/truncated gzip files, a missing bottle configuration and extra roots.
- Export tests cover successful verified publication, exporter/compressor failures, a missing destination, duplicate starts, cancellation and preservation of an existing archive.
- View-model tests cover defaults, remembered preferences, saved/manual selection, publication ordering, stale estimate rejection, missing destinations and busy cancellation.
- CrossOver created a disposable fixture bottle. The app exported it at all three compression levels, and CrossOver restored each archive into isolated temporary locations. File hashes, mode 0640, empty files, external link targets and the bottle configuration file were checked. Fast: 122,617,190 bytes. Balanced: 113,115,929 bytes. Maximum: 112,527,794 bytes. All three restorations passed.

## Interactive checks

- Inspected the actual native GUI in dark and light appearance using separate QA copies.
- Observed a 21 MB fixture estimate, Creating archive at 5% with written bytes/elapsed/remaining, cancellation returning Cancelled and removal of its partial file.
- A second GUI job displayed Verifying at 79%, then Archive complete with actual size and Reveal in Finder. The existing fixture archive was unchanged.
- Inspected Help and About, plus the enlarged window layout. Fixed a startup publication-order issue after a failing regression test.

## Delivery

- Built and signed a fresh Release app. Extracted its ZIP into a separate directory and validated identifier/version, macOS 15 minimum, arm64 executable, icon, all eight localisation resources, signature and system-only runtime dependencies.
- The ZIP is approximately 1.27 MB. The extracted app displayed its native window, estimate and compression controls, then created a verified 21 MB fixture archive. Reveal in Finder selected the finished file, which Finder identified as a CrossOver Bottle Archive.
- Restored the original Skyrim selection after the packaged-app test. No full-size Skyrim archive was created by these tests.
- Independent review is recorded below once complete.

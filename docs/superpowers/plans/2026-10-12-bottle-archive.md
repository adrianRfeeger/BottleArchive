# Bottle Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution or superpowers:subagent-driven-development if Adrian chooses delegation. Implement task by task and track steps with checkboxes.

**Goal:** Build a small native Mac app that estimates and creates verified CrossOver bottle archives with compression choices, visible progress and cancellation.

**Architecture:** A Swift archive-engine library owns discovery, scanning, estimation, child processes and validation. A SwiftUI app presents its events and remembers user choices. CrossOver supplies the tar stream; gzip writes directly to a temporary file in the destination, and a successful verification permits publication.

**Tech Stack:** SwiftPM, SwiftUI, AppKit, Foundation, IOKit, system zlib and libarchive, a narrow C process bridge, installed CrossOver and macOS gzip.

**Spec:** `docs/superpowers/specs/2026-10-12-bottle-archive-design.md`.

## Global constraints

- Project: `/Users/adrianfeeger/Development/BottleArchive`.
- Default archive folder: `/Volumes/External/Crossover Archives`.
- Target macOS 15 or newer; deliver an Apple silicon app for Adrian's Mac.
- Fast means gzip level 1; Balanced means level 6 and is the default; Maximum means level 9.
- Use installed CrossOver's `cxbottle --tar -`; retain its bottle layout, exclusions and symbolic links.
- Scan and sample without following symbolic links. Keep sampled contents in memory.
- Archive progress is approximate and stays below completion until verification succeeds.
- Existing archives are never replaced. Publish only a verified job-owned `.partial` file.
- Do not silently force-close Windows applications. Block another job while one is active.
- Preserve the live bottle. Perform restore tests only in disposable, isolated fixture locations.
- Use native controls, system appearance, keyboard access and localised strings. The approved personal-utility exceptions are a single icon, direct main window and configuration in that window.
- Localisation keys cover `en`, `fr`, `de`, `es`, `it`, `ja`, `zh-Hans` and `pt-BR`, matching Adrian's existing app standards. Format sizes, dates and durations using the user's locale.
- Bundle identifier: `com.adrianfeeger.BottleArchive`; display name: `Bottle Archive`; initial version/build: `1.0`/`1`.

## Review focus

1. A destination symlink points inside the bottle: resolve paths and reject it before creating output. Task 1 owns the test.
2. The destination disconnects, fills up or becomes unwritable mid-job: fail without publishing an archive and keep the UI responsive. Task 3 owns injected I/O failure tests.
3. The user changes bottle or compression during estimation: discard stale results and cancel obsolete work. Task 5 owns the state test.
4. A failed child leaves descendants or a blocked pipe: cancel only this job's process groups, drain errors concurrently and reap children. Task 3 owns the cancellation test.
5. A long Unicode path or an external link appears in the archive: validate through libarchive, preserve the link and restore the supported metadata. Tasks 4 and 6 own these tests.

## File map

- `Package.swift`, `.gitignore`: library, GUI and test targets; exclude build and distribution output.
- `Sources/ArchiveEngine/ArchiveModels.swift`: typed requests, stages, progress, results and errors.
- `Sources/ArchiveEngine/BottleDiscovery.swift`, `BottleScanner.swift`, `ArchivePreflight.swift`: locate bottles, enumerate metadata and check destination.
- `Sources/ArchiveEngine/SizeEstimator.swift`: bounded compression sampling and weighted size estimate.
- `Sources/CZlib/module.modulemap`, `shim.h`: system zlib import and linkage.
- `Sources/CArchive/module.modulemap`, `shim.h`: system libarchive import and linkage.
- `Sources/ProcessSupport/include/ProcessSupport.h`, `ProcessSupport.c`: POSIX spawn, process groups and signal-safe pipe handling.
- `Sources/ArchiveEngine/OwnedProcess.swift`, `ArchiveJob.swift`, `ArchiveVerifier.swift`: streaming export, job lifecycle and validation.
- `Sources/BottleArchive/BottleArchiveApp.swift`, `ArchiveViewModel.swift`, `ContentView.swift`, `WindowSupport.swift`, `SupportViews.swift`: native interface and supporting windows.
- `Sources/BottleArchive/Resources/<language>.lproj/Localizable.strings`: app and Help copy in the eight languages above.
- `Tests/ArchiveEngineTests/Fixtures.swift`, `DiscoveryTests.swift`, `ScannerTests.swift`, `EstimatorTests.swift`, `JobTests.swift`, `VerifierTests.swift`, `CrossOverRoundTripTests.swift`: meaningful engine and integration coverage.
- `Tests/BottleArchiveStateTests/ViewModelTests.swift`: selection, estimation and job state transitions in a small testable presentation-state target if required by SwiftPM executable testing limits.
- `script/build_and_run.sh`, `script/package.sh`, `script/create_icon.swift`: build, stage, sign, launch and package the local app.
- `.codex/environments/environment.toml`, `README.md`, `docs/verification.md`: Run action, usage and recorded delivery checks.

## Task 1: Bottle discovery, scanning and preflight

**Interfaces produced:** `CompressionPreset` with `gzipLevel: Int`; `Bottle(url: URL)` with `name`; `BottleSnapshot` with `bottle`, `logicalBytes: UInt64`, `archiveInputEstimate: UInt64`, `fileCount: Int`, `files: [FileSampleCandidate]` and `externalLinks: [URL]`; `ArchiveError` with actionable categories.

`BottleDiscovery.discover(home: URL, configuredRoots: [URL]) throws -> [Bottle]` deduplicates canonical paths. `BottleScanner.scan(_ bottle: Bottle) async throws -> BottleSnapshot` runs off the main thread. `ArchivePreflight.validate(bottle: Bottle, destination: URL) throws` rejects an invalid bottle, unreadable source, unavailable/unwritable destination or a destination inside the resolved bottle path.

- [ ] Add failing tests and their fixture helpers for custom bottle locations, missing `cxbottle.conf`, CrossOver's `files`/`desktopdata` exclusions, external symlinks, hard-link accounting, cancellation and a destination symlink into the bottle. Assertions include:

```swift
#expect(CompressionPreset.balanced.gzipLevel == 6)
#expect(snapshot.logicalBytes == fixture.regularFileBytes)
#expect(snapshot.externalLinks.count == 1)
#expect(throws: ArchiveError.self) {
    try ArchivePreflight.validate(bottle: fixture.bottle, destination: fixture.insideBottleLink)
}
```

- [ ] Run `swift test --filter 'DiscoveryTests|ScannerTests'` and confirm the new assertions fail before implementation.
- [ ] Create the package, models, fixture helpers and the three engine files. Use `lstat`/resource metadata, skip links, account for hard links once and estimate tar headers separately from regular contents. Read CrossOver's `BottleDir` preference and usual roots, including `~/cxbottles`, while supporting a manually chosen bottle. Use structured paths throughout.
- [ ] Run the same tests; require all to pass. Commit `feat: discover and inspect CrossOver bottles`.

## Task 2: Estimated compressed size

**Consumes:** `BottleSnapshot` and `CompressionPreset` from Task 1.
**Produces:** `ArchiveSizeEstimate(estimatedBytes: UInt64, sampledBytes: UInt64, gzipLevel: Int)` and `SizeEstimator.estimate(snapshot: BottleSnapshot, compression: CompressionPreset) async throws -> ArchiveSizeEstimate`.

- [ ] Add failing tests for compressible text, incompressible data, a mixed bottle, changing levels, unreadable samples, external links and cancellation. Pin a maximum sample budget of 64 MiB and avoid asserting an exact final size:

```swift
#expect(textEstimate.estimatedBytes < textSnapshot.archiveInputEstimate)
#expect(randomEstimate.estimatedBytes > randomSnapshot.logicalBytes / 2)
#expect(estimate.sampledBytes <= 64 * 1024 * 1024)
#expect(maximumEstimate.gzipLevel == 9)
#expect(fastEstimate.gzipLevel == 1)
```

- [ ] Run `swift test --filter EstimatorTests`; confirm failure before implementation.
- [ ] Implement the estimator and CZlib module. Group files by extension and size band, prioritise strata by represented bytes, and sample up to 1 MiB per chunk from the beginning, middle and end of eligible large files. Use zlib at the chosen level, weight ratios by stratum bytes, treat unsampled strata conservatively as uncompressed and add estimated tar framing. Stop at 64 MiB sampled; check cancellation between reads. A sampling failure produces an unavailable estimate without invalidating the bottle.
- [ ] Run `swift test --filter EstimatorTests`; require all to pass. Commit `feat: estimate archive size from bounded samples`.

## Task 3: Streaming export and owned cancellation

**Consumes:** Task 1 models and snapshot.
**Produces:** `ArchiveRequest(bottle: Bottle, destination: URL, compression: CompressionPreset, crossOverApp: URL)`; `ArchiveProgress(stage: ArchiveStage, fraction: Double?, processedBytes: UInt64, outputBytes: UInt64, elapsedSeconds: Double, remainingSeconds: Double?)`; `ArchiveJob.start(request: ArchiveRequest, snapshot: BottleSnapshot) -> AsyncThrowingStream<ArchiveEvent, Error>` and `ArchiveJob.cancel()`; events `.progress(ArchiveProgress)` and `.completed(ArchiveResult)`.

- [ ] Add failing tests using executable fixtures for exporter failure, compressor failure, full/unwritable destination injection, collision-free names, bounded stderr capture, duplicate starts and cancellation with child descendants. Assert that no final file appears on failure and an unrelated sentinel process keeps running:

```swift
#expect(!fixture.finalArchiveExists)
#expect(fixture.ownedProcessesHaveExited)
#expect(fixture.unrelatedProcessIsRunning)
#expect(fixture.existingArchiveContents == fixture.originalArchiveContents)
#expect(progress.stage != .completed || fixture.verificationSucceeded)
```

- [ ] Run `swift test --filter JobTests`; confirm failure before implementation.
- [ ] Implement `OwnedProcess` and the C bridge with POSIX spawn arguments/environment arrays and a separate process group per owned process. Suppress SIGPIPE crashes and report broken-pipe errors. Drain each stderr pipe concurrently with a 64 KiB retained tail. Cancellation terminates only recorded groups, escalates after a bounded grace period, closes pipes and reaps children.
- [ ] Implement `ArchiveJob`: resolve CrossOver, set `CX_BOTTLE_PATH` to the selected bottle's parent, reject an active selected bottle, repeat preflight, reserve a unique timestamped partial file and connect exporter stdout to gzip stdin through a byte-counting relay. Use gzip levels 1/6/9 with `-n -c`; direct gzip stdout to that file. Start with `Preparing`, show approximate byte progress capped at 99%, and compute ETA only after enough throughput data. Require both exit statuses to be successful. Invoke Task 4 verification before publication. Hold and release an IOKit idle-sleep assertion for the job.
- [ ] Keep completed output reserved against races: atomically move the verified partial file to its unique final name without replacement. Remove only this job's incomplete file after cancellation/failure when the destination remains reachable; explain when it cannot be removed. Save a concise local result and privacy-safe diagnostic categories.
- [ ] Run `swift test --filter JobTests` after Task 4 is available; require all to pass. Commit `feat: stream bottle archives with progress and cancellation`.

## Task 4: Archive verification

Implement this before closing Task 3's test cycle because publication depends on it.

**Consumes:** Task 3 process wrapper and progress callback.
**Produces:** `ArchiveVerifier.verify(url: URL, expectedBottleName: String, progress: @Sendable (Double) -> Void) async throws -> VerificationResult`; result contains `entryCount: Int`, `bottleName: String` and `verifiedBytes: UInt64`.

- [ ] Add failing tests for a valid archive, gzip checksum corruption, truncation, missing configuration, multiple roots, traversal names, a long Unicode path and a symbolic link to an external directory:

```swift
#expect(validResult.bottleName == fixture.bottle.name)
#expect(validResult.entryCount > 0)
#expect(throws: ArchiveError.self) { try await verify(fixture.truncatedArchive) }
#expect(throws: ArchiveError.self) { try await verify(fixture.multipleRootArchive) }
#expect(fixture.externalTargetWasNotRead)
```

- [ ] Run `swift test --filter VerifierTests`; confirm failure before implementation.
- [ ] Use an owned `gzip -t` process to check the entire compressed stream, feeding it in bounded chunks and measuring compressed bytes for the first half of verification progress. Then use libarchive's gzip/tar reader to validate every entry without extraction, measuring its input callback bytes for the second half. Support PAX/GNU long names through libarchive. Require one normalised bottle root and a regular `cxbottle.conf`; reject traversal or extra roots while allowing external link targets to remain links. Capture file identity/metadata before and after validation to reject replacement or modification during verification. Both passes honour cancellation.
- [ ] Run `swift test --filter 'VerifierTests|JobTests'`; require all to pass. Commit `feat: verify archives before publishing them`.

## Task 5: Native interface and preferences

**Consumes:** Tasks 1-4 public interfaces.
**Produces:** `@MainActor ArchiveViewModel` with `selectBottle(_:)`, `setCompression(_:)`, `estimateSize()`, `createArchive()`, `cancel()` and observable selection, estimate, progress, result and error states.

- [ ] Add failing state tests for selecting a bottle, changing compression, stale estimate rejection, missing external drive, a second start while busy, cancellation and completion. Assert:

```swift
#expect(model.compression == .balanced)
#expect(model.destination.path == "/Volumes/External/Crossover Archives")
#expect(model.estimate?.gzipLevel == model.compression.gzipLevel)
#expect(!model.canCreateArchiveWhenBusy)
#expect(model.completedResult == nil || model.completedResult!.verified)
```

- [ ] Run `swift test --filter ViewModelTests`; confirm failure before implementation.
- [ ] Build the compact SwiftUI window and state model. Use native `NSOpenPanel` pickers for bottles, destination and CrossOver. Cancel obsolete estimates and reject responses using a selection generation token. Display source size, approximate archive size, stage/progress, output size, elapsed time, ETA, Cancel and Reveal in Finder. Surface the external-link backup note when relevant. Persist destination/compression and clamp restored window geometry to available displays. Keep filesystem work off the main actor.
- [ ] Implement native menus, compact About and Help, locale-aware formatting, keyboard shortcuts and accessibility labels. Provide a close/quit choice for an active job and preview privacy-safe diagnostics before copying. Keep strings in the eight localisation folders. Use the approved single icon and direct main-window settings exception; no commerce or account is needed for this personal app.
- [ ] Run `swift test --filter ViewModelTests`; require all to pass. Stage and launch the actual `.app` using `script/build_and_run.sh --verify`. Inspect native UI in light and dark modes, tab through controls, alter and relaunch the window, and exercise estimation, selection and cancellation on disposable fixture data. Commit `feat: add native bottle archive interface`.

## Task 6: CrossOver restore proof and app delivery

**Consumes:** Completed app and engine.
**Produces:** `dist/Bottle Archive.app`, `dist/BottleArchive-1.0-arm64.zip`, usage instructions and verification record.

- [ ] Add `CrossOverRoundTripTests` guarded by explicit `BOTTLE_ARCHIVE_INTEGRATION=1`. Create a small temporary bottle using the installed `cxbottle --create` in an isolated `CX_BOTTLE_PATH`, populate text/binary/empty files, long Unicode names, a permission fixture and an external symbolic link. Define the fixture helper in `Fixtures.swift`. Export with all three compression choices and restore each with CrossOver's `--restore` into unique fixture roots. Assert file hashes, modes, link targets and the preserved configuration. Do not register launchers, replace a real bottle or restore into `~/cxbottles`.
- [ ] Run `swift test`, then `BOTTLE_ARCHIVE_INTEGRATION=1 swift test --filter CrossOverRoundTripTests`. Require all to pass, with integration skips clearly distinguished from actual success. Test an interrupted job through the running UI and confirm both process cleanup and preservation of existing fixture archives.
- [ ] Finish project-local build/run and package scripts. Follow the existing Run-action contract at `.codex/environments/environment.toml`; stage a real `.app` with display name, identifier, version/build, macOS 15 minimum, icon and localisation resources. Sign this local owner app ad hoc. The run script refuses to terminate an active archive job during rebuild. Package from a fresh Release build using `ditto`.
- [ ] Unzip the deliverable into a fresh temporary directory. Verify bundle metadata, arm64 architecture, minimum OS, signature, resource presence and absence of development files. Launch this extracted app and inspect the visible main window, Help, About, default archive destination, size estimate and Reveal in Finder. Record which checks were automated and which were interactive in `docs/verification.md`.
- [ ] Write a concise README with creating an archive, restoring through CrossOver, cancelling, compression choices, approximate estimates and separately backing up external saves. Record local-only privacy and dependency information. Commit `build: package and verify Bottle Archive`.

## Final review and handoff

- [ ] Review all tasks against the approved spec, including sampling limits, process ownership, destination validation, archive publication and external links. Run a fresh independent code review using the available review tool or a reviewer authorised by Adrian's execution choice, then resolve material findings.
- [ ] Re-run only checks affected by resulting fixes. Confirm the final app and ZIP are the verified artifacts.
- [ ] Hand off clickable app/ZIP links with the tests run and any genuine limitation. Keep the project and its build output outside the Skyrim bottle. Full-size user archives remain Adrian's choice after fixture and GUI verification.

## Execution recommendation

Implement natively in this chat, with one independent final review. These tasks share the archive job interfaces closely, and sequential implementation keeps integration overhead low. Review this plan and choose native execution or delegation before implementation.

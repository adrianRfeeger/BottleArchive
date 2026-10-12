# Bottle Archive design

## Purpose

Bottle Archive is a small native Mac app for creating archives that CrossOver can restore. Adrian wants to choose a bottle, save an archive in his existing archive folder, see progress and choose between faster compression and a smaller file.

Project: `/Users/adrianfeeger/Development/BottleArchive`.
Default archive folder: `/Volumes/External/Crossover Archives`.

The app project and build outputs stay outside the bottles being archived.

## Main window

A compact, resizable SwiftUI window has a bottle selector, destination folder, compression choice and Create Archive button. Bottle discovery uses CrossOver's configured bottle location and the usual locations, including Adrian's `~/cxbottles`. A Choose Bottle control supports other locations. A valid bottle must contain `cxbottle.conf`.

The destination uses a native folder picker. The app remembers the selected destination, compression and window geometry. An unavailable external drive produces a clear explanation and a Choose Folder action.

Compression choices are Fast (gzip level 1), Balanced (level 6, the default) and Maximum (level 9). Each produces a `.cxarchive` file. The labels explain that maximum compression takes longer and may make little difference for files that are already compressed.

Before starting, show the bottle size and estimated archive size for the selected compression choice. Scan file sizes without following symbolic links, then compress a bounded, representative sample of local file data. Include different file types and sizes, with samples from several positions in large files, and weight the resulting ratios by the scanned content. Keep sample data in memory. Show Estimating while this runs, allow it to be cancelled, and refresh the estimate when the bottle or compression choice changes. Label the result approximate because compression varies across the rest of the bottle. If sampling fails, show Size estimate unavailable without preventing an otherwise valid archive job.

During a job, the window shows the stage, progress, bytes processed, output size, elapsed time and an estimated remaining time when enough data is available. Scanning has an indeterminate indicator. Archive progress is an estimate based on scanned content size and the tar bytes processed. It stays below completion until verification succeeds. Verification has its own progress stage. Cancel stays available during scanning, archiving and verification.

On success, show the actual archive size and Reveal in Finder. On failure, explain the cause and the next action, such as reconnecting the destination drive or freeing space.

## Archive engine and compatibility

Use the installed CrossOver exporter, `cxbottle --tar -`, to obtain a tar stream with CrossOver's bottle layout and exclusions. Stream that output through gzip at the selected compression level directly into the destination. This avoids an uncompressed temporary copy of a large bottle.

The installed CrossOver 26.3 exporter excludes the bottle's `files` and `desktopdata` entries and retains symbolic links. Its restore code recognises gzip-compressed tar archives with the `.cxarchive` extension. Adrian's existing Skyrim archive has the gzip file signature.

CrossOver must be installed. Locate its app bundle through the normal installed locations or a user-selected app. Invoke executables with structured arguments rather than shell interpolation. Capture errors from both the exporter and compressor, and require both processes to succeed.

CrossOver's exporter locks the bottle and can shut down its Windows applications. Before starting, check whether the selected bottle is running and explain that its applications need to close. Give Adrian a chance to close them, then recheck before invoking the exporter. Do not silently force-close a game from this app. The exporter remains responsible for its own bottle lock.

Progress updates, scanning, compression and validation run away from the main thread. The interface remains responsive. Block a second archive job until the current one finishes or cancellation completes. Prevent idle sleep while the job is active, then release the assertion.

## Output and recovery

Use a filename containing the bottle name and local date and time. Choose another unused name if it already exists. Existing archives are never replaced.

Write into a uniquely named `.partial` file in the selected destination. Publish the final `.cxarchive` only after successful validation, using a move within the same destination volume. Report disk-full, permissions and drive-disconnection failures without claiming success.

Cancellation stops all processes belonging to this job, closes its pipes and handles its own incomplete file. It must not stop another CrossOver export or touch an existing archive. Closing or quitting during a job requires a choice to keep working or cancel it.

The bottle's symbolic links remain links. A visible note explains that files stored outside the bottle, such as Skyrim saves in Mac Documents, need a separate backup. The app does not follow links into the Mac home folder while scanning or archiving.

Before export, check that the destination is outside the selected bottle and has usable free space. Recheck destination availability while running. Retain a concise local result containing the filename, compression, source size, output size, elapsed time and verification result.

## Verification

Read the completed compressed stream fully to validate gzip integrity. Check the tar layout for one bottle root and its `cxbottle.conf`, while respecting links and metadata. Validation must not extract or change the live bottle. A damaged or truncated archive stays incomplete and is reported as a failure.

Before delivery, use a disposable fixture bottle to test all compression levels and restore the produced archive using CrossOver's own restore command into an isolated test location. Check representative file contents, names containing spaces and Unicode, permissions, empty files and symbolic links. Also test cancellation, invalid bottles, a destination inside the bottle, process failures and an existing output filename. Check size estimation using fixtures containing compressible text, data that is already compressed and a mixture of both. Confirm changing compression refreshes the estimate, and verify that sampling remains bounded and does not follow external links.

Inspect the actual running GUI for bottle selection, folder selection, estimated archive size, compression changes, progress updates, cancellation, success and errors. Verify both light and dark appearances, keyboard access, readable labels and window restoration.

## Implementation and delivery

Use a Swift package with separate archive engine and SwiftUI app targets, plus a project-local build-and-run script that stages a normal `.app` bundle. Target macOS 15 or newer and build an Apple silicon version for Adrian's Mac. CrossOver remains an external installed dependency.

Deliver the app and an owner ZIP in the project output folder, with a short README explaining creation, restore through CrossOver and external saves. Include native menus, compact About and Help windows, and a simple recognisable icon.

Apply Adrian's native macOS typography, spacing, semantic colours and light/dark appearance standards. This is a personal utility: use one app icon and a direct main window, with configuration in that window. This narrow exception avoids adding an icon-selection Settings window or a separate onboarding flow to the requested utility.

## Evidence

- Installed exporter and restore implementation: `/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/cxbottle`, export implementation around lines 1243-1310 and restore implementation around lines 700-810.
- Official restore workflow: https://support.codeweavers.com/en_US/common-actions/archiving-and-restoring-a-bottle
- Archive destination inspected on 12 October 2026 and contains existing `.cxarchive` files.

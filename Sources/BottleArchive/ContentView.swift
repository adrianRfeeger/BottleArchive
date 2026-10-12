import SwiftUI
import AppKit
import AppState
import ArchiveEngine

struct ContentView: View {
    @ObservedObject var model: ArchiveViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "archivebox.fill").font(.system(size: 31, weight: .medium)).foregroundStyle(.purple)
                    .frame(width: 56, height: 56).background(.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Create a bottle archive")).font(.title2.weight(.semibold))
                    Text(L("Backups you can restore in CrossOver.")).foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(L("Bottle")).frame(width: 95, alignment: .leading)
                        Picker(L("Bottle"), selection: Binding(get: { model.selectedBottle }, set: { if let value = $0 { model.selectBottle(value) } })) {
                            if model.selectedBottle == nil { Text(L("Select a bottle")).tag(nil as Bottle?) }
                            ForEach(model.bottles, id: \.self) { Text($0.name).tag(Optional($0)) }
                        }.labelsHidden().accessibilityLabel(L("Bottle")).disabled(model.isBusy)
                        Button(L("Choose…")) { chooseFolder { model.selectBottle(Bottle(url: $0)) } }.disabled(model.isBusy)
                    }
                    HStack {
                        Text(L("Save to")).frame(width: 95, alignment: .leading)
                        Text(model.destination.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(model.destination.path)
                        Spacer(minLength: 4)
                        Button(L("Choose…")) { chooseFolder { model.setDestination($0) } }.disabled(model.isBusy)
                    }
                    HStack {
                        Text(L("Compression")).frame(width: 95, alignment: .leading)
                        Picker(L("Compression"), selection: Binding(get: { model.compression }, set: { model.setCompression($0) })) {
                            Text(L("Fast")).tag(CompressionPreset.fast)
                            Text(L("Balanced")).tag(CompressionPreset.balanced)
                            Text(L("Maximum")).tag(CompressionPreset.maximum)
                        }.pickerStyle(.segmented).labelsHidden().disabled(model.isBusy).accessibilityLabel(L("Compression"))
                    }
                    Text(L(model.compression == .fast ? "Less time compressing, usually a larger file." : model.compression == .maximum ? "More time compressing, usually a smaller file." : "A balance of compression time and file size."))
                        .font(.callout).foregroundStyle(.secondary).padding(.leading, 95)
                    HStack {
                        Text(L("Threads")).frame(width: 95, alignment: .leading)
                        Picker(L("Threads"), selection: Binding(get: { model.threads }, set: { model.setThreads($0) })) {
                            Text(L("Automatic") + " (" + String(CompressionThreads.resolved(0)) + ")").tag(0)
                            ForEach(1...max(1, ProcessInfo.processInfo.activeProcessorCount), id: \.self) { Text(String($0)).tag($0) }
                        }.labelsHidden().frame(width: 165).disabled(model.isBusy).accessibilityLabel(L("Threads"))
                        Spacer()
                        Text(L("More threads use more CPU.")).font(.caption).foregroundStyle(.secondary)
                    }.help(L("Automatic leaves two cores available when possible."))
                    Divider()
                    HStack(alignment: .top) {
                        sizeCard(L("Bottle size"), model.snapshot.map { bytes($0.logicalBytes) } ?? L("Not yet scanned"))
                        Spacer()
                        sizeCard(L("Estimated archive"), model.isEstimating ? L("Estimating…") : model.estimate.map { "≈ " + bytes($0.estimatedBytes) } ?? L("Unavailable"))
                        if model.isEstimating { ProgressView().controlSize(.small).padding(.top, 12) }
                    }
                    Text(L("The estimate is approximate. Actual size may differ.")).font(.caption).foregroundStyle(.secondary)
                }.padding(10)
            }
            if !model.destinationAvailable {
                Label(L("The destination folder is unavailable. Connect the drive or choose another folder."), systemImage: "externaldrive.badge.exclamationmark").font(.callout).foregroundStyle(.orange)
            }
            if model.crossOverApp == nil {
                HStack { Text(L("Choose CrossOver to create compatible archives.")).font(.callout); Spacer(); Button(L("Choose CrossOver…")) { chooseCrossOver(model) } }
            }
            if !(model.snapshot?.externalLinks.isEmpty ?? true) {
                Label(L("Linked folders stay outside the archive. Back up external saves and documents separately."), systemImage: "link")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: model.completedResult != nil ? "checkmark.circle.fill" : model.error != nil ? "exclamationmark.circle" : "clock")
                            .foregroundStyle(model.completedResult != nil ? Color.green : .secondary)
                        Text(L(model.status)).fontWeight(.medium)
                        Spacer()
                        if model.isBusy, let f = model.progress?.fraction { Text(f.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    if model.isBusy {
                        if let fraction=model.progress?.fraction {ProgressView(value:fraction)} else {ProgressView().progressViewStyle(.linear)}
                        HStack {
                            detail(L("Written"), bytes(model.progress?.outputBytes ?? 0))
                            Spacer()
                            detail(L("Elapsed"), duration(model.progress?.elapsedSeconds ?? 0))
                            Spacer()
                            detail(L("Remaining"), model.progress?.remainingSeconds.map(duration) ?? L("Calculating…"))
                        }.font(.caption)
                    } else if let result=model.completedResult {
                        Text(result.archiveURL.lastPathComponent).lineLimit(2).font(.callout).textSelection(.enabled)
                        Text(bytes(result.archiveBytes) + " · " + duration(result.elapsedSeconds)).font(.caption).foregroundStyle(.secondary)
                    } else if let error=model.error {
                        Text(L(error)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {Text(L("Existing archives are kept. Each backup gets a dated filename.")).font(.callout).foregroundStyle(.secondary)}
                }.padding(10)
            }
            Spacer(minLength: 0)
            HStack {
                Button(L("Diagnostics…")) { showDiagnostics(model) }.buttonStyle(.link)
                Spacer()
                if let result=model.completedResult { Button(L("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([result.archiveURL]) } }
                if model.isBusy || model.isEstimating {
                    Button(L(model.isBusy ? "Cancel Archive" : "Cancel Estimate")) { model.cancel() }.keyboardShortcut(.escape, modifiers: []).disabled(model.isCancelling)
                }
                Button(L("Create Archive")) { model.createArchive() }.buttonStyle(.borderedProminent).tint(.purple).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: []).disabled(!model.canCreateArchive)
            }
        }.padding(24).frame(minWidth: 650, minHeight: 685)
        .background(WindowSupport(model: model).frame(width: 0, height: 0))
    }
    private func sizeCard(_ title:String,_ value:String)->some View { VStack(alignment:.leading,spacing:5){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.title3.weight(.semibold)).monospacedDigit()} }
    private func detail(_ title:String,_ value:String)->some View {VStack(alignment:.leading,spacing:3){Text(title).foregroundStyle(.secondary);Text(value).monospacedDigit()}}

}
func chooseFolder(_ action:(URL)->Void) {let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.canCreateDirectories=true;p.allowsMultipleSelection=false;if p.runModal() == .OK,let u=p.url{action(u)}}
func bytes(_ value:UInt64)->String {ByteCountFormatter.string(fromByteCount:Int64(min(value,UInt64(Int64.max))),countStyle:.file)}
func duration(_ value:Double)->String {let f=DateComponentsFormatter();f.allowedUnits=value < 3600 ? [.minute,.second] : [.hour,.minute];f.unitsStyle = .abbreviated;return f.string(from:max(0,value)) ?? "0s"}

@MainActor func chooseCrossOver(_ model:ArchiveViewModel){let p=NSOpenPanel();p.canChooseDirectories=false;p.canChooseFiles=true;p.allowedContentTypes=[.applicationBundle];if p.runModal() == .OK,let u=p.url{model.setCrossOver(u)}}

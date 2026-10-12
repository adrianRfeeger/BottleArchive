import Foundation
import Combine
import ArchiveEngine

@MainActor public final class ArchiveViewModel: ObservableObject {
    @Published public private(set) var bottles: [Bottle] = []
    @Published public private(set) var selectedBottle: Bottle?
    @Published public private(set) var threads = 0
    @Published public private(set) var compression: CompressionPreset
    @Published public private(set) var destination: URL
    @Published public private(set) var crossOverApp: URL?
    @Published public private(set) var snapshot: BottleSnapshot?
    @Published public private(set) var estimate: ArchiveSizeEstimate?
    @Published public private(set) var isEstimating = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var isCancelling = false
    @Published public private(set) var completedResult: ArchiveResult?
    @Published public private(set) var progress: ArchiveProgress?
    @Published public private(set) var error: String?
    @Published public private(set) var status = "Ready"
    private let defaults: UserDefaults
    private var generation = 0
    private var estimationTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    private let job = ArchiveJob()
    public var destinationAvailable: Bool { var directory:ObjCBool=false;return FileManager.default.fileExists(atPath:destination.path,isDirectory:&directory) && directory.boolValue }
    public var canCreateArchive: Bool { !isBusy && !isEstimating && snapshot != nil && selectedBottle != nil && crossOverApp != nil && destinationAvailable }
    public static var jobMarkerURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/BottleArchive/active-job") }
    public init(defaults: UserDefaults = .standard, autoDiscover: Bool = true) {
        self.defaults = defaults
        threads = min(max(0, defaults.integer(forKey: "threads")), max(1, ProcessInfo.processInfo.activeProcessorCount))
        compression = CompressionPreset(rawValue: defaults.string(forKey: "compression") ?? "balanced") ?? .balanced
        destination = URL(fileURLWithPath: defaults.string(forKey: "destination") ?? "/Volumes/External/Crossover Archives")
        crossOverApp = defaults.string(forKey: "crossOverApp").map { URL(fileURLWithPath: $0) } ?? CrossOverInstallation.locate()
        if autoDiscover { refreshBottles() }
    }
    public func refreshBottles() {
        guard !isBusy else { return }
        let last = defaults.string(forKey: "bottle").map { URL(fileURLWithPath: $0) }
        Task {
            let found = (try? await Task.detached { try BottleDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser, configuredRoots: last.map { [$0] } ?? []) }.value) ?? []
            if selectedBottle == nil, let first = found.first(where: { $0 == last.map { Bottle(url: $0) } }) ?? found.first { selectBottle(first) }
            bottles = found
            if let selectedBottle, !bottles.contains(selectedBottle) { bottles.append(selectedBottle) }
        }
    }
    public func selectBottle(_ bottle: Bottle) {
        guard !isBusy else { return }
        selectedBottle = bottle; defaults.set(bottle.url.path, forKey: "bottle")
        if !bottles.contains(bottle) { bottles.append(bottle) }
        snapshot = nil; estimate = nil; completedResult = nil; progress = nil; error = nil
        estimateSize()
    }
    public func setCompression(_ value: CompressionPreset) {
        guard !isBusy else { return }
        compression = value; defaults.set(value.rawValue, forKey: "compression")
        estimate = nil; estimateSize()
    }
    public func setThreads(_ value: Int) { guard !isBusy else { return }; threads = min(max(0, value), max(1, ProcessInfo.processInfo.activeProcessorCount)); defaults.set(threads, forKey: "threads") }
    public func setDestination(_ value: URL) { guard !isBusy else{return};destination=value;defaults.set(value.path,forKey:"destination");error=nil }
    public func setCrossOver(_ value: URL) { guard !isBusy else{return};crossOverApp=value;defaults.set(value.path,forKey:"crossOverApp");error=nil }
    public func estimateSize() {
        estimationTask?.cancel(); generation += 1
        guard let bottle = selectedBottle else { return }
        let version = generation, preset = compression
        isEstimating = true; status = "Scanning bottle…"
        estimationTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let snapshot = try await BottleScanner.scan(bottle)
                await self?.receiveSnapshot(snapshot, version: version)
                do {
                    let estimate = try await SizeEstimator.estimate(snapshot: snapshot, compression: preset)
                    await self?.receiveEstimate(estimate, version: version)
                } catch is CancellationError { }
                catch { await self?.estimateUnavailable(version: version) }
            } catch is CancellationError { }
            catch { await self?.scanFailed(error.localizedDescription, version: version) }
        }
    }
    private func receiveSnapshot(_ value:BottleSnapshot,version:Int){guard version==generation else{return};snapshot=value;status="Estimating size…"}
    private func receiveEstimate(_ value:ArchiveSizeEstimate,version:Int){guard version==generation else{return};estimate=value;isEstimating=false;status="Ready"}
    private func estimateUnavailable(version:Int){guard version==generation else{return};isEstimating=false;status="Size estimate unavailable"}
    private func scanFailed(_ message:String,version:Int){guard version==generation else{return};isEstimating=false;snapshot=nil;error=message;status="Could not inspect bottle"}
    public func createArchive() {
        guard canCreateArchive, let bottle=selectedBottle,let snapshot,let app=crossOverApp else{return}
        isBusy=true;isCancelling=false;error=nil;completedResult=nil;status="Preparing…"
        try? FileManager.default.createDirectory(at:Self.jobMarkerURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try? Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to:Self.jobMarkerURL,options:.atomic)
        let request=ArchiveRequest(bottle:bottle,destination:destination,compression:compression,crossOverApp:app,estimatedBytes:estimate?.estimatedBytes,threads:threads)
        let stream=job.start(request:request,snapshot:snapshot)
        jobTask=Task {
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let value):progress=value;status=isCancelling ? "Cancelling…" : value.stage == .preparing ? "Preparing…" : value.stage == .archiving ? "Creating archive…" : value.stage == .verifying ? "Verifying archive…" : "Archive complete"
                    case .completed(let result):completedResult=result;status="Archive complete";persist(result)
                    }
                }
            } catch is CancellationError {status="Cancelled"}
            catch {self.error=error.localizedDescription;status="Archive failed"}
            isBusy=false;isCancelling=false;jobTask=nil
            try? FileManager.default.removeItem(at:Self.jobMarkerURL)
        }
    }
    private func persist(_ result:ArchiveResult) {
        Task.detached(priority:.utility){
            let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BottleArchive/Results")
            do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let data=try JSONEncoder().encode(result);try data.write(to:folder.appendingPathComponent(UUID().uuidString+".json"),options:.atomic)}catch{}
        }
    }
    public func cancel() {
        if isBusy {isCancelling=true;status="Cancelling…";job.cancel()}
        else {generation += 1;estimationTask?.cancel();estimationTask=nil;isEstimating=false;status="Size estimate unavailable"}
    }
    public func diagnostics() -> String {
        "Bottle Archive 1.1 (2)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nCrossOver available: \(crossOverApp != nil)\nCompression level: \(compression.gzipLevel)\nCompression threads: \(CompressionThreads.resolved(threads))\nArchive active: \(isBusy)\nEstimate available: \(estimate != nil)\nLast stage: \(progress?.stage.rawValue ?? "none")\nLast result verified: \(completedResult?.verified ?? false)"
    }
}

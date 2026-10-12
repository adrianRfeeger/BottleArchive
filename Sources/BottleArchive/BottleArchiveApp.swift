import SwiftUI
import AppKit
import AppState

func L(_ key: String) -> String { NSLocalizedString(key, bundle: Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("BottleArchive_BottleArchive.bundle")) } ?? .module, comment: "") }
@main struct BottleArchiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = ArchiveViewModel()
    var body: some Scene {
        Window("Bottle Archive", id: "main") {
            ContentView(model: model).onAppear { delegate.model = model }
        }.defaultSize(width: 690, height: 665)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) { SupportCommands() }
            CommandGroup(before: .newItem) { Button(L("Choose CrossOver…")) { chooseCrossOver(model) }.disabled(model.isBusy) }
            CommandGroup(after: .newItem) { Button(L("Refresh Bottles")) { model.refreshBottles() }.keyboardShortcut("r").disabled(model.isBusy) }
            CommandGroup(replacing: .help) { HelpCommand() }
        }
        Window(L("Help"), id: "help") { HelpView().frame(width: 570, height: 470) }.windowResizability(.contentSize)
        Window(L("About Bottle Archive"), id: "about") { AboutView().frame(width: 370, height: 320) }.windowResizability(.contentSize)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ArchiveViewModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-light") { NSApp.appearance = NSAppearance(named: .aqua) }
        #endif
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isBusy else { model?.cancel(); return .terminateNow }
        guard confirmCancellation() else { return .terminateCancel }
        model.cancel()
        Task { while model.isBusy { try? await Task.sleep(for: .milliseconds(100)) }; sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
func confirmCancellation() -> Bool {
    let alert = NSAlert()
    alert.messageText = L("An archive is running")
    alert.informativeText = L("Keep the app open to finish, or cancel this archive before closing.")
    alert.addButton(withTitle: L("Keep Working")); alert.addButton(withTitle: L("Cancel Archive"))
    return alert.runModal() == .alertSecondButtonReturn
}

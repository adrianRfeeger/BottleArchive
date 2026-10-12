import SwiftUI
import AppKit
import AppState
struct WindowSupport: NSViewRepresentable {
    let model: ArchiveViewModel
    func makeNSView(context: Context) -> WindowBindingView { let view=WindowBindingView();view.model=model;return view }
    func updateNSView(_ view:WindowBindingView,context:Context){view.model=model}
}
final class WindowBindingView: NSView, NSWindowDelegate {
    weak var model: ArchiveViewModel?
    private var bound=false
    override func viewDidMoveToWindow(){
        super.viewDidMoveToWindow()
        guard !bound,let window else{return};bound=true
        window.setFrameAutosaveName("BottleArchive.main")
        if !NSScreen.screens.contains(where:{$0.visibleFrame.intersects(window.frame)}){window.center()}
        window.delegate=self
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {
        guard let model,model.isBusy else{model?.cancel();return true}
        if confirmCancellation(){model.cancel();Task{@MainActor in while model.isBusy{try? await Task.sleep(for:.milliseconds(100))};sender.performClose(nil)}}
        return false
    }
}

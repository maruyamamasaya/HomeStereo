import AppKit
import SwiftUI

/// Configures only the mini-player window; no application-wide window lookup.
struct MiniPlayerWindow: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: WindowProbe, context: Context) {
        nsView.onWindow = onWindow
    }
    final class WindowProbe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
            // Deliver after SwiftUI's update, and re-check that the view is still attached.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.onWindow?(window)
            }
        }
    }
}

/// The glass display doubles as a native window drag surface.
struct MiniPlayerDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

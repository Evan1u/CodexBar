import AppKit

@MainActor
enum TokenTrackerPanelFactory {
    static let shellSize = NSSize(width: 1, height: 1)

    static func makeShellPanel(contentRect: NSRect) -> NSPanel {
        self.makePanel(contentRect: contentRect, interactive: false, allowsKey: false)
    }

    static func makeNotchPanel(contentRect: NSRect) -> NSPanel {
        self.makePanel(contentRect: contentRect, interactive: true, allowsKey: true)
    }

    static func makeSidePanel(contentRect: NSRect) -> NSPanel {
        self.makePanel(contentRect: contentRect, interactive: true, allowsKey: true)
    }

    static func makeProviderDetailPanel(contentRect: NSRect) -> NSPanel {
        self.makePanel(contentRect: contentRect, interactive: true, allowsKey: true)
    }

    private static func makePanel(contentRect: NSRect, interactive: Bool, allowsKey: Bool) -> NSPanel {
        let panel = TokenTrackerShellPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.allowsKeyWindow = allowsKey
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true

        let contentView = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = contentView
        panel.setFrame(contentRect, display: false)
        return panel
    }
}

@MainActor
private final class TokenTrackerShellPanel: NSPanel {
    var allowsKeyWindow = false

    override var canBecomeKey: Bool {
        self.allowsKeyWindow
    }

    override var canBecomeMain: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        self.allowsKeyWindow
    }
}

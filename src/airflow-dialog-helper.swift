import AppKit
import Foundation

struct Arguments {
    let title: String
    let message: String
    let url: String
    let kind: String

    static func parse() -> Arguments {
        var values: [String: String] = [:]
        var index = 1
        let args = CommandLine.arguments
        while index < args.count {
            let key = args[index]
            if key.hasPrefix("--"), index + 1 < args.count {
                values[key] = args[index + 1]
                index += 2
            } else {
                index += 1
            }
        }

        return Arguments(
            title: values["--title"] ?? "Dagsy: Your DAG Watcher",
            message: values["--message"] ?? "",
            url: values["--url"] ?? "http://localhost:8080",
            kind: values["--kind"] ?? "generic"
        )
    }
}

final class PopupController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let args: Arguments
    private var window: NSWindow!
    private var result = "Dismiss"

    init(args: Arguments) {
        self.args = args
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
    }

    private func buildMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(dismissAction), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        print(result)
        fflush(stdout)
        NSApp.terminate(nil)
    }

    @objc private func dismissAction() {
        result = "Dismiss"
        NSApp.stopModal()
        window.close()
    }

    @objc private func openAction() {
        if let url = URL(string: args.url) {
            NSWorkspace.shared.open(url)
        }
        result = "Open in Airflow"
    }

    private func theme() -> (surface: NSColor, border: NSColor, accent: NSColor, button: NSColor, subtitle: String) {
        switch args.kind.lowercased() {
        case "failure":
            return (
                NSColor(calibratedRed: 1.0, green: 0.957, blue: 0.949, alpha: 1.0),
                NSColor(calibratedRed: 0.957, green: 0.78, blue: 0.765, alpha: 1.0),
                NSColor(calibratedRed: 0.706, green: 0.137, blue: 0.094, alpha: 1.0),
                NSColor(calibratedRed: 0.706, green: 0.137, blue: 0.094, alpha: 1.0),
                "Airflow Failure"
            )
        case "success":
            return (
                NSColor(calibratedRed: 0.941, green: 0.992, blue: 0.949, alpha: 1.0),
                NSColor(calibratedRed: 0.733, green: 0.969, blue: 0.816, alpha: 1.0),
                NSColor(calibratedRed: 0.086, green: 0.396, blue: 0.204, alpha: 1.0),
                NSColor(calibratedRed: 0.086, green: 0.396, blue: 0.204, alpha: 1.0),
                "Airflow Success"
            )
        default:
            return (
                NSColor(calibratedRed: 0.937, green: 0.965, blue: 1.0, alpha: 1.0),
                NSColor(calibratedRed: 0.749, green: 0.859, blue: 0.996, alpha: 1.0),
                NSColor(calibratedRed: 0.114, green: 0.306, blue: 0.847, alpha: 1.0),
                NSColor(calibratedRed: 0.114, green: 0.306, blue: 0.847, alpha: 1.0),
                "Airflow Update"
            )
        }
    }

    private func buildWindow() {
        let theme = theme()
        let rect = NSRect(x: 0, y: 0, width: 640, height: 320)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = theme.subtitle
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()

        let content = NSView(frame: rect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = content

        let card = NSView(frame: NSRect(x: 14, y: 14, width: 612, height: 292))
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.surface.cgColor
        card.layer?.borderColor = theme.border.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 14
        content.addSubview(card)

        let accentBar = NSView(frame: NSRect(x: 0, y: 286, width: 612, height: 6))
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = theme.accent.cgColor
        accentBar.layer?.cornerRadius = 14
        card.addSubview(accentBar)

        let titleLabel = NSTextField(labelWithString: args.title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)
        titleLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
        titleLabel.frame = NSRect(x: 22, y: 236, width: 560, height: 28)
        card.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: theme.subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.36, alpha: 1.0)
        subtitleLabel.frame = NSRect(x: 22, y: 214, width: 560, height: 20)
        card.addSubview(subtitleLabel)

        let messageView = NSTextField(wrappingLabelWithString: args.message)
        messageView.font = NSFont.systemFont(ofSize: 13)
        messageView.textColor = NSColor(calibratedWhite: 0.16, alpha: 1.0)
        messageView.frame = NSRect(x: 22, y: 80, width: 568, height: 122)
        card.addSubview(messageView)

        let dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismissAction))
        dismissButton.bezelStyle = .rounded
        dismissButton.frame = NSRect(x: 492, y: 24, width: 96, height: 34)
        card.addSubview(dismissButton)

        let openButton = NSButton(title: "Open in Airflow", target: self, action: #selector(openAction))
        openButton.isBordered = false
        openButton.wantsLayer = true
        openButton.layer?.backgroundColor = theme.button.cgColor
        openButton.layer?.cornerRadius = 8
        openButton.contentTintColor = .white
        openButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        openButton.frame = NSRect(x: 344, y: 24, width: 136, height: 34)
        card.addSubview(openButton)

        if let screenFrame = NSScreen.main?.visibleFrame {
            let originX = screenFrame.maxX - rect.width - 24
            let originY = screenFrame.maxY - rect.height - 60
            window.setFrameOrigin(NSPoint(x: originX, y: originY))
        }
    }
}

let args = Arguments.parse()
let app = NSApplication.shared
let delegate = PopupController(args: args)
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()

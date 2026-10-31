import SwiftUI
import AppKit

@main
struct OnggiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(app: delegate.app, openSetup: { tab in delegate.showSetup(tab: tab) })
        } label: {
            Image(systemName: "pawprint.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppState()
    private var overlay: OverlayController?
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(app: app)
        overlay?.start()

        Task {
            await app.bootstrap()
            switch app.phase {
            case .needsProfile: showSetup(tab: .character)
            case .needsGroup: showSetup(tab: .group)
            default: break
            }
        }
    }

    /// 캐릭터 만들기 / 그룹 만들기·가입 창
    func showSetup(tab: SetupView.Tab) {
        if let window = setupWindow {
            (window.contentViewController as? NSHostingController<SetupView>)?.rootView = makeSetupView(tab: tab)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "옹기종기"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: makeSetupView(tab: tab))
        window.center()
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSetupView(tab: SetupView.Tab) -> SetupView {
        SetupView(app: app, initialTab: tab, onDone: { [weak self] in self?.setupWindow?.close() })
    }
}

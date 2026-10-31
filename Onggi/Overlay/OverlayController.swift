import AppKit
import SwiftUI
import Combine

/// 클릭을 바로 받는 호스팅 뷰 (창이 활성화되지 않아도 첫 클릭이 먹히도록)
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 테두리 없는 투명 패널. 키보드 포커스를 뺏지 않는다.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 메인 화면 전체를 덮는 투명 창을 만들고 관리한다.
///
/// 핵심 요령: 평소에는 창이 클릭을 통과시키고(ignoresMouseEvents = true),
/// 마우스가 캐릭터나 카드 위에 올라갔을 때만 클릭을 받는다.
@MainActor
final class OverlayController {
    private let app: AppState
    private var panel: OverlayPanel?
    private var mouseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(app: AppState) {
        self.app = app
    }

    func start() {
        guard let screen = NSScreen.main else { return }

        let panel = OverlayPanel(contentRect: screen.frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = ClickThroughHostingView(rootView: OverlayView(app: app, sim: app.simulation))
        panel.setFrame(screen.frame, display: true)
        self.panel = panel

        updateBounds(screen: screen)
        applyLevel()
        applyVisibility()
        app.simulation.start()

        // 설정이 바뀌면 바로 반영
        app.$overlayOnTop.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLevel() }.store(in: &cancellables)
        app.$overlayVisible.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility() }.store(in: &cancellables)

        // 해상도·모니터 구성이 바뀌면 크기 다시 맞추기
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = NSScreen.main else { return }
                self.panel?.setFrame(screen.frame, display: true)
                self.updateBounds(screen: screen)
            }
        }

        // 마우스 위치를 보고 클릭 통과 여부를 바꾼다 (초당 30번)
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassThrough() }
        }
        RunLoop.main.add(mouseTimer!, forMode: .common)
    }

    /// 캐릭터가 다닐 수 있는 영역 = 메뉴바와 독을 뺀 부분 (창 좌표로 변환, 왼쪽 위가 0,0)
    private func updateBounds(screen: NSScreen) {
        let full = screen.frame
        let visible = screen.visibleFrame
        app.simulation.bounds = CGRect(x: visible.minX - full.minX,
                                       y: full.maxY - visible.maxY,
                                       width: visible.width,
                                       height: visible.height)
    }

    private func applyLevel() {
        guard let panel else { return }
        if app.overlayOnTop {
            panel.level = .floating
        } else {
            // 바탕화면 아이콘 바로 위, 다른 앱 창들보다는 아래
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
        panel.orderFrontRegardless()
    }

    private func applyVisibility() {
        if app.overlayVisible {
            panel?.orderFrontRegardless()
            app.simulation.start()
        } else {
            panel?.orderOut(nil)
            app.simulation.stop()
        }
    }

    private func updateMousePassThrough() {
        guard let panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation                 // 화면 좌표 (왼쪽 아래가 0,0)
        let frame = panel.frame
        let point = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)   // 창 좌표로 변환
        let interactive = app.simulation.isInteractive(at: point)
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
    }
}

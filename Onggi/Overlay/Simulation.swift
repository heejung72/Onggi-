import Foundation
import SwiftUI

/// 바탕화면 캐릭터들의 위치와 움직임을 계산한다 (초당 30번).
///
/// 규칙
/// - 산책 중: 화면 전체를 돌아다닌다. 2명 이상이면 리더를 따라 줄지어 같이 걷는다.
/// - 공부·일·잠·쉬기: 상태별 "구역"으로 걸어가서 멈춘다.
///   같은 상태가 2명 이상이면 한 구역에 나란히 모여 공유 소품(긴 책상, 큰 이불)을 쓴다.
@MainActor
final class Simulation: ObservableObject {

    struct Agent: Identifiable {
        let id: UUID
        var member: Member
        var position: CGPoint
        var target: CGPoint
        var facingLeft = false
        var arrived = false
        var pauseUntil = Date.distantPast
        var phase = Double.random(in: 0...(2 * .pi))   // 애니메이션 위상 (모두 똑같이 움직이지 않게)
        var reaction: String?
        var reactionUntil = Date.distantPast
    }

    /// 같은 상태로 모여 있는 무리 (공유 소품과 말풍선을 그리는 데 쓴다)
    struct Cluster: Identifiable {
        let activity: Activity
        let anchor: CGPoint
        let memberIDs: [UUID]
        var id: String { activity.rawValue }
        var width: CGFloat { CGFloat(memberIDs.count) * Simulation.seatSpacing(activity) }
    }

    @Published private(set) var agents: [Agent] = []
    @Published private(set) var clusters: [Cluster] = []
    @Published private(set) var time: Double = 0

    var myID: UUID?
    /// 캐릭터가 움직일 수 있는 영역 (오버레이 창 좌표, 왼쪽 위가 0,0)
    var bounds: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900) {
        didSet { if oldValue != bounds { relayout() } }
    }

    static let characterSize: CGFloat = 64
    private let walkSpeed: CGFloat = 70     // pt/초
    private let rushSpeed: CGFloat = 160    // 상태가 바뀌어 자리로 갈 때
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        var last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let now = Date()
            let dt = min(now.timeIntervalSince(last), 0.1)
            last = now
            MainActor.assumeIsolated { self?.step(dt: dt, now: now) }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 멤버 목록 반영

    func sync(members: [Member]) {
        var next: [Agent] = []
        for member in members.prefix(Config.maxMembers) {
            if var existing = agents.first(where: { $0.id == member.id }) {
                if existing.member.activity != member.activity { existing.arrived = false }
                existing.member = member
                next.append(existing)
            } else {
                let start = randomPoint()
                next.append(Agent(id: member.id, member: member, position: start, target: start))
            }
        }
        agents = next
        relayout()
    }

    /// 찌르기 등을 받았을 때 캐릭터가 폴짝 뛰며 말풍선을 띄운다
    func react(_ id: UUID, text: String) {
        guard let i = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[i].reaction = text
        agents[i].reactionUntil = Date().addingTimeInterval(2.5)
    }

    func agent(at point: CGPoint) -> Agent? {
        let half = Self.characterSize / 2 + 6
        return agents.last { abs($0.position.x - point.x) < half && abs($0.position.y - point.y) < half }
    }

    // MARK: 친구 카드 (캐릭터를 클릭하면 뜨는 작은 창)

    @Published var selectedID: UUID?
    static let cardSize = CGSize(width: 230, height: 150)

    /// 선택된 캐릭터 위쪽에 카드를 띄우되 화면 밖으로 나가지 않게
    func cardCenter() -> CGPoint? {
        guard let id = selectedID, let a = agents.first(where: { $0.id == id }) else { return nil }
        let w = Self.cardSize.width / 2, h = Self.cardSize.height / 2
        var c = CGPoint(x: a.position.x, y: a.position.y - Self.characterSize / 2 - h - 34)
        if c.y - h < bounds.minY { c.y = a.position.y + Self.characterSize / 2 + h + 24 }
        c.x = min(max(c.x, bounds.minX + w + 8), bounds.maxX - w - 8)
        return c
    }

    /// 이 지점이 캐릭터나 카드 위인가? (아니면 클릭이 뒤의 창으로 통과된다)
    func isInteractive(at point: CGPoint) -> Bool {
        if agent(at: point) != nil { return true }
        if let c = cardCenter() {
            let r = CGRect(x: c.x - Self.cardSize.width / 2, y: c.y - Self.cardSize.height / 2,
                           width: Self.cardSize.width, height: Self.cardSize.height)
            if r.contains(point) { return true }
        }
        return false
    }

    // MARK: 구역 배치

    /// 상태별 구역의 기준점 — 화면 아래쪽에 나란히 (독 바로 위)
    private func anchor(for activity: Activity) -> CGPoint {
        let fraction: CGFloat
        switch activity {
        case .sleep: fraction = 0.16
        case .study: fraction = 0.40
        case .work:  fraction = 0.62
        case .rest:  fraction = 0.84
        case .walk:  fraction = 0.5
        }
        return CGPoint(x: bounds.minX + bounds.width * fraction, y: bounds.maxY - 70)
    }

    nonisolated static func seatSpacing(_ activity: Activity) -> CGFloat {
        activity == .sleep ? 58 : 74
    }

    /// 상태가 같은 사람끼리 모아 자리를 정한다
    private func relayout() {
        var newClusters: [Cluster] = []
        for activity in Activity.allCases where !activity.roams {
            let ids = agents.filter { $0.member.activity == activity }.map(\.id).sorted { $0.uuidString < $1.uuidString }
            guard !ids.isEmpty else { continue }
            let anchor = anchor(for: activity)
            newClusters.append(Cluster(activity: activity, anchor: anchor, memberIDs: ids))
            let spacing = Self.seatSpacing(activity)
            for (n, id) in ids.enumerated() {
                guard let i = agents.firstIndex(where: { $0.id == id }) else { continue }
                let offset = (CGFloat(n) - CGFloat(ids.count - 1) / 2) * spacing
                agents[i].target = CGPoint(x: anchor.x + offset, y: anchor.y)
            }
        }
        clusters = newClusters
        for i in agents.indices where agents[i].member.activity.roams && agents[i].arrived == false {
            agents[i].target = randomPoint()
        }
    }

    // MARK: 한 프레임 진행

    private func step(dt: Double, now: Date) {
        time += dt
        let walkers = agents.filter { $0.member.activity.roams }.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let leaderID = walkers.first

        for i in agents.indices {
            var a = agents[i]
            if a.reaction != nil, now > a.reactionUntil { a.reaction = nil }

            if a.member.activity.roams {
                // 산책: 리더는 자유롭게, 나머지는 리더 뒤를 따라 걷는다
                if let leaderID, a.id != leaderID, let leader = agents.first(where: { $0.id == leaderID }) {
                    let rank = CGFloat(walkers.firstIndex(of: a.id) ?? 1)
                    let behind: CGFloat = leader.facingLeft ? 1 : -1
                    a.target = CGPoint(x: leader.position.x + behind * 56 * rank,
                                       y: leader.position.y + (rank.truncatingRemainder(dividingBy: 2) == 0 ? 10 : -10))
                } else if a.arrived {
                    if now > a.pauseUntil {
                        a.target = randomPoint()
                        a.arrived = false
                    }
                }
                move(&a, speed: walkSpeed, dt: dt, now: now, pauseOnArrival: true)
            } else {
                move(&a, speed: rushSpeed, dt: dt, now: now, pauseOnArrival: false)
            }
            agents[i] = a
        }
    }

    private func move(_ a: inout Agent, speed: CGFloat, dt: Double, now: Date, pauseOnArrival: Bool) {
        let dx = a.target.x - a.position.x
        let dy = a.target.y - a.position.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist < 2 {
            a.position = a.target
            if !a.arrived {
                a.arrived = true
                if pauseOnArrival { a.pauseUntil = now.addingTimeInterval(Double.random(in: 1.5...4)) }
            }
            return
        }
        a.arrived = false
        let stepLen = min(dist, speed * CGFloat(dt))
        a.position.x += dx / dist * stepLen
        a.position.y += dy / dist * stepLen
        if abs(dx) > 1 { a.facingLeft = dx < 0 }
    }

    private func randomPoint() -> CGPoint {
        let margin = Self.characterSize
        let inner = bounds.insetBy(dx: margin, dy: margin)
        guard inner.width > 0, inner.height > 0 else { return CGPoint(x: bounds.midX, y: bounds.midY) }
        return CGPoint(x: .random(in: inner.minX...inner.maxX), y: .random(in: inner.minY...inner.maxY))
    }
}

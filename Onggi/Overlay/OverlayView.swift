import SwiftUI

/// 바탕화면 전체를 덮는 투명 화면. 캐릭터·공유 소품·말풍선·친구 카드를 그린다.
struct OverlayView: View {
    @ObservedObject var app: AppState
    @ObservedObject var sim: Simulation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // 1) 캐릭터 (아래쪽에 있는 캐릭터가 앞에 오도록 y 순서대로)
            ForEach(sim.agents.sorted { $0.position.y < $1.position.y }) { agent in
                character(agent)
            }

            // 2) 함께 쓰는 소품 — 캐릭터 몸 앞쪽을 가린다
            ForEach(sim.clusters) { cluster in
                frontProp(cluster)
            }

            // 3) 이름표, Zzz, 반응 말풍선
            ForEach(sim.agents) { agent in
                decorations(agent)
            }

            // 4) "같이 ~ 중!" 말풍선
            ForEach(sim.clusters.filter { $0.memberIDs.count >= 2 }) { cluster in
                BubbleView(text: cluster.activity.togetherLabel, symbol: cluster.activity.symbol)
                    .position(x: cluster.anchor.x, y: cluster.anchor.y - Simulation.characterSize - 18)
            }
            walkTogetherBubble

            // 5) 친구 카드
            if let center = sim.cardCenter(),
               let id = sim.selectedID,
               let member = sim.agents.first(where: { $0.id == id })?.member {
                FriendCard(member: member, isMe: id == app.userID, time: sim.time,
                           onPoke: { kind in Task { await app.poke(id, kind: kind) } },
                           onClose: { sim.selectedID = nil })
                    .frame(width: Simulation.cardSize.width, height: Simulation.cardSize.height)
                    .position(center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: 캐릭터 한 명

    private func pose(_ a: Simulation.Agent) -> Pose {
        if !a.arrived { return .walking }
        switch a.member.activity {
        case .walk: return .standing
        case .sleep: return .sleeping
        default: return .sitting
        }
    }

    private func character(_ a: Simulation.Agent) -> some View {
        let jump: CGFloat = a.reaction != nil ? -abs(sin(sim.time * 10)) * 10 : 0
        return CharacterView(species: a.member.profile.species,
                             color: a.member.profile.color,
                             pose: pose(a),
                             facingLeft: a.facingLeft,
                             time: sim.time + a.phase,
                             size: Simulation.characterSize)
            .offset(y: jump)
            .contentShape(Rectangle())
            .onTapGesture {
                sim.selectedID = (sim.selectedID == a.id) ? nil : a.id
            }
            .position(a.position)
    }

    @ViewBuilder private func frontProp(_ cluster: Simulation.Cluster) -> some View {
        let seated = cluster.memberIDs.contains { id in sim.agents.first { $0.id == id }?.arrived == true }
        if seated {
            switch cluster.activity {
            case .sleep:
                BlanketView(width: cluster.width + 16)
                    .position(x: cluster.anchor.x, y: cluster.anchor.y + 18)
            case .study, .work:
                DeskView(width: cluster.width + 12,
                         seats: cluster.memberIDs.count,
                         activity: cluster.activity,
                         seatSpacing: Simulation.seatSpacing(cluster.activity))
                    .position(x: cluster.anchor.x, y: cluster.anchor.y + 22)
            case .rest, .walk:
                EmptyView()
            }
        }
    }

    private func decorations(_ a: Simulation.Agent) -> some View {
        let half = Simulation.characterSize / 2
        let isMe = a.id == app.userID
        return ZStack {
            NameTag(name: a.member.profile.nickname, isMe: isMe)
                .offset(y: half + (a.member.activity == .sleep || a.member.activity == .study || a.member.activity == .work ? 34 : 10))
            if a.arrived && a.member.activity == .sleep {
                ZzzView(time: sim.time + a.phase).offset(x: 10, y: -half)
            }
            if a.arrived && a.member.activity == .rest {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.62, green: 0.45, blue: 0.35))
                    .offset(x: half * 0.9, y: half * 0.45)
            }
            if let text = a.reaction {
                BubbleView(text: text).offset(y: -half - 22)
            }
        }
        .allowsHitTesting(false)
        .position(a.position)
    }

    /// 산책하는 사람이 2명 이상이면 맨 앞 친구 위에 "같이 산책 중!"
    @ViewBuilder private var walkTogetherBubble: some View {
        let walkers = sim.agents.filter { $0.member.activity == .walk }
        if walkers.count >= 2,
           let leader = walkers.min(by: { $0.id.uuidString < $1.id.uuidString }) {
            BubbleView(text: Activity.walk.togetherLabel, symbol: Activity.walk.symbol)
                .position(x: leader.position.x, y: leader.position.y - Simulation.characterSize / 2 - 26)
                .allowsHitTesting(false)
        }
    }
}

/// 친구 캐릭터를 클릭하면 뜨는 카드
struct FriendCard: View {
    let member: Member
    let isMe: Bool
    let time: Double
    let onPoke: (PokeKind) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CharacterView(species: member.profile.species, color: member.profile.color, time: time, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.profile.nickname).font(.system(size: 14, weight: .bold, design: .rounded))
                    HStack(spacing: 4) {
                        Image(systemName: member.activity.symbol)
                        Text("\(member.activity.label) · \(member.elapsedText())")
                    }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Text(member.status?.memo ?? " ")
                .font(.system(size: 12, design: .rounded))
                .lineLimit(1)
            if isMe {
                Text("나의 캐릭터예요. 상태는 메뉴바에서 바꿀 수 있어요.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Button("콕 찌르기") { onPoke(.poke) }
                    Button("화이팅") { onPoke(.cheer) }
                    Button("간식 주기") { onPoke(.snack) }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.4)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

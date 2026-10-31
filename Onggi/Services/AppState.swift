import Foundation
import SwiftUI

/// 앱 전체의 상태. 메뉴바·설정 창·바탕화면 오버레이가 모두 이 객체를 본다.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case needsProfile
        case needsGroup
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var me: Profile?
    @Published private(set) var groups: [FriendGroup] = []
    @Published private(set) var members: [Member] = []
    @Published var errorMessage: String?

    @Published var selectedGroupID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedGroupID?.uuidString, forKey: "onggi.selectedGroup")
            if oldValue != selectedGroupID { Task { await reloadMembers() } }
        }
    }

    /// 바탕화면 캐릭터 보이기
    @Published var overlayVisible: Bool = UserDefaults.standard.object(forKey: "onggi.overlayVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(overlayVisible, forKey: "onggi.overlayVisible") }
    }
    /// true = 모든 창 위에 표시, false = 바탕화면(창 아래)에만 표시
    @Published var overlayOnTop: Bool = UserDefaults.standard.bool(forKey: "onggi.overlayOnTop") {
        didSet { UserDefaults.standard.set(overlayOnTop, forKey: "onggi.overlayOnTop") }
    }

    let service = SupabaseService()
    let simulation = Simulation()

    private(set) var userID: UUID?
    private var lastPokeID = 0
    private var pollTask: Task<Void, Never>?

    var selectedGroup: FriendGroup? { groups.first { $0.id == selectedGroupID } }
    var myMember: Member? { members.first { $0.id == userID } }

    // MARK: 시작

    func bootstrap() async {
        phase = .loading
        do {
            let uid = try await service.signIn()
            userID = uid
            simulation.myID = uid

            guard let profile = try await service.fetchProfile(id: uid) else {
                phase = .needsProfile
                return
            }
            me = profile
            try await reloadGroups()
            lastPokeID = (try? await service.latestPokeID(to: uid)) ?? 0
            await startLiveUpdates()
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    // MARK: 프로필

    func saveProfile(nickname: String, species: Species, color: CharacterColor) async {
        guard let uid = userID else { return }
        let profile = Profile(id: uid, nickname: nickname, species: species, color: color)
        do {
            try await service.saveProfile(profile)
            if me == nil {
                // 첫 가입: 기본 상태 한 줄 만들기
                try await service.setStatus(userID: uid, activity: .rest, memo: nil)
            }
            me = profile
            try await reloadGroups()
            await startLiveUpdates()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: 그룹

    func createGroup(name: String) async {
        do {
            let group = try await service.createGroup(name: name)
            try await reloadGroups()
            selectedGroupID = group.id
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func joinGroup(code: String) async {
        do {
            let group = try await service.joinGroup(code: code)
            try await reloadGroups()
            selectedGroupID = group.id
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func reloadGroups() async throws {
        groups = try await service.fetchMyGroups()
        if groups.isEmpty {
            phase = .needsGroup
            members = []
            simulation.sync(members: [])
            return
        }
        let saved = UserDefaults.standard.string(forKey: "onggi.selectedGroup").flatMap(UUID.init)
        if let current = selectedGroupID, groups.contains(where: { $0.id == current }) {
            // 그대로 유지
        } else if let saved, groups.contains(where: { $0.id == saved }) {
            selectedGroupID = saved
        } else {
            selectedGroupID = groups.first?.id
        }
        phase = .ready
        await reloadMembers()
    }

    func reloadMembers() async {
        guard let gid = selectedGroupID else { return }
        do {
            members = try await service.fetchMembers(groupID: gid)
            simulation.sync(members: members)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: 내 상태

    func setActivity(_ activity: Activity) async {
        guard let uid = userID else { return }
        let memo = myMember?.status?.memo
        await updateStatus(uid: uid, activity: activity, memo: memo)
    }

    func setMemo(_ memo: String) async {
        guard let uid = userID else { return }
        let trimmed = String(memo.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        await updateStatus(uid: uid, activity: myMember?.activity ?? .rest, memo: trimmed.isEmpty ? nil : trimmed)
    }

    private func updateStatus(uid: UUID, activity: Activity, memo: String?) async {
        // 내 화면은 서버 응답을 기다리지 않고 바로 바꾼다
        if let i = members.firstIndex(where: { $0.id == uid }) {
            let changed = members[i].activity != activity
            let start = changed ? Date() : (members[i].status?.startedAt ?? Date())
            members[i].status = Status(userID: uid, activity: activity, memo: memo, startedAt: start)
            simulation.sync(members: members)
        }
        do {
            try await service.setStatus(userID: uid, activity: activity, memo: memo)
        } catch {
            errorMessage = Self.describe(error)
            await reloadMembers()
        }
    }

    // MARK: 찌르기

    func poke(_ friendID: UUID, kind: PokeKind) async {
        guard let uid = userID, let gid = selectedGroupID, friendID != uid else { return }
        simulation.react(friendID, text: kind.bubble)   // 내 화면에서도 바로 반응
        do {
            try await service.sendPoke(from: uid, to: friendID, groupID: gid, kind: kind)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func checkIncomingPokes() async {
        guard let uid = userID else { return }
        guard let pokes = try? await service.fetchPokes(to: uid, afterID: lastPokeID), !pokes.isEmpty else { return }
        lastPokeID = pokes.map(\.id).max() ?? lastPokeID
        for poke in pokes {
            let name = members.first { $0.id == poke.fromUser }?.profile.nickname ?? "친구"
            simulation.react(uid, text: "\(name): \(poke.kind.bubble)")
        }
    }

    // MARK: 실시간 + 주기적 새로고침

    private func startLiveUpdates() async {
        await service.subscribe { [weak self] table in
            Task { @MainActor in
                guard let self else { return }
                switch table {
                case "pokes": await self.checkIncomingPokes()
                case "group_members": try? await self.reloadGroups()
                default: await self.reloadMembers()
                }
            }
        }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Config.pollInterval * 1_000_000_000))
                guard let self else { return }
                await self.reloadMembers()
                await self.checkIncomingPokes()
            }
        }
    }

    // MARK: 에러 메시지

    static func describe(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("group_full") { return "그룹이 가득 찼어요 (최대 \(Config.maxMembers)명)." }
        if text.contains("invalid_code") { return "초대 코드를 다시 확인해 주세요." }
        if text.contains("profile_required") { return "먼저 캐릭터를 만들어 주세요." }
        if text.contains("anonymous") { return "Supabase 에서 익명 로그인(Anonymous sign-ins)을 켜 주세요." }
        if Config.supabaseURL.contains("YOUR-PROJECT") { return "Config.swift 에 Supabase 주소와 키를 넣어 주세요." }
        return "문제가 생겼어요: \(error.localizedDescription)"
    }
}

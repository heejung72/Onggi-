import Foundation
import Supabase

/// 로그인 세션을 UserDefaults 에 저장 (개발자 계정 없이 서명한 앱에서
/// 키체인 접근이 막히는 문제를 피하기 위한 0단계용 저장소).
/// 앱스토어 출시 단계에서는 기본 키체인 저장소로 되돌리세요.
struct UserDefaultsAuthStorage: AuthLocalStorage {
    private let prefix = "onggi.auth."
    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }
    func retrieve(key: String) throws -> Data? {
        UserDefaults.standard.data(forKey: prefix + key)
    }
    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}

/// Supabase 와 주고받는 모든 일을 한곳에 모은 서비스.
/// 화면 코드는 이 클래스만 부르고, Supabase API 를 직접 만지지 않는다.
final class SupabaseService {
    let client: SupabaseClient
    private var channel: RealtimeChannelV2?

    init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(storage: UserDefaultsAuthStorage())
            )
        )
    }

    // MARK: 로그인 (익명)

    /// 저장된 세션이 있으면 그대로, 없으면 익명으로 가입해 사용자 id 를 돌려준다.
    func signIn() async throws -> UUID {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        let session = try await client.auth.signInAnonymously()
        return session.user.id
    }

    // MARK: 프로필

    func fetchProfile(id: UUID) async throws -> Profile? {
        let rows: [Profile] = try await client.from("profiles")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return rows.first
    }

    func saveProfile(_ profile: Profile) async throws {
        try await client.from("profiles").upsert(profile).execute()
    }

    // MARK: 상태

    func setStatus(userID: UUID, activity: Activity, memo: String?) async throws {
        let row = StatusUpsert(userID: userID, activity: activity, memo: memo)
        try await client.from("statuses").upsert(row, onConflict: "user_id").execute()
    }

    // MARK: 그룹

    func fetchMyGroups() async throws -> [FriendGroup] {
        // RLS 덕분에 내가 속한 그룹만 돌아온다
        try await client.from("groups")
            .select("id, name, invite_code")
            .order("created_at")
            .execute()
            .value
    }

    func createGroup(name: String) async throws -> FriendGroup {
        try await client.rpc("create_group", params: ["p_name": name]).execute().value
    }

    func joinGroup(code: String) async throws -> FriendGroup {
        try await client.rpc("join_group", params: ["p_code": code]).execute().value
    }

    /// 그룹 멤버들의 프로필과 상태를 한 번에 모아 온다 (최대 10명이라 단순하게 3번 조회)
    func fetchMembers(groupID: UUID) async throws -> [Member] {
        let rows: [GroupMemberRow] = try await client.from("group_members")
            .select("user_id")
            .eq("group_id", value: groupID)
            .execute()
            .value
        let ids = rows.map { $0.userID.uuidString }
        guard !ids.isEmpty else { return [] }

        let profiles: [Profile] = try await client.from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
        let statuses: [Status] = try await client.from("statuses")
            .select()
            .in("user_id", values: ids)
            .execute()
            .value

        let statusByUser = Dictionary(uniqueKeysWithValues: statuses.map { ($0.userID, $0) })
        return profiles
            .map { Member(profile: $0, status: statusByUser[$0.id]) }
            .sorted { $0.profile.nickname < $1.profile.nickname }
    }

    // MARK: 찌르기

    func sendPoke(from: UUID, to: UUID, groupID: UUID, kind: PokeKind) async throws {
        let row = PokeInsert(fromUser: from, toUser: to, groupID: groupID, kind: kind)
        try await client.from("pokes").insert(row).execute()
    }

    /// 내가 받은 찌르기 중 afterID 보다 새로운 것
    func fetchPokes(to userID: UUID, afterID: Int) async throws -> [Poke] {
        try await client.from("pokes")
            .select("id, from_user, to_user, kind")
            .eq("to_user", value: userID)
            .gt("id", value: afterID)
            .order("id")
            .execute()
            .value
    }

    func latestPokeID(to userID: UUID) async throws -> Int {
        let rows: [Poke] = try await client.from("pokes")
            .select("id, from_user, to_user, kind")
            .eq("to_user", value: userID)
            .order("id", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.id ?? 0
    }

    // MARK: 실시간

    /// 상태·멤버·찌르기 테이블이 바뀌면 onChange 를 부른다.
    /// 변경 내용 자체는 쓰지 않고 "바뀌었다"는 신호로만 쓴 뒤 다시 조회한다 (단순하고 튼튼함).
    func subscribe(onChange: @escaping @Sendable (String) -> Void) async {
        await unsubscribe()
        let channel = client.channel("onggi-\(UUID().uuidString.prefix(8))")
        let statusChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "statuses")
        let memberChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "group_members")
        let pokeChanges = channel.postgresChange(InsertAction.self, schema: "public", table: "pokes")
        await channel.subscribe()
        self.channel = channel

        Task { for await _ in statusChanges { onChange("statuses") } }
        Task { for await _ in memberChanges { onChange("group_members") } }
        Task { for await _ in pokeChanges { onChange("pokes") } }
    }

    func unsubscribe() async {
        if let channel {
            await channel.unsubscribe()
            self.channel = nil
        }
    }
}

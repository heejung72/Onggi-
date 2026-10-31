import Foundation
import SwiftUI

// MARK: - 상태(활동)

enum Activity: String, Codable, CaseIterable, Identifiable {
    case study, work, sleep, walk, rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .study: return "공부 중"
        case .work: return "일하는 중"
        case .sleep: return "자는 중"
        case .walk: return "산책 중"
        case .rest: return "쉬는 중"
        }
    }

    /// 여러 명이 같은 상태일 때 장면 위에 띄우는 말풍선
    var togetherLabel: String {
        switch self {
        case .study: return "같이 공부 중!"
        case .work: return "같이 일하는 중!"
        case .sleep: return "같이 자는 중"
        case .walk: return "같이 산책 중!"
        case .rest: return "같이 쉬는 중"
        }
    }

    var symbol: String {
        switch self {
        case .study: return "book.fill"
        case .work: return "laptopcomputer"
        case .sleep: return "moon.zzz.fill"
        case .walk: return "figure.walk"
        case .rest: return "cup.and.saucer.fill"
        }
    }

    /// 걷기는 화면을 돌아다니고, 나머지는 제자리에 머문다
    var roams: Bool { self == .walk }
}

// MARK: - 캐릭터

enum Species: String, Codable, CaseIterable, Identifiable {
    case cat, bear, bunny, chick, monkey, puppy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cat: return "고양이"
        case .bear: return "곰"
        case .bunny: return "토끼"
        case .chick: return "병아리"
        case .monkey: return "원숭이"
        case .puppy: return "강아지"
        }
    }
}

enum CharacterColor: String, Codable, CaseIterable, Identifiable {
    case cream, peach, mint, sky, lilac, cocoa
    var id: String { rawValue }

    var fill: Color {
        switch self {
        case .cream: return Color(red: 1.00, green: 0.96, blue: 0.90)
        case .peach: return Color(red: 1.00, green: 0.84, blue: 0.76)
        case .mint:  return Color(red: 0.80, green: 0.94, blue: 0.85)
        case .sky:   return Color(red: 0.81, green: 0.90, blue: 1.00)
        case .lilac: return Color(red: 0.89, green: 0.84, blue: 1.00)
        case .cocoa: return Color(red: 0.79, green: 0.64, blue: 0.49)
        }
    }

    /// 테두리·귀 안쪽 등에 쓰는 진한 색
    var shade: Color {
        switch self {
        case .cream: return Color(red: 0.55, green: 0.47, blue: 0.40)
        case .peach: return Color(red: 0.62, green: 0.40, blue: 0.33)
        case .mint:  return Color(red: 0.33, green: 0.52, blue: 0.40)
        case .sky:   return Color(red: 0.32, green: 0.45, blue: 0.62)
        case .lilac: return Color(red: 0.45, green: 0.38, blue: 0.62)
        case .cocoa: return Color(red: 0.40, green: 0.28, blue: 0.18)
        }
    }
}

// MARK: - DB 행

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String
    var species: Species
    var color: CharacterColor
}

struct Status: Codable, Equatable {
    let userID: UUID
    var activity: Activity
    var memo: String?
    var startedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", activity, memo, startedAt = "started_at"
    }
}

struct StatusUpsert: Encodable {
    let userID: UUID
    let activity: Activity
    let memo: String?
    enum CodingKeys: String, CodingKey { case userID = "user_id", activity, memo }
}

struct FriendGroup: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var inviteCode: String
    enum CodingKeys: String, CodingKey { case id, name, inviteCode = "invite_code" }
}

struct GroupMemberRow: Codable {
    let userID: UUID
    enum CodingKeys: String, CodingKey { case userID = "user_id" }
}

enum PokeKind: String, Codable {
    case poke, cheer, snack
    var bubble: String {
        switch self {
        case .poke: return "콕!"
        case .cheer: return "화이팅!"
        case .snack: return "간식 냠!"
        }
    }
}

struct Poke: Codable, Identifiable {
    let id: Int
    let fromUser: UUID
    let toUser: UUID
    let kind: PokeKind
    enum CodingKeys: String, CodingKey { case id, fromUser = "from_user", toUser = "to_user", kind }
}

struct PokeInsert: Encodable {
    let fromUser: UUID
    let toUser: UUID
    let groupID: UUID
    let kind: PokeKind
    enum CodingKeys: String, CodingKey {
        case fromUser = "from_user", toUser = "to_user", groupID = "group_id", kind
    }
}

// MARK: - 화면용 합본

/// 바탕화면에 그려지는 친구 한 명 (프로필 + 현재 상태)
struct Member: Identifiable, Equatable {
    let profile: Profile
    var status: Status?

    var id: UUID { profile.id }
    var activity: Activity { status?.activity ?? .rest }

    /// "1시간 24분째" 같은 경과 시간
    func elapsedText(now: Date = Date()) -> String {
        guard let start = status?.startedAt else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 { return "방금 시작" }
        if minutes < 60 { return "\(minutes)분째" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)시간째" : "\(h)시간 \(m)분째"
    }
}

import SwiftUI

/// 같이 자는 친구들이 함께 덮는 이불 (인원수만큼 길어진다)
struct BlanketView: View {
    let width: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.80, green: 0.76, blue: 0.96))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .frame(height: 8)
                .padding(.horizontal, 6)
                .padding(.top, 4)
            // 퀼팅 무늬
            HStack(spacing: 22) {
                ForEach(0..<max(1, Int(width / 30)), id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.5)).frame(width: 5, height: 5)
                }
            }
            .padding(.top, 20)
        }
        .frame(width: width, height: 38)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

/// 같이 공부·일하는 친구들이 함께 쓰는 긴 책상
struct DeskView: View {
    let width: CGFloat
    let seats: Int
    let activity: Activity
    let seatSpacing: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // 다리
            HStack {
                Rectangle().fill(Color(red: 0.55, green: 0.40, blue: 0.28)).frame(width: 5, height: 22)
                Spacer()
                Rectangle().fill(Color(red: 0.55, green: 0.40, blue: 0.28)).frame(width: 5, height: 22)
            }
            .padding(.horizontal, 10)
            .offset(y: 8)
            // 상판
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: 0.76, green: 0.58, blue: 0.42))
                .frame(height: 12)
            // 자리마다 책 또는 노트북
            HStack(spacing: 0) {
                ForEach(0..<seats, id: \.self) { _ in
                    deskItem.frame(width: seatSpacing)
                }
            }
            .offset(y: -12)
        }
        .frame(width: width, height: 30)
    }

    @ViewBuilder private var deskItem: some View {
        if activity == .work {
            // 노트북 (뒷면이 보이는 모양)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.82))
                .overlay(Circle().fill(Color.white.opacity(0.9)).frame(width: 4, height: 4))
                .frame(width: 26, height: 16)
        } else {
            // 펼친 책
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.98, green: 0.95, blue: 0.86)).frame(width: 11, height: 12)
                RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.98, green: 0.95, blue: 0.86)).frame(width: 11, height: 12)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.42, green: 0.58, blue: 0.80)))
        }
    }
}

/// 자는 캐릭터 위로 떠오르는 Zzz
struct ZzzView: View {
    let time: Double
    var body: some View {
        let t = time.truncatingRemainder(dividingBy: 2.4) / 2.4
        Text("z z")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(red: 0.45, green: 0.40, blue: 0.70).opacity(1 - t))
            .offset(x: 8 + t * 10, y: -t * 18)
    }
}

/// 말풍선
struct BubbleView: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color(red: 0.30, green: 0.26, blue: 0.40))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.95)))
        .overlay(Capsule().stroke(Color(red: 0.80, green: 0.76, blue: 0.96), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .fixedSize()
    }
}

/// 캐릭터 아래 이름표
struct NameTag: View {
    let name: String
    let isMe: Bool
    var body: some View {
        Text(isMe ? "\(name) (나)" : name)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(isMe ? 0.55 : 0.38)))
            .fixedSize()
    }
}

import SwiftUI

/// 캐릭터의 자세
enum Pose: Equatable {
    case standing
    case walking
    case sitting      // 공부·일·쉬기
    case sleeping
}

/// 오리지널 캐릭터를 도형으로 그린다 (이미지 파일 없이).
/// 부위(몸통·귀·얼굴·발)를 따로 그려서, 나중에 옷·소품 레이어를 얹기 쉽게 만든다.
struct CharacterView: View {
    let species: Species
    let color: CharacterColor
    var pose: Pose = .standing
    var facingLeft = false
    /// 0... 증가하는 시간 값 (애니메이션용)
    var time: Double = 0
    var size: CGFloat = 64

    private var s: CGFloat { size }

    /// 걷기·숨쉬기에 따른 위아래 흔들림
    private var bob: CGFloat {
        switch pose {
        case .walking: return CGFloat(abs(sin(time * 9))) * -s * 0.06
        case .sleeping: return 0
        default: return CGFloat(sin(time * 2)) * s * 0.012
        }
    }

    var body: some View {
        ZStack {
            feet
            ears
            bodyShape
            face
        }
        .frame(width: s, height: s)
        .scaleEffect(x: facingLeft ? -1 : 1, y: pose == .sleeping ? 0.86 : 1, anchor: .bottom)
        .offset(y: bob)
    }

    // MARK: 몸통

    private var bodyShape: some View {
        Ellipse()
            .fill(color.fill)
            .overlay(Ellipse().stroke(color.shade.opacity(0.55), lineWidth: s * 0.03))
            .frame(width: s * 0.86, height: s * 0.74)
            .offset(y: s * 0.06)
    }

    // MARK: 귀 (종류마다 다름)

    @ViewBuilder private var ears: some View {
        switch species {
        case .cat:
            HStack(spacing: s * 0.26) {
                Triangle().fill(color.fill).overlay(Triangle().stroke(color.shade.opacity(0.55), lineWidth: s * 0.03))
                    .frame(width: s * 0.24, height: s * 0.24).rotationEffect(.degrees(-12))
                Triangle().fill(color.fill).overlay(Triangle().stroke(color.shade.opacity(0.55), lineWidth: s * 0.03))
                    .frame(width: s * 0.24, height: s * 0.24).rotationEffect(.degrees(12))
            }
            .offset(y: -s * 0.30)
        case .bear, .monkey:
            HStack(spacing: species == .monkey ? s * 0.62 : s * 0.40) {
                roundEar
                roundEar
            }
            .offset(y: species == .monkey ? -s * 0.02 : -s * 0.27)
        case .bunny:
            HStack(spacing: s * 0.12) {
                bunnyEar.rotationEffect(.degrees(-8))
                bunnyEar.rotationEffect(.degrees(8))
            }
            .offset(y: -s * 0.40)
        case .puppy:
            HStack(spacing: s * 0.66) {
                Ellipse().fill(color.shade.opacity(0.7)).frame(width: s * 0.18, height: s * 0.32).rotationEffect(.degrees(18))
                Ellipse().fill(color.shade.opacity(0.7)).frame(width: s * 0.18, height: s * 0.32).rotationEffect(.degrees(-18))
            }
            .offset(y: -s * 0.08)
        case .chick:
            // 머리 위 깃털 한 가닥
            Capsule().fill(color.shade.opacity(0.6))
                .frame(width: s * 0.05, height: s * 0.16)
                .rotationEffect(.degrees(15))
                .offset(y: -s * 0.36)
        }
    }

    private var roundEar: some View {
        Circle().fill(color.fill)
            .overlay(Circle().stroke(color.shade.opacity(0.55), lineWidth: s * 0.03))
            .overlay(Circle().fill(color.shade.opacity(0.25)).padding(s * 0.05))
            .frame(width: s * 0.22, height: s * 0.22)
    }

    private var bunnyEar: some View {
        Capsule().fill(color.fill)
            .overlay(Capsule().stroke(color.shade.opacity(0.55), lineWidth: s * 0.03))
            .overlay(Capsule().fill(Color.pink.opacity(0.25)).padding(s * 0.04))
            .frame(width: s * 0.16, height: s * 0.38)
    }

    // MARK: 얼굴

    private var face: some View {
        ZStack {
            if species == .monkey {
                Ellipse().fill(Color.white.opacity(0.55))
                    .frame(width: s * 0.5, height: s * 0.36)
                    .offset(y: s * 0.10)
            }
            // 눈
            HStack(spacing: s * 0.24) { eye; eye }
                .offset(y: s * 0.03)
            // 볼터치
            HStack(spacing: s * 0.40) {
                Ellipse().fill(Color.pink.opacity(0.35)).frame(width: s * 0.12, height: s * 0.07)
                Ellipse().fill(Color.pink.opacity(0.35)).frame(width: s * 0.12, height: s * 0.07)
            }
            .offset(y: s * 0.12)
            // 입
            if species == .chick {
                Triangle().fill(Color.orange.opacity(0.85))
                    .frame(width: s * 0.10, height: s * 0.07)
                    .rotationEffect(.degrees(180))
                    .offset(y: s * 0.12)
            } else {
                Mouth().stroke(color.shade, style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
                    .frame(width: s * 0.12, height: s * 0.05)
                    .offset(y: s * 0.13)
            }
        }
        .offset(y: s * 0.04)
    }

    @ViewBuilder private var eye: some View {
        if pose == .sleeping || blinking {
            ClosedEye().stroke(Color.black.opacity(0.8), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
                .frame(width: s * 0.08, height: s * 0.03)
        } else {
            Ellipse().fill(Color.black.opacity(0.85))
                .frame(width: s * 0.065, height: s * 0.085)
        }
    }

    /// 몇 초에 한 번 눈 깜빡임
    private var blinking: Bool {
        (time.truncatingRemainder(dividingBy: 4.2)) < 0.12
    }

    // MARK: 발

    private var feet: some View {
        let step = pose == .walking ? CGFloat(sin(time * 9)) * s * 0.04 : 0
        return HStack(spacing: s * 0.20) {
            Capsule().fill(color.fill).overlay(Capsule().stroke(color.shade.opacity(0.55), lineWidth: s * 0.025))
                .frame(width: s * 0.18, height: s * 0.11).offset(y: step)
            Capsule().fill(color.fill).overlay(Capsule().stroke(color.shade.opacity(0.55), lineWidth: s * 0.025))
                .frame(width: s * 0.18, height: s * 0.11).offset(y: -step)
        }
        .offset(y: s * 0.42)
        .opacity(pose == .sleeping ? 0 : 1)
    }
}

// MARK: - 도형

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// "w" 모양 입
struct Mouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - r.width * 0.25, y: r.maxY))
        return p
    }
}

/// 감은 눈 (아래로 볼록한 곡선)
struct ClosedEye: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 2))
        return p
    }
}

#Preview {
    HStack {
        ForEach(Species.allCases) { sp in
            CharacterView(species: sp, color: .cream)
        }
    }
    .padding()
}

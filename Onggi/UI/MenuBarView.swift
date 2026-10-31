import SwiftUI
import AppKit

/// 메뉴바 발바닥 아이콘을 누르면 뜨는 창: 내 상태 바꾸기, 그룹 고르기, 표시 설정
struct MenuBarView: View {
    @ObservedObject var app: AppState
    let openSetup: (SetupView.Tab) -> Void

    @State private var memo = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch app.phase {
            case .loading:
                HStack { ProgressView().controlSize(.small); Text("불러오는 중…") }
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.red)
                Button("다시 시도") { Task { await app.bootstrap() } }
            case .needsProfile:
                Text("캐릭터를 만들고 친구들을 초대해 보세요.")
                Button("시작하기") { openSetup(.character) }.buttonStyle(.borderedProminent)
            case .needsGroup:
                Text("그룹을 만들거나 초대 코드로 가입해 주세요.")
                Button("그룹 만들기 · 가입") { openSetup(.group) }.buttonStyle(.borderedProminent)
            case .ready:
                readyContent
            }

            if let error = app.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .onTapGesture { app.errorMessage = nil }
            }

            Divider()
            Toggle("바탕화면에 캐릭터 보이기", isOn: $app.overlayVisible)
            Toggle("모든 창 위에 표시", isOn: $app.overlayOnTop)
                .disabled(!app.overlayVisible)
            HStack {
                Button("캐릭터 꾸미기") { openSetup(.character) }
                    .disabled(app.me == nil)
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { memo = app.myMember?.status?.memo ?? "" }
    }

    // MARK: 준비 완료 화면

    @ViewBuilder private var readyContent: some View {
        // 나
        if let me = app.me {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { ctx in
                    CharacterView(species: me.species, color: me.color,
                                  pose: app.myMember?.activity == .sleep ? .sleeping : .standing,
                                  time: ctx.date.timeIntervalSinceReferenceDate, size: 44)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(me.nickname).font(.system(size: 14, weight: .bold, design: .rounded))
                    if let mine = app.myMember {
                        Text("\(mine.activity.label) · \(mine.elapsedText())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        // 상태 버튼
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(Activity.allCases) { activity in
                let selected = app.myMember?.activity == activity
                Button {
                    Task { await app.setActivity(activity) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: activity.symbol).font(.system(size: 16))
                        Text(activity.label.replacingOccurrences(of: " 중", with: ""))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }

        // 한 줄 메모
        HStack {
            TextField("한 줄 메모 (예: 시험 D-3)", text: $memo)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await app.setMemo(memo) } }
            Button("저장") { Task { await app.setMemo(memo) } }
        }

        Divider()

        // 그룹
        if app.groups.count > 1 {
            Picker("바탕화면에 보일 그룹", selection: $app.selectedGroupID) {
                ForEach(app.groups) { g in
                    Text(g.name).tag(Optional(g.id))
                }
            }
        }
        if let group = app.selectedGroup {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.name) · \(app.members.count)명").font(.system(size: 13, weight: .semibold))
                    Text("초대 코드 \(group.inviteCode)")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(copied ? "복사됨" : "코드 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(group.inviteCode, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .controlSize(.small)
            }
        }
        Button("그룹 추가 · 가입") { openSetup(.group) }
            .buttonStyle(.borderless)
    }
}

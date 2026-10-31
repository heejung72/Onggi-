import SwiftUI

/// 처음 실행 시: 캐릭터 만들기 → 그룹 만들기 또는 초대 코드로 가입
struct SetupView: View {
    enum Tab: Hashable { case character, group }

    @ObservedObject var app: AppState
    let initialTab: Tab
    let onDone: () -> Void

    @State private var tab: Tab = .character
    @State private var nickname = ""
    @State private var species: Species = .cat
    @State private var color: CharacterColor = .cream
    @State private var groupName = ""
    @State private var inviteCode = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $tab) {
                Text("내 캐릭터").tag(Tab.character)
                Text("그룹").tag(Tab.group)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(app.me == nil)   // 캐릭터를 먼저 만들어야 그룹으로 갈 수 있음

            if tab == .character { characterTab } else { groupTab }

            if let error = app.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
                    .onTapGesture { app.errorMessage = nil }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 420, height: 520)
        .onAppear {
            tab = app.me == nil ? .character : initialTab
            if let me = app.me {
                nickname = me.nickname
                species = me.species
                color = me.color
            }
        }
    }

    // MARK: 캐릭터

    private var characterTab: some View {
        VStack(spacing: 18) {
            TimelineView(.animation) { context in
                CharacterView(species: species, color: color,
                              time: context.date.timeIntervalSinceReferenceDate, size: 110)
            }
            .frame(height: 130)

            TextField("닉네임 (최대 20자)", text: $nickname)
                .textFieldStyle(.roundedBorder)
                .onChange(of: nickname) { _, new in
                    if new.count > 20 { nickname = String(new.prefix(20)) }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("캐릭터").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(Species.allCases) { sp in
                        Button { species = sp } label: {
                            VStack(spacing: 2) {
                                CharacterView(species: sp, color: color, size: 40)
                                Text(sp.label).font(.caption2)
                            }
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .stroke(species == sp ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("색").font(.headline).padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach(CharacterColor.allCases) { c in
                        Circle().fill(c.fill)
                            .overlay(Circle().stroke(c.shade.opacity(0.5)))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: color == c ? 3 : 0).padding(-3))
                            .frame(width: 26, height: 26)
                            .onTapGesture { color = c }
                    }
                }
            }

            Button {
                busy = true
                Task {
                    await app.saveProfile(nickname: nickname.trimmingCharacters(in: .whitespaces),
                                          species: species, color: color)
                    busy = false
                    if app.errorMessage == nil {
                        if app.phase == .ready { onDone() } else { tab = .group }
                    }
                }
            } label: {
                Text(app.me == nil ? "캐릭터 만들기" : "저장").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || nickname.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: 그룹

    private var groupTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !app.groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("내 그룹").font(.headline)
                    ForEach(app.groups) { g in
                        HStack {
                            Text(g.name)
                            Spacer()
                            Text(g.inviteCode).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("새 그룹 만들기").font(.headline)
                HStack {
                    TextField("그룹 이름 (예: 우리 방)", text: $groupName).textFieldStyle(.roundedBorder)
                    Button("만들기") {
                        busy = true
                        Task {
                            await app.createGroup(name: groupName)
                            busy = false
                            if app.errorMessage == nil { groupName = ""; onDone() }
                        }
                    }
                    .disabled(busy || groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("만들면 6자리 초대 코드가 생겨요. 친구에게 보내 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("초대 코드로 가입").font(.headline)
                HStack {
                    TextField("예: A1B2C3", text: $inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("가입") {
                        busy = true
                        Task {
                            await app.joinGroup(code: inviteCode)
                            busy = false
                            if app.errorMessage == nil { inviteCode = ""; onDone() }
                        }
                    }
                    .disabled(busy || inviteCode.trimmingCharacters(in: .whitespaces).count < 6)
                }
                Text("그룹은 여러 개 가입할 수 있고, 한 그룹은 최대 \(Config.maxMembers)명이에요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

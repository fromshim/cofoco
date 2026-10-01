import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var notifications: LocalNotifications
    @State private var newProject = ""
    @State private var integrationID = ""
    @State private var allowPersonal = false
    @State private var selectedProjects: Set<String> = []

    init(model: AppModel) {
        self.model = model
        notifications = model.notifications
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.screen = .list } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("목록으로 돌아가기")
                Text("설정").font(.system(size: 15, weight: .semibold))
                Spacer()
            }.padding(14)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    projectSettings
                    integrationSettings
                    petSettings
                    Toggle("조용히 보기", isOn: $model.quietMode)
                        .font(.system(size: 12))
                        .help("변경 알림을 숨기지만 기록과 승인 대기는 유지합니다")
                    Toggle("macOS 알림", isOn: Binding(get: { notifications.enabled },
                        set: { enabled in Task { await notifications.setEnabled(enabled) } }))
                        .font(.system(size: 12))
                    if let status = notifications.status {
                        Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .disabled(model.isMutating)
        .onExitCommand { model.screen = .list }
        .onChange(of: model.recoveredMutation) { _, recovered in
            guard let recovered, recovered.path == "/v1/owner/projects", recovered.method == "POST",
                  let body = try? recovered.object, body["name"] as? String == newProject else { return }
            newProject = ""
        }
    }

    private var projectSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("프로젝트").font(.system(size: 12, weight: .semibold))
            ForEach(model.projects) { project in
                ProjectSettingsRow(model: model, project: project)
            }
            HStack(spacing: 6) {
                TextField("프로젝트 이름", text: $newProject)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { addProject() }
                Button { addProject() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).accessibilityLabel("프로젝트 추가")
            }
        }
    }

    private func addProject() {
        let value = newProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task { if await model.createProject(value) { newProject = "" } }
    }

    private var integrationSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("에이전트 연결").font(.system(size: 12, weight: .semibold))
            Text("같은 연결을 쓰는 세션은 선택한 범위를 공유합니다. 폴더는 권한 경계가 아닙니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.integrations) { grant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(grant.id).font(.system(size: 12))
                        Text(grant.revoked ? "해제됨" : "설정됨 · 연결 상태 미측정")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(grant.scopes.joined(separator: ", "))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if !grant.revoked {
                        Button("해제") { Task { await model.revokeIntegration(grant.id) } }
                            .font(.system(size: 11))
                    }
                }
            }
            TextField("연결 이름 (예: claude-local)", text: $integrationID)
                .textFieldStyle(.roundedBorder).font(.system(size: 12))
            Toggle("내 할 일 접근 허용", isOn: $allowPersonal).font(.system(size: 11))
            if !model.projects.isEmpty {
                Text("프로젝트 범위").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(model.projects) { project in
                    Toggle(project.name, isOn: Binding(
                        get: { selectedProjects.contains(project.id) },
                        set: { selected in
                            if selected { selectedProjects.insert(project.id) }
                            else { selectedProjects.remove(project.id) }
                        }
                    )).font(.system(size: 11))
                }
            }
            Button("권한 부여") {
                let id = integrationID.trimmingCharacters(in: .whitespacesAndNewlines)
                var scopes = selectedProjects.sorted().map { "project:\($0)" }
                if allowPersonal { scopes.insert("personal", at: 0) }
                guard !id.isEmpty, !scopes.isEmpty else {
                    model.errorMessage = "연결 이름과 허용 범위를 골라주세요."
                    return
                }
                Task { await model.grantIntegration(id, scopes: scopes) }
            }
            .font(.system(size: 11))
            Text("현재는 권한만 생성합니다. Claude/Codex 설정 파일 연결은 수동으로 해야 합니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var petSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("펫").font(.system(size: 12, weight: .semibold))
            Text("PNG/WebP를 기기에 복사합니다. 사용하는 이미지의 권리는 직접 확인해 주세요.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(PetPose.allCases, id: \.self) { pose in
                HStack {
                    Text(pose.label).font(.system(size: 11))
                    Spacer()
                    Text("\(model.petPack.frames[pose]?.count ?? 0)장")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("가져오기") { importFrames(for: pose) }
                        .font(.system(size: 11))
                        .disabled(pose != .idle && (model.petPack.frames[.idle] ?? []).isEmpty)
                }
            }
            Button("이미지 생성 프롬프트 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.petPrompt, forType: .string)
            }
            .font(.system(size: 11))
        }
    }

    private func importFrames(for pose: PetPose) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "프레임은 파일 이름 순서로 재생합니다. 01, 02, 03처럼 이름을 붙여 주세요."
        guard panel.runModal() == .OK else { return }
        model.importPetFrames(panel.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }, pose: pose)
    }

    private static let petPrompt = """
    첨부한 캐릭터와 같은 외형·선 스타일의 투명 배경 PNG 또는 WebP 프레임을 만들어주세요. \
    idle: 서기/중립적 눈 감기 2장. noticed: 짧은 팔이 몸 앞에서 도는 자세 3장(1-2-3-2-1). \
    working: 얼굴을 유지한 채 아래 몸통만 좌우로 흔드는 자세 3장(A-B-A-C-A). \
    resting: 눕기/가볍게 숨쉬기 2장. 모든 프레임은 같은 캔버스, 몸집, 기준선, 투명 알파를 유지하고 \
    배경·그림자·글자·워터마크를 넣지 마세요.
    """
}

private struct ProjectSettingsRow: View {
    @ObservedObject var model: AppModel
    let project: AppProject
    @State private var name = ""
    @FocusState private var editing: Bool
    @State private var editingRevision: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("프로젝트 이름", text: $name)
                .focused($editing)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .onSubmit {
                    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty && value != project.name {
                        var edited = project
                        edited.revision = editingRevision ?? project.revision
                        Task { await model.renameProject(edited, name: value) }
                    }
                }
            ForEach(model.projectFolders[project.id] ?? [], id: \.self) { folder in
                HStack {
                    Text(folder).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { Task { await model.changeFolder(project, path: folder, add: false) } } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }.buttonStyle(.plain).accessibilityLabel("폴더 연결 해제: \(folder)")
                }
            }
            Button("폴더 연결") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                Task { await model.changeFolder(project, path: url.path, add: true) }
            }
            .font(.system(size: 10))
        }
        .onAppear { name = project.name }
        .onChange(of: project.name) { old, value in if name == old { name = value } }
        .onChange(of: editing) { _, focused in editingRevision = focused ? project.revision : nil }
    }
}

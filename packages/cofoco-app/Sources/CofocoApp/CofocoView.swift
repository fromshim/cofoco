import AppKit
import SwiftUI

struct GlassBackground: NSViewRepresentable {
    var strong = false
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = strong ? .popover : .hudWindow
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = strong ? .popover : .hudWindow
    }
}

private struct BubbleSurface: ViewModifier {
    var strong = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: strong ? 16 : 20, style: .continuous)
        content
            .background {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    GlassBackground(strong: strong).clipShape(shape)
                }
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.14), radius: 16, y: 5)
    }
}

extension View {
    func bubbleSurface(strong: Bool = false) -> some View { modifier(BubbleSurface(strong: strong)) }
}

struct CofocoView: View {
    @ObservedObject var model: AppModel
    let toggleBubble: () -> Void
    let dragPet: (CGSize) -> Void
    let finishDrag: () -> Void
    let bubbleVisibilityChanged: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0)
            if model.bubbleVisible {
                if model.hasChangeBubble {
                    ChangeBubbleView(model: model)
                        .frame(width: 324, height: model.changeBubbleHeight)
                        .bubbleSurface(strong: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                bubble
                    .frame(width: 324, height: model.mainBubbleHeight)
                    .bubbleSurface()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Button(action: toggleBubble) {
                PetArtwork(pack: model.petPack, pose: model.petPose)
            }
            .buttonStyle(.plain)
            .help(model.bubbleVisible ? "할 일 접기" : "할 일 열기")
            .accessibilityLabel(model.bubbleVisible ? "할 일 말풍선 접기" : "할 일 말풍선 열기")
            .simultaneousGesture(DragGesture(minimumDistance: 4)
                .onChanged { dragPet($0.translation) }
                .onEnded { _ in finishDrag() })
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(10)
        .frame(width: model.bubbleVisible ? 350 : 132,
               height: model.panelHeight, alignment: .bottomTrailing)
        .onChange(of: model.bubbleVisible) { _, _ in bubbleVisibilityChanged() }
        .onChange(of: model.hasChangeBubble) { _, _ in bubbleVisibilityChanged() }
        .onChange(of: model.changeBubbleHeight) { _, _ in bubbleVisibilityChanged() }
    }

    @ViewBuilder private var bubble: some View {
        VStack(spacing: 0) {
            if !model.serviceAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                    Text("다시 연결하는 중")
                    Spacer()
                    Button("재시도") { Task { await model.refresh() } }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .accessibilityLabel("서비스 연결 안 됨. 재시도 가능")
            }
            if let error = model.errorMessage,
               model.serviceAvailable || error != AppAPIError.serviceUnavailable.localizedDescription {
                HStack {
                    Text(error).font(.system(size: 11)).lineLimit(2)
                    Spacer()
                    Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("오류 닫기")
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            switch model.screen {
            case .list: TodoListView(model: model)
            case .detail(let id): TodoDetailView(model: model, id: id)
            case .history(let id): HistoryView(model: model, id: id)
            case .trash: TrashView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .disabled((!model.serviceAvailable || model.awaitingConfirmation) && model.screen != .list)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChangeBubbleView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let proposal = model.pendingProposals.first {
                HStack {
                    Text("변경 제안").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if model.pendingProposals.count > 1 {
                        Text("1 / \(model.pendingProposals.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text(proposal.actorId.replacingOccurrences(of: "integration:", with: "") + " · " + proposal.reason)
                    .font(.system(size: 11)).lineLimit(2)
                if proposal.changes.count > 1 {
                    Text("\(proposal.changes.count)개 변경을 함께 적용합니다")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in
                            ProposalPreview(model: model, change: change)
                        }
                    }
                }
                .frame(maxHeight: 85)
                HStack {
                    Button("거절") { Task { await model.review(proposal, accept: false) } }
                    Spacer()
                    Button("승인") { Task { await model.review(proposal, accept: true) } }
                        .buttonStyle(.borderedProminent)
                }
                .font(.system(size: 12))
                .disabled(model.isMutating || !model.serviceAvailable)
            } else if let event = model.currentAlert {
                HStack {
                    Text(event.actorId.replacingOccurrences(of: "integration:", with: ""))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("1 / \(model.alerts.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(model.todos.first(where: { $0.id == event.aggregateId })?.title ?? "할 일이 변경됐어요")
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                HStack {
                    Text(event.operationLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("확인") { model.acknowledgeAlert() }.font(.system(size: 11))
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct ProposalPreview: View {
    @ObservedObject var model: AppModel
    let change: AppProposalChange

    private var changes: [String] {
        let after = change.after
        guard let before = change.before else {
            return ["새 할 일: \(after.title)", "프로젝트: \(model.projectName(for: after.scope))"]
        }
        var lines: [String] = []
        if before.title != after.title { lines.append("제목: \(before.title) → \(after.title)") }
        if before.scope != after.scope {
            lines.append("프로젝트: \(model.projectName(for: before.scope)) → \(model.projectName(for: after.scope))")
        }
        if before.status != after.status { lines.append("상태: \(status(before.status)) → \(status(after.status))") }
        if change.operation == "delete" { lines.append("휴지통으로 이동: \(before.title)") }
        if change.operation == "restore" { lines.append("복원: \(before.title)") }
        for old in before.steps ?? [] {
            if let new = after.steps?.first(where: { $0.id == old.id }) {
                if new.title != old.title { lines.append("단계: \(old.title) → \(new.title)") }
                if new.isDone != old.isDone { lines.append("단계 \(new.isDone ? "완료" : "재열기"): \(new.title)") }
            } else { lines.append("단계 삭제: \(old.title)") }
        }
        for new in after.steps ?? [] where !(before.steps ?? []).contains(where: { $0.id == new.id }) {
            lines.append("단계 추가: \(new.title)")
        }
        for old in before.notes ?? [] {
            if let new = after.notes?.first(where: { $0.id == old.id }) {
                if new.text != old.text { lines.append("메모: \(old.text) → \(new.text)") }
            } else { lines.append("메모 삭제: \(old.text)") }
        }
        for new in after.notes ?? [] where !(before.notes ?? []).contains(where: { $0.id == new.id }) {
            lines.append("메모 추가: \(new.text)")
        }
        return lines.isEmpty ? [after.title] : lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ value: AppTodoStatus) -> String {
        switch value { case .open: "안 함"; case .in_progress: "하는 중"; case .done: "완료" }
    }
}

struct TodoListView: View {
    @ObservedObject var model: AppModel
    @State private var composerOpen = false
    @State private var draft = ""
    @State private var draftScope: AppScope = .personal
    @State private var showCompleted = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    Button("전체") { model.setScope("all") }
                    Button("내 할 일") { model.setScope("personal") }
                    ForEach(model.projects) { project in
                        Button(project.name) { model.setScope("project:\(project.id)") }
                    }
                    Button("프로젝트 추가…") { model.screen = .settings }
                } label: {
                    (Text(model.selectedScopeName) + Text(" ") + Text(Image(systemName: "chevron.down")).font(.system(size: 9)))
                        .font(.system(size: 15, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("할 일 범위: \(model.selectedScopeName)")
                Spacer()
                Menu {
                    Button("설정") { model.screen = .settings }
                    Button("휴지통") { model.screen = .trash }
                    Button("완료한 일") { showCompleted.toggle() }
                    Button("말풍선 접기") { model.bubbleVisible = false }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("더 보기")
            }
            .frame(height: 38)
            .padding(.horizontal, 14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.activeTodos.isEmpty {
                        Text("아직 할 일이 없어요")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 70)
                    }
                    ForEach(model.activeTodos) { todo in
                        TodoRow(model: model, todo: todo)
                    }
                    if !model.completedTodos.isEmpty {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            ForEach(model.completedTodos) { todo in TodoRow(model: model, todo: todo) }
                        } label: {
                            Text("완료 · \(model.completedTodos.count)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.top, 10)
                    }
                }
                .padding(.top, 2)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $model.listScrollAnchor)

            if composerOpen {
                VStack(alignment: .leading, spacing: 5) {
                    Menu {
                        Button("내 할 일") { draftScope = .personal }
                        ForEach(model.projects) { project in
                            Button(project.name) { draftScope = .project(project.id) }
                        }
                        Button("프로젝트 추가…") { model.screen = .settings }
                    } label: {
                        (Text(model.projectName(for: draftScope)) + Text(" ") + Text(Image(systemName: "chevron.down")).font(.system(size: 9)))
                        .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    TextField("할 일 추가", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($composerFocused)
                        .onSubmit {
                            let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !title.isEmpty else { return }
                            Task {
                                if await model.addTodo(title, scope: draftScope) {
                                    draft = ""; composerOpen = false
                                }
                            }
                        }
                        .accessibilityLabel("새 할 일 제목")
                        .disabled(model.isMutating || model.awaitingConfirmation || !model.serviceAvailable)
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            } else {
                Button {
                    draftScope = .personal
                    composerOpen = true
                    DispatchQueue.main.async { composerFocused = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .help("할 일 추가")
                .accessibilityLabel("할 일 추가")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14).padding(.bottom, 12)
            }
        }
        .onKeyPress("n", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            draftScope = .personal; composerOpen = true
            DispatchQueue.main.async { composerFocused = true }
            return .handled
        }
        .onChange(of: model.requestComposer) { _, requested in
            guard requested else { return }
            draftScope = .personal; composerOpen = true
            DispatchQueue.main.async { composerFocused = true; model.requestComposer = false }
        }
        .onChange(of: model.recoveredMutation) { _, recovered in
            guard let recovered, recovered.method == "POST", recovered.path == "/v1/owner/todos",
                  let body = try? recovered.object, body["title"] as? String == draft else { return }
            draft = ""; composerOpen = false
        }
        .onExitCommand {
            if composerOpen { composerOpen = false; composerFocused = false }
            else { model.bubbleVisible = false }
        }
    }
}

struct TodoRow: View {
    @ObservedObject var model: AppModel
    let todo: AppTodo
    @State private var hovering = false
    @FocusState private var rowFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Button {
                if todo.status != .done { model.retainedCompleted.insert(todo.id) }
                Task { await model.updateTodo(todo, status: todo.status == .done ? .open : .done) }
            } label: {
                Image(systemName: todo.status == .done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 25, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.status == .done ? "완료 취소: \(todo.title)" : "완료: \(todo.title)")
            Text(model.projectMark(for: todo.scope))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.projectColor(for: todo.scope))
                .frame(width: 16)
                .help(model.projectName(for: todo.scope))
                .accessibilityLabel(model.projectName(for: todo.scope))
            Button { Task { await model.showDetail(todo.id) } } label: {
                Text(todo.title)
                    .font(.system(size: 13))
                    .foregroundStyle(todo.status == .done ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("상세 보기: \(todo.title), \(model.projectName(for: todo.scope))")
            if todo.status == .in_progress {
                Menu {
                    Button("안 함으로 변경") { Task { await model.updateTodo(todo, status: .open) } }
                    Button("상세 보기") { Task { await model.showDetail(todo.id) } }
                } label: { ProgressDots().frame(width: 27, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("진행 중: \(todo.title). 상태 변경 메뉴")
            } else if todo.status == .open {
                Button { Task { await model.updateTodo(todo, status: .in_progress) } } label: {
                    Image(systemName: "play.fill").font(.system(size: 10)).frame(width: 27, height: 28)
                }
                .buttonStyle(.plain)
                .opacity(hovering || rowFocused ? 1 : 0)
                .help("진행 시작")
                .accessibilityLabel("진행 시작: \(todo.title)")
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
        .background(hovering || rowFocused ? Color.primary.opacity(0.045) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .focusable()
        .focused($rowFocused)
        .onKeyPress(.return) { Task { await model.showDetail(todo.id) }; return .handled }
        .onKeyPress(.space) {
            if todo.status != .done { model.retainedCompleted.insert(todo.id) }
            Task { await model.updateTodo(todo, status: todo.status == .done ? .open : .done) }
            return .handled
        }
        .onHover { inside in
            hovering = inside
            if !inside && !rowFocused { model.retainedCompleted.remove(todo.id) }
        }
        .onChange(of: rowFocused) { _, focused in
            if !focused && !hovering { model.retainedCompleted.remove(todo.id) }
        }
        .disabled(model.isMutating || model.awaitingConfirmation || !model.serviceAvailable)
    }
}

struct ProgressDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if reduceMotion {
            Text("…").font(.system(size: 15, weight: .semibold))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let time = timeline.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 4)
                HStack(spacing: 2) {
                    ForEach(0..<3) { index in
                        Circle().fill(Color.primary).frame(width: 3, height: 3)
                            .offset(y: DotMotion.offset(index: index, elapsed: time))
                    }
                }
            }
        }
    }
}

enum DotMotion {
    static func offset(index: Int, elapsed: TimeInterval) -> CGFloat {
        let local = elapsed.truncatingRemainder(dividingBy: 4) - Double(index) * 0.17
        guard local >= 0, local < 0.45 else { return 0 }
        return -2.5 * sin(local / 0.45 * .pi)
    }
}

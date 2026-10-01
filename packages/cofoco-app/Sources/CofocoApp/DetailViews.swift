import SwiftUI

struct TodoDetailView: View {
    @ObservedObject var model: AppModel
    let id: String
    @State private var titleDraft = ""
    @State private var stepDraft = ""
    @State private var noteDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var titleRevision: Int64?
    @State private var titleBaseline = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.screen = .list } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).frame(width: 28, height: 30)
                    .accessibilityLabel("할 일 목록으로")
                Spacer()
                Menu {
                    Button("변경 이력") { model.screen = .history(id); Task { await model.loadHistory(id) } }
                    if let todo = model.selectedTodo {
                        Button("휴지통으로 이동", role: .destructive) { Task { await model.deleteTodo(todo) } }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 30) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("상세 메뉴")
            }
            .padding(.horizontal, 12).frame(height: 38)

            if let todo = model.selectedTodo, todo.id == id {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Menu {
                            Button("내 할 일") { Task { await model.updateTodo(todo, scope: .personal) } }
                            ForEach(model.projects) { project in
                                Button(project.name) { Task { await model.updateTodo(todo, scope: .project(project.id)) } }
                            }
                        } label: {
                            (Text(model.projectName(for: todo.scope)) + Text(" ") + Text(Image(systemName: "chevron.down")).font(.system(size: 9)))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("프로젝트: \(model.projectName(for: todo.scope))")

                        TextField("할 일 제목", text: $titleDraft, axis: .vertical)
                            .focused($titleFocused)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold))
                            .onSubmit {
                                let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !title.isEmpty && title != todo.title {
                                    var edited = todo
                                    edited.revision = titleRevision ?? todo.revision
                                    Task { await model.updateTodo(edited, title: title) }
                                }
                            }
                            .accessibilityLabel("할 일 제목 수정")

                        HStack(spacing: 8) {
                            Button { Task { await model.updateTodo(todo, status: todo.status == .done ? .open : .done) } } label: {
                                Label(todo.status == .done ? "완료" : "완료 표시",
                                      systemImage: todo.status == .done ? "checkmark.square.fill" : "square")
                            }
                            .buttonStyle(.plain)
                            if todo.status == .open {
                                Button { Task { await model.updateTodo(todo, status: .in_progress) } } label: {
                                    Label("시작", systemImage: "play.fill")
                                }.buttonStyle(.plain)
                            } else if todo.status == .in_progress {
                                Menu {
                                    Button("안 함") { Task { await model.updateTodo(todo, status: .open) } }
                                    Button("완료") { Task { await model.updateTodo(todo, status: .done) } }
                                } label: { Text("하는 중 ···") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)

                        steps(todo)
                        notes(todo)
                        if !(todo.deletedSteps ?? []).isEmpty || !(todo.deletedNotes ?? []).isEmpty {
                            DisclosureGroup("삭제한 단계·메모") {
                                ForEach(todo.deletedSteps ?? []) { step in
                                    HStack {
                                        Text(step.title).font(.system(size: 12))
                                        Spacer()
                                        Button("복원") { Task { await model.changeStep(todo, operation: "restore", id: step.id) } }
                                    }
                                }
                                ForEach(todo.deletedNotes ?? []) { note in
                                    HStack {
                                        Text(note.text).font(.system(size: 12)).lineLimit(2)
                                        Spacer()
                                        Button("복원") { Task { await model.changeNote(todo, operation: "restore", id: note.id) } }
                                    }
                                }
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .onAppear { titleDraft = todo.title; titleBaseline = todo.title }
                .onChange(of: todo.revision) { _, _ in
                    if titleDraft == titleBaseline || titleDraft == todo.title {
                        titleDraft = todo.title; titleBaseline = todo.title
                        if titleFocused { titleRevision = todo.revision }
                    }
                }
                .onChange(of: titleFocused) { _, focused in titleRevision = focused ? todo.revision : nil }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .disabled(model.isMutating)
        .onExitCommand { model.screen = .list }
        .onChange(of: model.recoveredMutation) { _, recovered in
            guard let recovered, let body = try? recovered.object else { return }
            if recovered.path == "/v1/owner/todos/\(id)/steps", body["operation"] as? String == "add",
               body["title"] as? String == stepDraft { stepDraft = "" }
            if recovered.path == "/v1/owner/todos/\(id)/notes", body["operation"] as? String == "append",
               body["text"] as? String == noteDraft { noteDraft = "" }
        }
    }

    private func steps(_ todo: AppTodo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("단계").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let steps = todo.steps, !steps.isEmpty {
                    Text("\(steps.filter(\.isDone).count)/\(steps.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            ForEach(todo.steps ?? []) { step in
                StepRow(model: model, todo: todo, step: step)
            }
            HStack {
                Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("단계 추가", text: $stepDraft)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit {
                        let title = stepDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        Task { if await model.changeStep(todo, operation: "add", title: title) { stepDraft = "" } }
                    }
                    .accessibilityLabel("새 단계 제목")
            }
        }
    }

    private func notes(_ todo: AppTodo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("메모").font(.system(size: 12, weight: .semibold))
            ForEach(todo.notes ?? []) { note in
                NoteRow(model: model, todo: todo, note: note)
            }
            TextField("메모 추가", text: $noteDraft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onSubmit {
                    let value = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    Task { if await model.changeNote(todo, operation: "append", text: value) { noteDraft = "" } }
                }
                .accessibilityLabel("새 메모")
        }
    }
}

private struct StepRow: View {
    @ObservedObject var model: AppModel
    let todo: AppTodo
    let step: AppStep
    @State private var draft = ""
    @FocusState private var editing: Bool
    @State private var editingRevision: Int64?

    var body: some View {
        HStack(spacing: 6) {
            Button { Task { await model.changeStep(todo, operation: "check", id: step.id, done: !step.isDone) } } label: {
                Image(systemName: step.isDone ? "checkmark.square.fill" : "square")
                    .frame(width: 22, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.isDone ? "단계 완료 취소: \(step.title)" : "단계 완료: \(step.title)")
            TextField("단계", text: $draft)
                .focused($editing)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onSubmit {
                    let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty && title != step.title {
                        var edited = todo
                        edited.revision = editingRevision ?? todo.revision
                        Task { await model.changeStep(edited, operation: "edit", id: step.id, title: title) }
                    }
                }
            Menu {
                Button("위로") { reorder(by: -1) }
                    .disabled(todo.steps?.first?.id == step.id)
                Button("아래로") { reorder(by: 1) }
                    .disabled(todo.steps?.last?.id == step.id)
                Button("삭제", role: .destructive) { Task { await model.changeStep(todo, operation: "delete", id: step.id) } }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 25) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("단계 메뉴: \(step.title)")
        }
        .onAppear { draft = step.title }
        .onChange(of: step.title) { old, value in if draft == old { draft = value } }
        .onChange(of: editing) { _, focused in editingRevision = focused ? todo.revision : nil }
    }

    private func reorder(by delta: Int) {
        var ids = (todo.steps ?? []).map(\.id)
        guard let index = ids.firstIndex(of: step.id), ids.indices.contains(index + delta) else { return }
        ids.swapAt(index, index + delta)
        Task { await model.changeStep(todo, operation: "reorder", ids: ids) }
    }
}

private struct NoteRow: View {
    @ObservedObject var model: AppModel
    let todo: AppTodo
    let note: AppNote
    @State private var editing = false
    @State private var draft = ""
    @State private var editingRevision: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(note.authorId == "owner" ? "나" : note.authorId.replacingOccurrences(of: "integration:", with: ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("수정") { draft = note.text; editingRevision = todo.revision; editing = true }
                    Button("삭제", role: .destructive) { Task { await model.changeNote(todo, operation: "delete", id: note.id) } }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("메모 메뉴")
            }
            if editing {
                TextField("메모", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            var edited = todo
                            edited.revision = editingRevision ?? todo.revision
                            Task { if await model.changeNote(edited, operation: "edit", id: note.id, text: text) { editing = false } }
                        }
                    }
            } else { Text(note.text).font(.system(size: 12)).textSelection(.enabled) }
        }
        .padding(.vertical, 3)
        .onChange(of: model.recoveredMutation) { _, recovered in
            guard let recovered, recovered.path == "/v1/owner/todos/\(todo.id)/notes",
                  let body = try? recovered.object, body["operation"] as? String == "edit",
                  body["id"] as? String == note.id, body["text"] as? String == draft else { return }
            editing = false
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    let id: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.screen = .detail(id) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("상세로 돌아가기")
                Text("변경 이력").font(.system(size: 15, weight: .semibold))
                Spacer()
            }.padding(14)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.history) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.operationLabel).font(.system(size: 12, weight: .medium))
                            Text("\(event.actorId) · \(event.reason)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 16)
            }
        }
    }
}

struct TrashView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.screen = .list } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("목록으로 돌아가기")
                Text("휴지통").font(.system(size: 15, weight: .semibold))
                Spacer()
            }.padding(14)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.trashedTodos.isEmpty {
                        Text("휴지통이 비어 있어요").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(model.trashedTodos) { todo in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(todo.title).font(.system(size: 12)).lineLimit(2)
                                Text(model.projectName(for: todo.scope)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("복원") { Task { await model.restoreTodo(todo) } }.font(.system(size: 11))
                        }
                    }
                }.padding(.horizontal, 16)
            }
        }
    }
}

import AppKit
import Foundation
import SwiftUI

enum AppScreen: Equatable {
    case list
    case detail(String)
    case history(String)
    case trash
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var todos: [AppTodo] = []
    @Published var projects: [AppProject] = []
    @Published var proposals: [AppProposal] = []
    @Published var integrations: [AppIntegration] = []
    @Published var selectedTodo: AppTodo?
    @Published var history: [AppEvent] = []
    @Published var projectFolders: [String: [String]] = [:]
    @Published var alerts: [AppEvent] = []
    @Published var serviceAvailable = false
    @Published var isMutating = false
    @Published var awaitingConfirmation = false
    @Published var recoveredMutation: PendingMutation?
    @Published var errorMessage: String?
    @Published var screen: AppScreen = .list
    @Published var bubbleVisible = true
    @Published var requestComposer = false
    @Published var retainedCompleted: Set<String> = []
    @Published var listScrollAnchor: String?
    @Published var maximumPanelHeight: CGFloat = 780
    @Published var scopeFilter: String
    @Published var petPack: PetPack
    @Published var quietMode: Bool {
        didSet { AppPaths.preferences.set(quietMode, forKey: "cofoco.quietMode") }
    }

    private let api = AppAPI()
    let notifications = LocalNotifications()
    private var pollTask: Task<Void, Never>?
    private var scannedCursor: Int64
    private var seededCursor: Bool
    private var refreshing = false
    private var pendingMutation: PendingMutation?
    private var recoveryBlocked = false
    var requestServiceStart: (() -> Void)?

    init() {
        scopeFilter = AppPaths.preferences.string(forKey: "cofoco.scopeFilter") ?? "all"
        quietMode = AppPaths.preferences.bool(forKey: "cofoco.quietMode")
        petPack = PetPack.load()
        let inbox = EventInbox.load()
        seededCursor = inbox != nil
        scannedCursor = inbox?.cursor ?? 0
        alerts = inbox?.alerts ?? []
        do { pendingMutation = try PendingMutation.load(); awaitingConfirmation = pendingMutation != nil }
        catch { recoveryBlocked = true; errorMessage = "미확인 요청을 읽지 못했어요. 저장소를 확인해 주세요." }
    }

    var activeTodos: [AppTodo] {
        todos.filter { $0.deletedAt == nil && ($0.status != .done || retainedCompleted.contains($0.id)) && matchesFilter($0) }
    }

    var completedTodos: [AppTodo] {
        todos.filter { $0.deletedAt == nil && $0.status == .done && !retainedCompleted.contains($0.id) && matchesFilter($0) }
    }

    var trashedTodos: [AppTodo] { todos.filter { $0.deletedAt != nil } }
    var pendingProposals: [AppProposal] { proposals.filter { $0.state == "pending" } }
    var currentAlert: AppEvent? { quietMode ? nil : alerts.first }
    var hasChangeBubble: Bool { !pendingProposals.isEmpty || currentAlert != nil }
    var changeBubbleHeight: CGFloat { !pendingProposals.isEmpty ? 200 : 100 }
    var panelHeight: CGFloat {
        bubbleVisible ? min(maximumPanelHeight, 545 + (hasChangeBubble ? changeBubbleHeight + 8 : 0)) : 132
    }
    var mainBubbleHeight: CGFloat {
        panelHeight - 140 - (hasChangeBubble ? changeBubbleHeight + 8 : 0)
    }

    var selectedScopeName: String {
        if scopeFilter == "all" { return "Todo" }
        if scopeFilter == "personal" { return "내 할 일" }
        let id = String(scopeFilter.dropFirst("project:".count))
        return projects.first(where: { $0.id == id })?.name ?? "Todo"
    }

    var petPose: PetPose {
        if !bubbleVisible { return .resting }
        if !quietMode && (!pendingProposals.isEmpty || !alerts.isEmpty) { return .noticed }
        if case .detail(let id) = screen, let todo = selectedTodo, todo.id == id,
           todo.status == .in_progress { return .working }
        if screen == .list && activeTodos.contains(where: { $0.status == .in_progress }) { return .working }
        return .idle
    }

    func projectName(for scope: AppScope) -> String {
        switch scope {
        case .personal: "내 할 일"
        case .project(let id): projects.first(where: { $0.id == id })?.name ?? "프로젝트"
        }
    }

    func projectMark(for scope: AppScope) -> String {
        switch scope {
        case .personal: "P"
        case .project: String(projectName(for: scope).first ?? "·")
        }
    }

    func projectColor(for scope: AppScope) -> Color {
        guard case .project(let id) = scope else { return .secondary }
        let palette: [Color] = [.teal, .orange, .indigo, .pink, .green, .purple, .brown]
        let hash = id.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return palette[Int(hash % UInt64(palette.count))]
    }

    func setScope(_ value: String) {
        retainedCompleted.removeAll()
        listScrollAnchor = nil
        scopeFilter = value
        AppPaths.preferences.set(value, forKey: "cofoco.scopeFilter")
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            if let pendingMutation, !isMutating {
                struct Recovered: Decodable { let outcome: String }
                do {
                    let result: Recovered = try await api.request(pendingMutation.method, pendingMutation.path, body: pendingMutation.object)
                    try PendingMutation.clear()
                    self.pendingMutation = nil
                    awaitingConfirmation = false
                    recoveredMutation = pendingMutation
                    errorMessage = result.outcome == "stale" ? "제안이 오래되어 적용하지 않았어요." : nil
                } catch AppAPIError.rejected(let code, let message) {
                    // A definitive service rejection can be reconciled manually;
                    // transport failures retain the same request for the next poll.
                    try PendingMutation.clear()
                    self.pendingMutation = nil
                    awaitingConfirmation = false
                    errorMessage = AppAPIError.rejected(code, message).localizedDescription
                }
            }
            // Capture the cursor BEFORE the snapshot. A mutation during the
            // snapshot is then replayed, rather than skipped on first launch.
            if !seededCursor {
                let baseline: EventsEnvelope = try await api.request("GET", "/v1/owner/events?after=0")
                scannedCursor = baseline.latestCursor ?? 0
                seededCursor = true
            }
            let projects: ProjectsEnvelope = try await api.request("GET", "/v1/owner/projects")
            var allTodos: [AppTodo] = []
            var offset = 0
            while true {
                let page: TodosEnvelope = try await api.request("GET", "/v1/owner/todos?include_deleted=true&limit=200&offset=\(offset)")
                allTodos.append(contentsOf: page.todos)
                if page.todos.count < 200 { break }
                offset += page.todos.count
            }
            var allProposals: [AppProposal] = []
            var proposalOffset = 0
            while true {
                let page: ProposalsEnvelope = try await api.request("GET", "/v1/owner/proposals?state=pending&limit=200&offset=\(proposalOffset)")
                allProposals.append(contentsOf: page.proposals)
                if page.proposals.count < 200 { break }
                proposalOffset += page.proposals.count
            }
            let integrations: IntegrationsEnvelope = try await api.request("GET", "/v1/owner/integrations")
            let events: EventsEnvelope = try await api.request("GET", "/v1/owner/events?after=\(scannedCursor)")
            self.projects = projects.projects
            self.todos = allTodos
            self.proposals = allProposals
            self.integrations = integrations.integrations
            serviceAvailable = true
            if errorMessage == AppAPIError.serviceUnavailable.localizedDescription ||
                errorMessage == AppAPIError.missingOwnerCredential.localizedDescription ||
                errorMessage?.hasPrefix("서비스 시작 오류:") == true { errorMessage = nil }
            for event in events.events where event.feedback == "todo" && event.actorId != "owner" {
                if !alerts.contains(where: { $0.cursor == event.cursor }) { alerts.append(event) }
            }
            if let last = events.events.last { scannedCursor = last.cursor }
            saveAlertQueue()
            await notifications.deliver(events: events.events, proposals: allProposals,
                                        todos: allTodos, quiet: quietMode)
            if case .detail(let id) = screen { await loadTodo(id) }
            if case .history(let id) = screen { await loadHistory(id) }
            if case .settings = screen { await loadFolders() }
        } catch {
            serviceAvailable = false
            if errorMessage == nil { errorMessage = error.localizedDescription }
            requestServiceStart?()
        }
    }

    private func matchesFilter(_ todo: AppTodo) -> Bool {
        scopeFilter == "all" || todo.scope.query == scopeFilter
    }

    func acknowledgeAlert() {
        guard !alerts.isEmpty else { return }
        alerts.removeFirst()
        saveAlertQueue()
    }

    private func saveAlertQueue() {
        do { try EventInbox(cursor: scannedCursor, alerts: alerts).save() }
        catch { errorMessage = "알림 대기를 저장하지 못했어요: \(error.localizedDescription)" }
    }

    func showDetail(_ id: String) async {
        screen = .detail(id)
        await loadTodo(id)
    }

    func loadTodo(_ id: String) async {
        do {
            let response: TodoEnvelope = try await api.request("GET", "/v1/owner/todos/\(id)")
            selectedTodo = response.todo
        } catch { errorMessage = error.localizedDescription }
    }

    func loadHistory(_ id: String) async {
        do {
            var allEvents: [AppEvent] = []
            var cursor: Int64 = 0
            while true {
                let response: EventsEnvelope = try await api.request("GET", "/v1/owner/todos/\(id)/history?after=\(cursor)")
                allEvents.append(contentsOf: response.events)
                if response.events.count < 100 { break }
                guard let last = response.events.last else { break }
                cursor = last.cursor
            }
            history = allEvents
        } catch { errorMessage = error.localizedDescription }
    }

    func loadFolders() async {
        for project in projects {
            do {
                let response: FoldersEnvelope = try await api.request("GET", "/v1/owner/projects/\(project.id)/folders")
                projectFolders[project.id] = response.folders
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func perform<T: Decodable>(_ method: String, _ path: String, _ body: [String: Any]) async -> T? {
        guard serviceAvailable else { errorMessage = AppAPIError.serviceUnavailable.localizedDescription; return nil }
        guard !isMutating else { return nil }
        guard !recoveryBlocked else { return nil }
        guard pendingMutation == nil else {
            errorMessage = "이전 요청의 저장 여부를 확인하고 있어요. 잠시 후 다시 시도해 주세요."
            return nil
        }
        isMutating = true
        defer { isMutating = false }
        do {
            let pending = try PendingMutation(method: method, path: path, body: body)
            try pending.save()
            pendingMutation = pending
            awaitingConfirmation = true
            let response: T = try await api.request(method, path, body: body)
            try PendingMutation.clear()
            pendingMutation = nil
            awaitingConfirmation = false
            errorMessage = nil
            await refresh()
            return response
        } catch {
            if case AppAPIError.rejected = error {
                try? PendingMutation.clear()
                pendingMutation = nil
                awaitingConfirmation = false
            }
            errorMessage = error.localizedDescription
            await refresh()
            return nil
        }
    }

    private func payload(_ reason: String, revision: Int64? = nil) -> [String: Any] {
        var body: [String: Any] = ["idempotency_key": UUID().uuidString, "reason": reason]
        if let revision { body["expected_revision"] = revision }
        return body
    }

    @discardableResult func addTodo(_ title: String, scope: AppScope) async -> Bool {
        var body = payload("사용자가 앱에서 할 일을 추가함")
        body["title"] = title; body["scope"] = scope.object
        let result: MutationResponse? = await perform("POST", "/v1/owner/todos", body)
        return result != nil
    }

    func updateTodo(_ todo: AppTodo, title: String? = nil, scope: AppScope? = nil,
                    status: AppTodoStatus? = nil) async {
        var body = payload("사용자가 앱에서 할 일을 수정함", revision: todo.revision)
        if let title { body["title"] = title }
        if let scope { body["scope"] = scope.object }
        if let status { body["status"] = status.rawValue }
        let _: MutationResponse? = await perform("PATCH", "/v1/owner/todos/\(todo.id)", body)
    }

    func deleteTodo(_ todo: AppTodo) async {
        let result: MutationResponse? = await perform("DELETE", "/v1/owner/todos/\(todo.id)",
                                                       payload("사용자가 휴지통으로 이동함", revision: todo.revision))
        if result != nil { screen = .list }
    }

    func restoreTodo(_ todo: AppTodo) async {
        let _: MutationResponse? = await perform("POST", "/v1/owner/todos/\(todo.id)/restore",
                                                  payload("사용자가 휴지통에서 복원함", revision: todo.revision))
    }

    @discardableResult func changeStep(_ todo: AppTodo, operation: String, id: String? = nil,
                    title: String? = nil, done: Bool? = nil, ids: [String]? = nil) async -> Bool {
        var body = payload("사용자가 단계 수정", revision: todo.revision)
        body["operation"] = operation
        if let id { body["id"] = id }
        if let title { body["title"] = title }
        if let done { body["done"] = done }
        if let ids { body["ids"] = ids }
        let result: MutationResponse? = await perform("POST", "/v1/owner/todos/\(todo.id)/steps", body)
        return result != nil
    }

    @discardableResult func changeNote(_ todo: AppTodo, operation: String, id: String? = nil, text: String? = nil) async -> Bool {
        var body = payload("사용자가 메모 수정", revision: todo.revision)
        body["operation"] = operation
        if let id { body["id"] = id }
        if let text { body["text"] = text }
        let result: MutationResponse? = await perform("POST", "/v1/owner/todos/\(todo.id)/notes", body)
        return result != nil
    }

    func review(_ proposal: AppProposal, accept: Bool) async {
        var body = payload(accept ? "사용자가 변경 제안을 승인함" : "사용자가 변경 제안을 거절함")
        body["accept"] = accept
        let result: MutationResponse? = await perform("POST", "/v1/owner/proposals/\(proposal.id)/review", body)
        if result?.outcome == "stale" { errorMessage = "이 할 일이 제안 뒤에 변경됐어요. 새 제안을 요청해 주세요." }
    }

    @discardableResult func createProject(_ name: String) async -> Bool {
        var body: [String: Any] = ["idempotency_key": UUID().uuidString]
        body["name"] = name
        let result: ProjectMutationResponse? = await perform("POST", "/v1/owner/projects", body)
        return result != nil
    }

    func renameProject(_ project: AppProject, name: String) async {
        let body: [String: Any] = ["idempotency_key": UUID().uuidString, "expected_revision": project.revision, "name": name]
        let _: ProjectMutationResponse? = await perform("PATCH", "/v1/owner/projects/\(project.id)", body)
    }

    func changeFolder(_ project: AppProject, path: String, add: Bool) async {
        let body: [String: Any] = ["idempotency_key": UUID().uuidString, "expected_revision": project.revision, "path": path]
        let _: ProjectMutationResponse? = await perform(add ? "POST" : "DELETE", "/v1/owner/projects/\(project.id)/folders", body)
    }

    func grantIntegration(_ id: String, scopes: [String]) async {
        let body: [String: Any] = ["id": id, "scopes": scopes, "idempotency_key": UUID().uuidString]
        let _: IntegrationMutationResponse? = await perform("POST", "/v1/owner/integrations", body)
    }

    func revokeIntegration(_ id: String) async {
        let body: [String: Any] = ["idempotency_key": UUID().uuidString]
        let _: IntegrationMutationResponse? = await perform("DELETE", "/v1/owner/integrations/\(id)", body)
    }

    func importPetFrames(_ urls: [URL], pose: PetPose) {
        do {
            let next = try petPack.importing(urls, for: pose)
            try next.save()
            petPack = next
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

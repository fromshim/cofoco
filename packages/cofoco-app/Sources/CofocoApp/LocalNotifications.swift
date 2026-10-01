import Foundation
import UserNotifications

@MainActor
final class LocalNotifications: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status: String?
    private var attempted: Set<String>
    private let center = UNUserNotificationCenter.current()

    init() {
        enabled = AppPaths.preferences.bool(forKey: "cofoco.osNotifications")
        attempted = Set(AppPaths.preferences.stringArray(forKey: "cofoco.notificationAttempts") ?? [])
    }

    func setEnabled(_ requested: Bool) async {
        guard requested else {
            enabled = false
            AppPaths.preferences.set(false, forKey: "cofoco.osNotifications")
            return
        }
        do {
            enabled = try await center.requestAuthorization(options: [.alert])
            status = enabled ? nil : "macOS에서 알림이 허용되지 않았어요. 앱 안의 기록은 계속 남습니다."
            AppPaths.preferences.set(enabled, forKey: "cofoco.osNotifications")
        } catch { enabled = false; status = error.localizedDescription }
    }

    func deliver(events: [AppEvent], proposals: [AppProposal], todos: [AppTodo], quiet: Bool) async {
        guard enabled && !quiet else { return }
        for event in events where event.feedback == "todo" && event.actorId != "owner" {
            await send(id: "event-\(event.cursor)", title: "할 일이 바뀌었어요",
                       body: todos.first(where: { $0.id == event.aggregateId })?.title ?? event.reason)
        }
        for proposal in proposals where proposal.state == "pending" {
            await send(id: "proposal-\(proposal.id)", title: "확인할 변경 제안", body: proposal.reason)
        }
    }

    private func send(id: String, title: String, body: String) async {
        guard attempted.insert(id).inserted else { return }
        // Record before dispatch: OS delivery is best effort, while the durable
        // in-app queue remains authoritative and never depends on OS delivery.
        AppPaths.preferences.set(attempted.sorted(), forKey: "cofoco.notificationAttempts")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
        catch { status = "macOS 알림을 보내지 못했어요. 앱에서 확인해 주세요." }
    }
}

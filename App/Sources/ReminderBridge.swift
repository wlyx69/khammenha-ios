import Foundation
import WebKit
import UserNotifications

/// Receives `window.webkit.messageHandlers.native.postMessage({...})` from the page
/// and schedules local daily reminders. No server, no push entitlement needed.
final class ReminderBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "native"
    private static let idPrefix = "daily-"
    private static let daysAhead = 14
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "reminders":
            let enabled = body["enabled"] as? Bool ?? false
            let time = body["time"] as? String ?? "20:00"
            let skipToday = body["skipToday"] as? Bool ?? false
            if enabled {
                requestPermission { [weak self] granted in
                    self?.reply(["type": "reminderPermission", "granted": granted])
                    if granted { self?.plan(time: time, skipToday: skipToday) } else { self?.cancelAll() }
                }
            } else {
                cancelAll()
            }
        default:
            break
        }
    }

    // MARK: - Scheduling

    private func requestPermission(_ completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in completion(granted) }
            default:
                completion(false)
            }
        }
    }

    /// One non-repeating notification per day for the next `daysAhead` days, so today's can be skipped when the word is solved.
    private func plan(time: String, skipToday: Bool) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.count > 0 ? min(max(parts[0], 0), 23) : 20
        let minute = parts.count > 1 ? min(max(parts[1], 0), 59) : 0

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers())

        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for offset in 0..<Self.daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            guard let fireDate = calendar.date(from: comps), fireDate > now else { continue }
            if offset == 0 && skipToday { continue }

            let content = UNMutableNotificationContent()
            content.title = "خمّنها"
            content.body = offset == 0 ? "كلمة اليوم بانتظارك، لا تكسر الستريك 🔥" : "كلمة جديدة ولغز جديد بانتظارك 💡"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: Self.idPrefix + formatter.string(from: day), content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pendingIdentifiers())
    }

    private func pendingIdentifiers() -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (-1...Self.daysAhead).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: Date()).map { Self.idPrefix + formatter.string(from: $0) }
        }
    }

    private func reply(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.onNativeMessage && window.onNativeMessage(\(json))", completionHandler: nil)
        }
    }
}

import EventKit
import EventKitUI
import Flutter
import Foundation
import UIKit

/// Presents the system new-event editor pre-filled from a club event, so the
/// runner confirms the save themselves and the app never writes to a calendar
/// behind their back. Dart side: `lib/calendar_intent.dart` over
/// `run_app/calendar`.
///
/// The series arrives as an RFC 5545 RRULE value — the one representation both
/// platforms speak — and is mapped onto an `EKRecurrenceRule` here. Only the
/// parts `buildRrule` can emit are understood; anything else yields no rule
/// rather than a wrong one, because a recurrence the editor states differently
/// than the club page is worse than a single date.
@objc class CalendarBridge: NSObject, EKEventEditViewDelegate {
    @objc static let shared = CalendarBridge()

    private let store = EKEventStore()
    private var channel: FlutterMethodChannel?

    @objc func attach(binaryMessenger: FlutterBinaryMessenger) {
        let calendar = FlutterMethodChannel(
            name: "run_app/calendar",
            binaryMessenger: binaryMessenger
        )
        // Strong capture: `shared` is a permanent singleton, so there is no
        // cycle to break — and a weak self going nil would leave the Dart
        // future unanswered forever instead of failing.
        calendar.setMethodCallHandler { call, result in
            guard call.method == "addEvent" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.requestAccessThenPresent(call.arguments as? [String: Any] ?? [:], result: result)
        }
        channel = calendar
    }

    private func requestAccessThenPresent(
        _ args: [String: Any],
        result: @escaping FlutterResult
    ) {
        let granted: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard ok else {
                    result(false)
                    return
                }
                result(self.present(args))
            }
        }
        if #available(iOS 17.0, *) {
            store.requestWriteOnlyAccessToEvents { ok, _ in granted(ok) }
        } else {
            store.requestAccess(to: .event) { ok, _ in granted(ok) }
        }
    }

    private func present(_ args: [String: Any]) -> Bool {
        guard let title = args["title"] as? String,
              let startMs = args["startMs"] as? NSNumber,
              let host = topViewController()
        else { return false }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = Date(timeIntervalSince1970: startMs.doubleValue / 1000)
        if let endMs = args["endMs"] as? NSNumber {
            event.endDate = Date(timeIntervalSince1970: endMs.doubleValue / 1000)
        } else {
            event.endDate = event.startDate
        }
        event.notes = args["description"] as? String
        event.location = args["location"] as? String
        if let link = args["url"] as? String { event.url = URL(string: link) }
        event.calendar = store.defaultCalendarForNewEvents
        if let rrule = args["rrule"] as? String,
           let rule = Self.recurrenceRule(from: rrule) {
            event.recurrenceRules = [rule]
        }

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = self
        host.present(editor, animated: true)
        return true
    }

    func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        controller.dismiss(animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - RRULE -> EKRecurrenceRule

    static func recurrenceRule(from rrule: String) -> EKRecurrenceRule? {
        var fields: [String: String] = [:]
        for part in rrule.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            fields[String(pair[0]).uppercased()] = String(pair[1]).uppercased()
        }

        let frequency: EKRecurrenceFrequency
        switch fields["FREQ"] {
        case "WEEKLY": frequency = .weekly
        case "MONTHLY": frequency = .monthly
        default: return nil
        }

        let interval = Int(fields["INTERVAL"] ?? "1") ?? 1
        guard interval >= 1 else { return nil }

        var end: EKRecurrenceEnd?
        if let count = fields["COUNT"] {
            guard let n = Int(count), n >= 1 else { return nil }
            end = EKRecurrenceEnd(occurrenceCount: n)
        } else if let until = fields["UNTIL"] {
            guard let date = utcStamp(until) else { return nil }
            end = EKRecurrenceEnd(end: date)
        }

        var daysOfTheWeek: [EKRecurrenceDayOfWeek]?
        var daysOfTheMonth: [NSNumber]?
        if frequency == .monthly {
            guard let day = Int(fields["BYMONTHDAY"] ?? ""), day >= 1, day <= 31 else { return nil }
            daysOfTheMonth = [NSNumber(value: day)]
        } else if let byday = fields["BYDAY"] {
            var days: [EKRecurrenceDayOfWeek] = []
            for code in byday.split(separator: ",") {
                guard let weekday = Self.weekdays[String(code)] else { return nil }
                days.append(EKRecurrenceDayOfWeek(weekday))
            }
            guard !days.isEmpty else { return nil }
            daysOfTheWeek = days
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfTheWeek,
            daysOfTheMonth: daysOfTheMonth,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static let weekdays: [String: EKWeekday] = [
        "MO": .monday, "TU": .tuesday, "WE": .wednesday, "TH": .thursday,
        "FR": .friday, "SA": .saturday, "SU": .sunday
    ]

    private static func utcStamp(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: value)
    }
}

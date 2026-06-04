import EventKit
import Foundation
import Logging

// MARK: - Sendable result types

public struct CalendarEvent: Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarTitle: String
    public let calendarID: String
    public let notes: String?
    public let isAllDay: Bool
    public let location: String?
}

public struct ReminderItem: Sendable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let dueDate: Date?
    public let notes: String?
    public let listTitle: String
    public let listID: String
    public let priority: Int
}

public struct EKCalendarInfo: Sendable {
    public let id: String
    public let title: String
    public let type: String
    public let color: String  // hex
}

public actor EventKitActor {
    private let store = EKEventStore()
    private let logger = Logger(label: "macctl.eventkit")
    public init() {}

    // MARK: - Permission

    public func requestCalendarAccess() async throws {
        if #available(macOS 14, *) {
            try await store.requestFullAccessToEvents()
        } else {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let e = error { cont.resume(throwing: e) }
                    else if !granted { cont.resume(throwing: EventKitError.accessDenied("Calendar")) }
                    else { cont.resume() }
                }
            }
        }
    }

    public func requestRemindersAccess() async throws {
        if #available(macOS 14, *) {
            try await store.requestFullAccessToReminders()
        } else {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .reminder) { granted, error in
                    if let e = error { cont.resume(throwing: e) }
                    else if !granted { cont.resume(throwing: EventKitError.accessDenied("Reminders")) }
                    else { cont.resume() }
                }
            }
        }
    }

    // MARK: - Calendars

    public func listCalendars() -> [EKCalendarInfo] {
        store.calendars(for: .event).map { cal in
            EKCalendarInfo(
                id:    cal.calendarIdentifier,
                title: cal.title,
                type:  calendarType(cal.type),
                color: cal.cgColor.map { colorToHex($0) } ?? "#000000"
            )
        }
    }

    // MARK: - Events

    public func fetchEvents(
        from start: Date,
        to end: Date,
        calendarIDs: [String]? = nil
    ) -> [CalendarEvent] {
        let cals = calendarIDs.map { ids in
            store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: predicate).map { eventToStruct($0) }
    }

    public func createEvent(
        title: String,
        start: Date,
        end: Date,
        calendarID: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false,
        location: String? = nil
    ) throws -> CalendarEvent {
        let event = EKEvent(eventStore: store)
        event.title     = title
        event.startDate = start
        event.endDate   = end
        event.isAllDay  = isAllDay
        event.notes     = notes
        event.location  = location
        if let id = calendarID {
            event.calendar = store.calendar(withIdentifier: id)
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        try store.save(event, span: .thisEvent)
        return eventToStruct(event)
    }

    public func deleteEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) else {
            throw EventKitError.notFound(id)
        }
        try store.remove(event, span: .thisEvent)
    }

    // MARK: - Reminders

    public func fetchReminders(
        listIDs: [String]? = nil,
        completed: Bool? = nil
    ) async throws -> [ReminderItem] {
        let lists = listIDs.map { ids in
            store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate = store.predicateForReminders(in: lists)
        // EKReminder is not Sendable — bridge via box, process immediately after resume
        let box = RemindersBox()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.fetchReminders(matching: predicate) { reminders in
                box.items = reminders ?? []
                cont.resume()
            }
        }
        let raw = box.items
        return raw
            .filter { r in guard let c = completed else { return true }; return r.isCompleted == c }
            .map { reminderToStruct($0) }
    }

    public func createReminder(
        title: String,
        dueDate: Date? = nil,
        listID: String? = nil,
        notes: String? = nil,
        priority: Int = 0
    ) throws -> ReminderItem {
        let reminder = EKReminder(eventStore: store)
        reminder.title    = title
        reminder.notes    = notes
        reminder.priority = priority
        if let d = dueDate {
            reminder.dueDateComponents = Calendar.current
                .dateComponents([.year, .month, .day, .hour, .minute], from: d)
        }
        if let id = listID {
            reminder.calendar = store.calendar(withIdentifier: id)
        } else {
            // Use default if available, otherwise use first Reminders calendar
            reminder.calendar = store.defaultCalendarForNewReminders()
                ?? store.calendars(for: .reminder).first
        }
        guard reminder.calendar != nil else {
            throw EventKitError.accessDenied("No Reminders calendar available — open Reminders.app first")
        }
        try store.save(reminder, commit: true)
        return reminderToStruct(reminder)
    }

    public func completeReminder(id: String) throws -> ReminderItem {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw EventKitError.notFound(id)
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return reminderToStruct(reminder)
    }

    public func listReminderLists() -> [EKCalendarInfo] {
        store.calendars(for: .reminder).map { cal in
            EKCalendarInfo(
                id:    cal.calendarIdentifier,
                title: cal.title,
                type:  calendarType(cal.type),
                color: cal.cgColor.map { colorToHex($0) } ?? "#000000"
            )
        }
    }

    // MARK: - Private helpers

    private func eventToStruct(_ e: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id:            e.eventIdentifier ?? "",
            title:         e.title ?? "",
            startDate:     e.startDate,
            endDate:       e.endDate,
            calendarTitle: e.calendar?.title ?? "",
            calendarID:    e.calendar?.calendarIdentifier ?? "",
            notes:         e.notes,
            isAllDay:      e.isAllDay,
            location:      e.location
        )
    }

    private func reminderToStruct(_ r: EKReminder) -> ReminderItem {
        let dueDate = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(
            id:          r.calendarItemIdentifier,
            title:       r.title ?? "",
            isCompleted: r.isCompleted,
            dueDate:     dueDate,
            notes:       r.notes,
            listTitle:   r.calendar?.title ?? "",
            listID:      r.calendar?.calendarIdentifier ?? "",
            priority:    r.priority
        )
    }

    private func calendarType(_ type: EKCalendarType) -> String {
        switch type {
        case .local:        return "local"
        case .calDAV:       return "calDAV"
        case .exchange:     return "exchange"
        case .subscription: return "subscription"
        case .birthday:     return "birthday"
        @unknown default:   return "unknown"
        }
    }

    private func colorToHex(_ color: CGColor) -> String {
        guard let comps = color.components, comps.count >= 3 else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(comps[0]*255), Int(comps[1]*255), Int(comps[2]*255))
    }
}

private final class RemindersBox: @unchecked Sendable {
    var items: [EKReminder] = []
}

public enum EventKitError: Error, Sendable {
    case accessDenied(String)
    case notFound(String)
    case saveFailed(String)
}

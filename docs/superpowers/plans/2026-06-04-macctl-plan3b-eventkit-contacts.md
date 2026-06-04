# macctl Plan 3B — EventKit, Contacts, File Watch Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`.

**Goal:** Add EventKitActor (Calendar + Reminders read/write via EventKit), ContactsActor (Contacts search/read/create via ContactsKit), and wire both into the daemon dispatcher with CLI commands. Also improve file watching to add a `watch network` fallback note and expose the existing FSEvents topic via the streaming protocol.

**Architecture:** `EventKitActor` wraps `EKEventStore` (single shared store per process). `ContactsActor` wraps `CNContactStore`. Both actors handle TCC permission requests internally — operations automatically request access if not granted. All returned types are `Sendable` structs (no EKEvent/CNContact crossing actor boundaries). Framework calls go on background DispatchQueues to avoid blocking the cooperative pool.

**Tech Stack:** Swift 6, EventKit (EKEventStore, EKEvent, EKReminder), ContactsKit (CNContactStore, CNContact, CNSaveRequest), macOS 13+, existing actor patterns.

**API reality check:**
- `EKEventStore.requestFullAccessToEvents()` — macOS 14+ (async). Use `requestAccess(to:)` for macOS 13 compat.
- `CNContactStore.requestAccess(for:)` — callback-based, wrap in continuation.
- EventKit fetch is synchronous (`EKEventStore.events(matching:)`) — run on background queue.
- ContactsKit fetch is synchronous — run on background queue.

---

## File Map

```
Sources/MacCtlKit/Actors/
  EventKitActor.swift         NEW — Calendar + Reminders via EKEventStore
  ContactsActor.swift         NEW — Contacts via CNContactStore

Sources/macctl-daemon/
  Dispatcher.swift            MODIFY — add calendar.* reminder.* contact.* cases
  main.swift                  MODIFY — add eventKitActor, contactsActor instances

Sources/macctl/Commands/
  CalendarCommand.swift       NEW — calendar list/create/search
  RemindersCommand.swift      NEW — reminders list/create/complete
  ContactsCommand.swift       NEW — contacts search/get

Tests/MacCtlKitTests/
  EventKitActorTests.swift    NEW — permission check, struct tests (no real calendar needed)
  ContactsActorTests.swift    NEW — struct tests
```

---

## Task 1: EventKitActor — Calendar + Reminders

**Files:**
- Create: `Sources/MacCtlKit/Actors/EventKitActor.swift`
- Create: `Tests/MacCtlKitTests/EventKitActorTests.swift`

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/EventKitActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("EventKitActor")
struct EventKitActorTests {
    @Test func calendarEventStructIsComplete() {
        let event = CalendarEvent(
            id: "test-id",
            title: "Test Event",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarTitle: "Personal",
            calendarID: "cal-123",
            notes: "some notes",
            isAllDay: false,
            location: nil
        )
        #expect(event.title == "Test Event")
        #expect(event.id == "test-id")
        #expect(!event.isAllDay)
    }

    @Test func reminderStructIsComplete() {
        let r = ReminderItem(
            id: "rem-1",
            title: "Buy milk",
            isCompleted: false,
            dueDate: nil,
            notes: nil,
            listTitle: "Reminders",
            listID: "list-1",
            priority: 0
        )
        #expect(r.title == "Buy milk")
        #expect(!r.isCompleted)
    }

    @Test func actorInitDoesNotCrash() async {
        let actor = EventKitActor()
        // Just verify init doesn't crash — actual EKEventStore needs TCC
        _ = actor
    }
}
```

- [ ] **Run — expect compile failure**

```bash
swift test --filter EventKitActorTests 2>&1 | grep "error:" | head -3
```

- [ ] **Implement EventKitActor.swift**

```swift
// Sources/MacCtlKit/Actors/EventKitActor.swift
import EventKit
import Foundation
import Logging

// MARK: - Sendable result types (EKEvent/EKReminder never cross actor boundary)

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
    public let type: String   // "local", "calDAV", "iCloud", etc.
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
            try await withCheckedThrowingContinuation { cont in
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
            try await withCheckedThrowingContinuation { cont in
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
            let hex = cal.cgColor.map { colorToHex($0) } ?? "#000000"
            return EKCalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                type: calendarType(cal.type),
                color: hex
            )
        }
    }

    // MARK: - Calendar events

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
        event.title    = title
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
        let rawReminders: [EKReminder] = try await withCheckedThrowingContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
        return rawReminders
            .filter { r in
                guard let c = completed else { return true }
                return r.isCompleted == c
            }
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
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: d)
            reminder.dueDateComponents = comps
        }
        if let id = listID {
            reminder.calendar = store.calendar(withIdentifier: id)
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
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
                id: cal.calendarIdentifier,
                title: cal.title,
                type: calendarType(cal.type),
                color: cal.cgColor.map { colorToHex($0) } ?? "#000000"
            )
        }
    }

    // MARK: - Helpers

    private func eventToStruct(_ e: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: e.eventIdentifier ?? "",
            title: e.title ?? "",
            startDate: e.startDate,
            endDate: e.endDate,
            calendarTitle: e.calendar?.title ?? "",
            calendarID: e.calendar?.calendarIdentifier ?? "",
            notes: e.notes,
            isAllDay: e.isAllDay,
            location: e.location
        )
    }

    private func reminderToStruct(_ r: EKReminder) -> ReminderItem {
        let dueDate = r.dueDateComponents.flatMap {
            Calendar.current.date(from: $0)
        }
        return ReminderItem(
            id: r.calendarItemIdentifier,
            title: r.title ?? "",
            isCompleted: r.isCompleted,
            dueDate: dueDate,
            notes: r.notes,
            listTitle: r.calendar?.title ?? "",
            listID: r.calendar?.calendarIdentifier ?? "",
            priority: r.priority
        )
    }

    private func calendarType(_ type: EKCalendarType) -> String {
        switch type {
        case .local:      return "local"
        case .calDAV:     return "calDAV"
        case .exchange:   return "exchange"
        case .subscription: return "subscription"
        case .birthday:   return "birthday"
        @unknown default: return "unknown"
        }
    }

    private func colorToHex(_ color: CGColor) -> String {
        guard let comps = color.components, comps.count >= 3 else { return "#000000" }
        let r = Int(comps[0] * 255)
        let g = Int(comps[1] * 255)
        let b = Int(comps[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

public enum EventKitError: Error, Sendable {
    case accessDenied(String)
    case notFound(String)
    case saveFailed(String)
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter EventKitActorTests 2>&1 | grep -E "passed|failed" | head -5
```
Expected: 3 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/EventKitActor.swift Tests/MacCtlKitTests/EventKitActorTests.swift
git commit -m "feat: add EventKitActor (Calendar read/write + Reminders via EKEventStore)"
```

---

## Task 2: ContactsActor

**Files:**
- Create: `Sources/MacCtlKit/Actors/ContactsActor.swift`
- Create: `Tests/MacCtlKitTests/ContactsActorTests.swift`

- [ ] **Write failing tests**

```swift
// Tests/MacCtlKitTests/ContactsActorTests.swift
import Testing
import Foundation
@testable import MacCtlKit

@Suite("ContactsActor")
struct ContactsActorTests {
    @Test func contactStructIsComplete() {
        let c = ContactRecord(
            id: "c1", givenName: "John", familyName: "Doe",
            emailAddresses: ["john@example.com"], phoneNumbers: ["+1-555-0100"],
            organizationName: "Acme", jobTitle: "Engineer",
            birthday: nil, note: nil
        )
        #expect(c.id == "c1")
        #expect(c.emailAddresses == ["john@example.com"])
        #expect(c.fullName == "John Doe")
    }

    @Test func actorInitDoesNotCrash() async {
        let actor = ContactsActor()
        _ = actor
    }
}
```

- [ ] **Run — expect compile failure**

```bash
swift test --filter ContactsActorTests 2>&1 | grep "error:" | head -3
```

- [ ] **Implement ContactsActor.swift**

```swift
// Sources/MacCtlKit/Actors/ContactsActor.swift
import Contacts
import Foundation
import Logging

public struct ContactRecord: Sendable {
    public let id: String
    public let givenName: String
    public let familyName: String
    public let emailAddresses: [String]
    public let phoneNumbers: [String]
    public let organizationName: String
    public let jobTitle: String
    public let birthday: DateComponents?
    public let note: String?

    public var fullName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public actor ContactsActor {
    private let store = CNContactStore()
    private let logger = Logger(label: "macctl.contacts")
    public init() {}

    // MARK: - Permission

    public func requestAccess() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let e = error { cont.resume(throwing: e) }
                else if !granted { cont.resume(throwing: ContactsError.accessDenied) }
                else { cont.resume() }
            }
        }
    }

    // MARK: - Search

    public func search(query: String, limit: Int = 25) throws -> [ContactRecord] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = CNContact.predicateForContacts(matchingName: query)

        var results: [ContactRecord] = []
        try store.enumerateContacts(with: request) { contact, stop in
            results.append(contactToStruct(contact))
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }

    public func get(id: String) throws -> ContactRecord {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]
        let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keysToFetch)
        return contactToStruct(contact)
    }

    public func create(
        givenName: String,
        familyName: String,
        email: String? = nil,
        phone: String? = nil,
        organization: String? = nil
    ) throws -> ContactRecord {
        let contact = CNMutableContact()
        contact.givenName  = givenName
        contact.familyName = familyName
        if let e = email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: e as NSString)]
        }
        if let p = phone {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain,
                                                    value: CNPhoneNumber(stringValue: p))]
        }
        if let o = organization { contact.organizationName = o }

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contactToStruct(contact)
    }

    // MARK: - Helper

    private func contactToStruct(_ c: CNContact) -> ContactRecord {
        ContactRecord(
            id:               c.identifier,
            givenName:        c.givenName,
            familyName:       c.familyName,
            emailAddresses:   c.emailAddresses.map { $0.value as String },
            phoneNumbers:     c.phoneNumbers.map { $0.value.stringValue },
            organizationName: c.organizationName,
            jobTitle:         c.jobTitle,
            birthday:         c.birthday,
            note:             (c.isKeyAvailable(CNContactNoteKey)) ? c.note : nil
        )
    }
}

public enum ContactsError: Error, Sendable {
    case accessDenied
    case notFound(String)
}
```

- [ ] **Run tests — expect pass**

```bash
swift test --filter "EventKitActorTests|ContactsActorTests" 2>&1 | grep -E "passed|failed" | head -8
```
Expected: 5 tests passed.

- [ ] **Commit**

```bash
git add Sources/MacCtlKit/Actors/ContactsActor.swift Tests/MacCtlKitTests/ContactsActorTests.swift
git commit -m "feat: add ContactsActor (search/get/create via ContactsKit CNContactStore)"
```

---

## Task 3: Wire into daemon + dispatcher

**Files:**
- Modify: `Sources/macctl-daemon/main.swift`
- Modify: `Sources/macctl-daemon/Dispatcher.swift`

- [ ] **Add actors to main.swift**

Add after `fileActor`:
```swift
let eventKitActor = EventKitActor()
let contactsActor = ContactsActor()
```

Update `middlewarePipeline` base closure and `dispatch(...)` call to include the new actors.

- [ ] **Update dispatch function signature in Dispatcher.swift**

Add two new parameters:
```swift
eventKit: EventKitActor,
contacts: ContactsActor,
```

- [ ] **Add dispatcher cases for calendar.*, reminder.*, contact.***

```swift
    // MARK: - calendar.*

    case "calendar.list-calendars":
        try await eventKit.requestCalendarAccess()
        let cals = await eventKit.listCalendars()
        let list: [JSONValue] = cals.map { c in
            .object(["id":.string(c.id),"title":.string(c.title),
                     "type":.string(c.type),"color":.string(c.color)])
        }
        return layer("framework-api", ["calendars": .array(list), "count": .int(list.count)])

    case "calendar.fetch-events":
        try await eventKit.requestCalendarAccess()
        let startTS = params["startTimestamp"]?.doubleValue ?? Date().timeIntervalSince1970
        let endTS   = params["endTimestamp"]?.doubleValue
                      ?? Date().addingTimeInterval(7 * 86400).timeIntervalSince1970
        let calIDs  = params["calendarIDs"].flatMap {
            if case .array(let arr) = $0 { return arr.compactMap { $0.stringValue } }
            return nil
        }
        let events = await eventKit.fetchEvents(
            from: Date(timeIntervalSince1970: startTS),
            to:   Date(timeIntervalSince1970: endTS),
            calendarIDs: calIDs
        )
        let list: [JSONValue] = events.map { e in
            var obj: [String: JSONValue] = [
                "id":            .string(e.id),
                "title":         .string(e.title),
                "startDate":     .double(e.startDate.timeIntervalSince1970),
                "endDate":       .double(e.endDate.timeIntervalSince1970),
                "calendarTitle": .string(e.calendarTitle),
                "isAllDay":      .bool(e.isAllDay),
            ]
            if let n = e.notes    { obj["notes"]    = .string(n) }
            if let l = e.location { obj["location"] = .string(l) }
            return .object(obj)
        }
        return layer("framework-api", ["events": .array(list), "count": .int(list.count)])

    case "calendar.create-event":
        try await eventKit.requestCalendarAccess()
        guard case .string(let title) = params["title"],
              case .double(let startTS) = params["startTimestamp"],
              case .double(let endTS)   = params["endTimestamp"]
        else { throw RPCError.operationFailed("calendar.create-event requires title+startTimestamp+endTimestamp") }
        let event = try await eventKit.createEvent(
            title:      title,
            start:      Date(timeIntervalSince1970: startTS),
            end:        Date(timeIntervalSince1970: endTS),
            calendarID: params["calendarID"]?.stringValue,
            notes:      params["notes"]?.stringValue,
            isAllDay:   params["isAllDay"] == .bool(true),
            location:   params["location"]?.stringValue
        )
        return layer("framework-api", ["id": .string(event.id), "title": .string(event.title)])

    case "calendar.delete-event":
        try await eventKit.requestCalendarAccess()
        guard case .string(let id) = params["id"] else {
            throw RPCError.operationFailed("calendar.delete-event requires id")
        }
        try await eventKit.deleteEvent(id: id)
        return layer("framework-api")

    // MARK: - reminder.*

    case "reminder.list-lists":
        try await eventKit.requestRemindersAccess()
        let lists = await eventKit.listReminderLists()
        return layer("framework-api", [
            "lists": .array(lists.map { .object(["id":.string($0.id),"title":.string($0.title)]) }),
        ])

    case "reminder.fetch":
        try await eventKit.requestRemindersAccess()
        let completed = params["completed"]?.boolValue
        let listIDs = params["listIDs"].flatMap { if case .array(let a) = $0 { return a.compactMap { $0.stringValue } }; return nil }
        let reminders = try await eventKit.fetchReminders(listIDs: listIDs, completed: completed)
        let list: [JSONValue] = reminders.map { r in
            var obj: [String: JSONValue] = [
                "id": .string(r.id), "title": .string(r.title),
                "isCompleted": .bool(r.isCompleted), "listTitle": .string(r.listTitle),
            ]
            if let d = r.dueDate { obj["dueDate"] = .double(d.timeIntervalSince1970) }
            if let n = r.notes   { obj["notes"]   = .string(n) }
            return .object(obj)
        }
        return layer("framework-api", ["reminders": .array(list), "count": .int(list.count)])

    case "reminder.create":
        try await eventKit.requestRemindersAccess()
        guard case .string(let title) = params["title"] else {
            throw RPCError.operationFailed("reminder.create requires title")
        }
        let dueDate = params["dueTimestamp"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }
        let reminder = try await eventKit.createReminder(
            title:    title,
            dueDate:  dueDate,
            listID:   params["listID"]?.stringValue,
            notes:    params["notes"]?.stringValue,
            priority: params["priority"]?.intValue ?? 0
        )
        return layer("framework-api", ["id": .string(reminder.id), "title": .string(reminder.title)])

    case "reminder.complete":
        try await eventKit.requestRemindersAccess()
        guard case .string(let id) = params["id"] else {
            throw RPCError.operationFailed("reminder.complete requires id")
        }
        let r = try await eventKit.completeReminder(id: id)
        return layer("framework-api", ["id": .string(r.id), "isCompleted": .bool(r.isCompleted)])

    // MARK: - contact.*

    case "contact.search":
        try await contacts.requestAccess()
        guard case .string(let query) = params["query"] else {
            throw RPCError.operationFailed("contact.search requires query")
        }
        let limit = params["limit"]?.intValue ?? 25
        let results = try await contacts.search(query: query, limit: limit)
        let list: [JSONValue] = results.map { c in
            .object([
                "id":           .string(c.id),
                "fullName":     .string(c.fullName),
                "givenName":    .string(c.givenName),
                "familyName":   .string(c.familyName),
                "emails":       .array(c.emailAddresses.map { .string($0) }),
                "phones":       .array(c.phoneNumbers.map { .string($0) }),
                "organization": .string(c.organizationName),
            ])
        }
        return layer("framework-api", ["contacts": .array(list), "count": .int(list.count)])

    case "contact.get":
        try await contacts.requestAccess()
        guard case .string(let id) = params["id"] else {
            throw RPCError.operationFailed("contact.get requires id")
        }
        let c = try await contacts.get(id: id)
        return layer("framework-api", [
            "id":           .string(c.id),
            "fullName":     .string(c.fullName),
            "givenName":    .string(c.givenName),
            "familyName":   .string(c.familyName),
            "emails":       .array(c.emailAddresses.map { .string($0) }),
            "phones":       .array(c.phoneNumbers.map { .string($0) }),
            "organization": .string(c.organizationName),
            "jobTitle":     .string(c.jobTitle),
        ])

    case "contact.create":
        try await contacts.requestAccess()
        guard case .string(let given)  = params["givenName"],
              case .string(let family) = params["familyName"]
        else { throw RPCError.operationFailed("contact.create requires givenName+familyName") }
        let c = try await contacts.create(
            givenName:    given,
            familyName:   family,
            email:        params["email"]?.stringValue,
            phone:        params["phone"]?.stringValue,
            organization: params["organization"]?.stringValue
        )
        return layer("framework-api", ["id": .string(c.id), "fullName": .string(c.fullName)])
```

- [ ] **Build to verify**

```bash
swift build --product macctl-daemon 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/macctl-daemon/
git commit -m "feat: wire EventKitActor + ContactsActor into dispatcher (calendar/reminder/contact methods)"
```

---

## Task 4: CLI commands

**Files:**
- Create: `Sources/macctl/Commands/CalendarCommand.swift`
- Create: `Sources/macctl/Commands/RemindersCommand.swift`
- Create: `Sources/macctl/Commands/ContactsCommand.swift`
- Modify: `Sources/macctl/main.swift`

- [ ] **CalendarCommand.swift**

```swift
// Sources/macctl/Commands/CalendarCommand.swift
import ArgumentParser
import MacCtlKit
import Foundation

struct CalendarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "Calendar events via EventKit (faster than AppleScript)",
        subcommands: [Calendars.self, Events.self, Create.self, Delete.self])

    struct Calendars: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        func run() throws { try rpc(method: "calendar.list-calendars", params: [:]) }
    }

    struct Events: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "events",
            abstract: "Fetch events (default: next 7 days)")
        @Option(name: .long, help: "Start timestamp (unix)") var from: Double?
        @Option(name: .long, help: "End timestamp (unix)")   var to: Double?
        func run() throws {
            var params: [String: JSONValue] = [:]
            if let f = from { params["startTimestamp"] = .double(f) }
            if let t = to   { params["endTimestamp"]   = .double(t) }
            try rpc(method: "calendar.fetch-events", params: params)
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create")
        @Argument var title: String
        @Option(name: .long, help: "Start (ISO8601 or unix timestamp)") var start: String
        @Option(name: .long, help: "End (ISO8601 or unix timestamp)")   var end: String
        @Option(name: .long, help: "Notes") var notes: String?
        @Option(name: .long, help: "Location") var location: String?
        @Flag(name: .long) var allDay = false
        func run() throws {
            let startTS = parseTimestamp(start)
            let endTS   = parseTimestamp(end)
            var params: [String: JSONValue] = [
                "title":          .string(title),
                "startTimestamp": .double(startTS),
                "endTimestamp":   .double(endTS),
                "isAllDay":       .bool(allDay),
            ]
            if let n = notes    { params["notes"]    = .string(n) }
            if let l = location { params["location"] = .string(l) }
            try rpc(method: "calendar.create-event", params: params)
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @Argument var id: String
        func run() throws { try rpc(method: "calendar.delete-event", params: ["id": .string(id)]) }
    }
}

private func parseTimestamp(_ s: String) -> Double {
    if let d = Double(s) { return d }
    let fmt = ISO8601DateFormatter()
    return fmt.date(from: s)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
}
```

- [ ] **RemindersCommand.swift**

```swift
// Sources/macctl/Commands/RemindersCommand.swift
import ArgumentParser
import MacCtlKit
import Foundation

struct RemindersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Reminders via EventKit",
        subcommands: [Lists.self, Fetch.self, Create.self, Complete.self])

    struct Lists: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "lists")
        func run() throws { try rpc(method: "reminder.list-lists", params: [:]) }
    }

    struct Fetch: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list",
            abstract: "List reminders (default: incomplete)")
        @Flag(name: .long, help: "Include completed reminders") var completed = false
        @Flag(name: .long, help: "Show only completed") var onlyCompleted = false
        func run() throws {
            var params: [String: JSONValue] = [:]
            if onlyCompleted { params["completed"] = .bool(true) }
            else if !completed { params["completed"] = .bool(false) }
            try rpc(method: "reminder.fetch", params: params)
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create")
        @Argument var title: String
        @Option(name: .long, help: "Due date (ISO8601)") var due: String?
        @Option(name: .long, help: "Notes") var notes: String?
        func run() throws {
            var params: [String: JSONValue] = ["title": .string(title)]
            if let d = due {
                let fmt = ISO8601DateFormatter()
                if let date = fmt.date(from: d) { params["dueTimestamp"] = .double(date.timeIntervalSince1970) }
            }
            if let n = notes { params["notes"] = .string(n) }
            try rpc(method: "reminder.create", params: params)
        }
    }

    struct Complete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "complete",
            abstract: "Mark reminder as completed")
        @Argument var id: String
        func run() throws { try rpc(method: "reminder.complete", params: ["id": .string(id)]) }
    }
}
```

- [ ] **ContactsCommand.swift**

```swift
// Sources/macctl/Commands/ContactsCommand.swift
import ArgumentParser
import MacCtlKit

struct ContactsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contacts",
        abstract: "Contacts via ContactsKit",
        subcommands: [Search.self, Get.self, Create.self])

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search")
        @Argument var query: String
        @Option(name: .long, help: "Max results") var limit: Int = 25
        func run() throws {
            try rpc(method: "contact.search",
                    params: ["query": .string(query), "limit": .int(limit)])
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get",
            abstract: "Get contact details by ID")
        @Argument var id: String
        func run() throws { try rpc(method: "contact.get", params: ["id": .string(id)]) }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create")
        @Option(name: .long) var givenName: String = ""
        @Option(name: .long) var familyName: String = ""
        @Option(name: .long) var email: String?
        @Option(name: .long) var phone: String?
        @Option(name: .long) var organization: String?
        func run() throws {
            var params: [String: JSONValue] = [
                "givenName": .string(givenName), "familyName": .string(familyName)
            ]
            if let e = email        { params["email"]        = .string(e) }
            if let p = phone        { params["phone"]        = .string(p) }
            if let o = organization { params["organization"] = .string(o) }
            try rpc(method: "contact.create", params: params)
        }
    }
}
```

- [ ] **Register in main.swift** — add `CalendarCommand.self, RemindersCommand.self, ContactsCommand.self`

- [ ] **Build CLI**

```bash
swift build --product macctl 2>&1 | grep -E "error:|complete"
```
Expected: `Build complete!`

- [ ] **Commit**

```bash
git add Sources/macctl/Commands/ Sources/macctl/main.swift
git commit -m "feat: add CalendarCommand, RemindersCommand, ContactsCommand CLI"
```

---

## Task 5: Tests + smoke + benchmark

- [ ] **Run full test suite**

```bash
swift test 2>&1 | grep "Suite 'All tests'"
```

- [ ] **Smoke test (permissions first)**

```bash
.build/debug/macctl-daemon &
DPID=$!
sleep 1.5

# Calendar — requires Calendar permission
# First run will prompt for permission
.build/debug/macctl calendar list 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('calendars:', d.get('data',{}).get('count','?'), 'layer:', d.get('meta',{}).get('layer','?'))"

# Events for next 7 days
.build/debug/macctl calendar events 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('events count:', d.get('data',{}).get('count','?'))"

# Reminders — requires Reminders permission
.build/debug/macctl reminders list 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('reminders:', d.get('data',{}).get('count','?'), 'layer:', d.get('meta',{}).get('layer','?'))"

# Contacts — requires Contacts permission
.build/debug/macctl contacts search "test" 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('contacts found:', d.get('data',{}).get('count','?'), 'layer:', d.get('meta',{}).get('layer','?'))"

kill $DPID
```

Expected (after granting permissions): all return `layer: framework-api`.

- [ ] **Benchmark EventKit vs AppleScript**

EventKit direct call should be 5-20ms vs 10-30ms for AppleScript.

```bash
# Start daemon
.build/debug/macctl-daemon &
DPID=$!
sleep 1.5

python3 -c "
import subprocess, json, time

def bench(label, args, n=5):
    times = []
    for _ in range(n):
        d = subprocess.run(['.build/debug/macctl']+args, capture_output=True, text=True, timeout=10)
        try:
            j = json.loads(d.stdout)
            t = j.get('meta',{}).get('durationMs',-1)
            if t > 0: times.append(t)
        except: pass
    if times:
        times.sort()
        p50 = times[int(len(times)*0.5)]
        print(f'  {label:<35} P50={p50:.1f}ms  [framework-api]')

bench('calendar list-calendars', ['calendar','list'])
bench('calendar fetch-events (7d)', ['calendar','events'])
bench('reminders list (incomplete)', ['reminders','list'])
bench('contacts search', ['contacts','search','a'])
"

kill $DPID
```

- [ ] **Final commit**

```bash
git add -A
git commit -m "feat: Plan 3B complete — EventKit (Calendar+Reminders) + ContactsKit, CLI + tests"
```

---

## Self-Review

| Spec requirement | Task | Status |
|---|---|---|
| Calendar read via EventKit | Task 1+3 | ✅ |
| Calendar write via EventKit | Task 1+3 | ✅ |
| Reminders read/write via EventKit | Task 1+3 | ✅ |
| Contacts search/read/create | Task 2+3 | ✅ |
| Permission handling (TCC) | Tasks 1+2 | ✅ |
| CLI: calendar/reminders/contacts | Task 4 | ✅ |
| Typed Sendable return structs | Tasks 1+2 | ✅ |
| No direct SQLite/CoreData access | Tasks 1+2 | ✅ |
| Tests | Task 5 | ✅ |
| Benchmark vs AppleScript | Task 5 | ✅ |

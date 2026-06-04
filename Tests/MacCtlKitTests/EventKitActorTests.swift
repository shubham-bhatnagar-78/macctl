import Testing
import Foundation
@testable import MacCtlKit

@Suite("EventKitActor")
struct EventKitActorTests {
    @Test func calendarEventStructIsComplete() {
        let now = Date()
        let event = CalendarEvent(
            id: "test-id", title: "Test Event",
            startDate: now, endDate: now.addingTimeInterval(3600),
            calendarTitle: "Personal", calendarID: "cal-123",
            notes: "some notes", isAllDay: false, location: "Conference Room"
        )
        #expect(event.title == "Test Event")
        #expect(event.id == "test-id")
        #expect(!event.isAllDay)
        #expect(event.location == "Conference Room")
        #expect(event.notes == "some notes")
    }

    @Test func reminderStructIsComplete() {
        let r = ReminderItem(
            id: "rem-1", title: "Buy milk", isCompleted: false,
            dueDate: nil, notes: "2% milk", listTitle: "Reminders",
            listID: "list-1", priority: 1
        )
        #expect(r.title == "Buy milk")
        #expect(!r.isCompleted)
        #expect(r.priority == 1)
        #expect(r.notes == "2% milk")
    }

    @Test func calendarInfoStructIsComplete() {
        let cal = EKCalendarInfo(id: "c1", title: "Work", type: "calDAV", color: "#FF0000")
        #expect(cal.id == "c1")
        #expect(cal.type == "calDAV")
        #expect(cal.color == "#FF0000")
    }

    @Test func actorInitDoesNotCrash() async {
        let actor = EventKitActor()
        _ = actor
    }

    @Test func reminderCompletedFlagWorks() {
        let r = ReminderItem(
            id: "x", title: "Done", isCompleted: true,
            dueDate: Date(), notes: nil, listTitle: "List",
            listID: "l1", priority: 0
        )
        #expect(r.isCompleted)
        #expect(r.dueDate != nil)
    }
}

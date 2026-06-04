import Testing
import Foundation
@testable import MacCtlKit

@Suite("ContactsActor")
struct ContactsActorTests {
    @Test func contactRecordFullName() {
        let c = ContactRecord(
            id: "c1", givenName: "Jane", familyName: "Smith",
            emailAddresses: ["jane@example.com"], phoneNumbers: ["+1-555-0200"],
            organizationName: "Corp", jobTitle: "VP", birthday: nil, note: nil
        )
        #expect(c.fullName == "Jane Smith")
        #expect(c.emailAddresses.count == 1)
        #expect(c.phoneNumbers.first == "+1-555-0200")
    }

    @Test func contactRecordNoFamilyName() {
        let c = ContactRecord(
            id: "c2", givenName: "Madonna", familyName: "",
            emailAddresses: [], phoneNumbers: [],
            organizationName: "", jobTitle: "", birthday: nil, note: nil
        )
        #expect(c.fullName == "Madonna")
    }

    @Test func contactRecordEmptyNames() {
        let c = ContactRecord(
            id: "c3", givenName: "", familyName: "",
            emailAddresses: [], phoneNumbers: [],
            organizationName: "Company Only", jobTitle: "", birthday: nil, note: nil
        )
        #expect(c.fullName == "")
        #expect(c.organizationName == "Company Only")
    }

    @Test func actorInitDoesNotCrash() async {
        let actor = ContactsActor()
        _ = actor
    }
}

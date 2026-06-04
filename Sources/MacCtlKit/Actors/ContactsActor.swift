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
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactBirthdayKey, CNContactNoteKey,
        ].map { $0 as CNKeyDescriptor }

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContacts(matchingName: query)

        var results: [ContactRecord] = []
        try store.enumerateContacts(with: request) { contact, stop in
            results.append(contactToRecord(contact))
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }

    public func get(id: String) throws -> ContactRecord {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactBirthdayKey, CNContactNoteKey,
        ].map { $0 as CNKeyDescriptor }
        let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
        return contactToRecord(contact)
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
            contact.phoneNumbers = [CNLabeledValue(
                label: CNLabelPhoneNumberMain,
                value: CNPhoneNumber(stringValue: p))]
        }
        if let o = organization { contact.organizationName = o }

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contactToRecord(contact)
    }

    // MARK: - Private

    private func contactToRecord(_ c: CNContact) -> ContactRecord {
        ContactRecord(
            id:               c.identifier,
            givenName:        c.givenName,
            familyName:       c.familyName,
            emailAddresses:   c.emailAddresses.map { $0.value as String },
            phoneNumbers:     c.phoneNumbers.map { $0.value.stringValue },
            organizationName: c.organizationName,
            jobTitle:         c.jobTitle,
            birthday:         c.birthday,
            note:             c.isKeyAvailable(CNContactNoteKey) ? c.note : nil
        )
    }
}

public enum ContactsError: Error, Sendable {
    case accessDenied
    case notFound(String)
}

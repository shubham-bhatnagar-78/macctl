import Foundation

public actor DefaultsActor {
    public init() {}

    // Return types use String? / typed reads — Any is not Sendable across actors.
    // For typed reading, use readString/readBool/readInt/readDouble.

    public func readString(domain: String, key: String) -> String? {
        UserDefaults(suiteName: domain)?.string(forKey: key)
    }

    public func readBool(domain: String, key: String) -> Bool? {
        guard let d = UserDefaults(suiteName: domain), d.object(forKey: key) != nil else { return nil }
        return d.bool(forKey: key)
    }

    public func readInt(domain: String, key: String) -> Int? {
        guard let d = UserDefaults(suiteName: domain), d.object(forKey: key) != nil else { return nil }
        return d.integer(forKey: key)
    }

    public func readDouble(domain: String, key: String) -> Double? {
        guard let d = UserDefaults(suiteName: domain), d.object(forKey: key) != nil else { return nil }
        return d.double(forKey: key)
    }

    /// Returns all keys as String representation. Use typed reads for known keys.
    public func readAll(domain: String) -> [String: String] {
        guard let d = UserDefaults(suiteName: domain) else { return [:] }
        return d.dictionaryRepresentation().compactMapValues { "\($0)" }
    }

    public func write(domain: String, key: String, stringValue: String) {
        let d = UserDefaults(suiteName: domain)
        d?.set(stringValue, forKey: key)
        d?.synchronize()
    }

    public func write(domain: String, key: String, boolValue: Bool) {
        let d = UserDefaults(suiteName: domain)
        d?.set(boolValue, forKey: key)
        d?.synchronize()
    }

    public func write(domain: String, key: String, intValue: Int) {
        let d = UserDefaults(suiteName: domain)
        d?.set(intValue, forKey: key)
        d?.synchronize()
    }

    public func write(domain: String, key: String, doubleValue: Double) {
        let d = UserDefaults(suiteName: domain)
        d?.set(doubleValue, forKey: key)
        d?.synchronize()
    }

    public func delete(domain: String, key: String) {
        let d = UserDefaults(suiteName: domain)
        d?.removeObject(forKey: key)
        d?.synchronize()
    }

    public func exists(domain: String, key: String) -> Bool {
        UserDefaults(suiteName: domain)?.object(forKey: key) != nil
    }
}

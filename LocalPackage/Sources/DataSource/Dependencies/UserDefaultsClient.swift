import Foundation

public struct UserDefaultsClient: DependencyClient {
    var bool: @Sendable (String) -> Bool
    var optionalBool: @Sendable (String) -> Bool?
    var optionalInt: @Sendable (String) -> Int?
    var optionalDouble: @Sendable (String) -> Double?
    var stringArray: @Sendable (String) -> [String]?
    var setInt: @Sendable (Int, String) -> Void
    var setDouble: @Sendable (Double, String) -> Void
    var setStringArray: @Sendable ([String], String) -> Void
    var setBool: @Sendable (Bool, String) -> Void
    var removePersistentDomain: @Sendable (String) -> Void
    var persistentDomain: @Sendable (String) -> [String : Any]?

    public static let liveValue = Self(
        bool: { UserDefaults.standard.bool(forKey: $0) },
        optionalBool: { UserDefaults.standard.object(forKey: $0) as? Bool },
        optionalInt: { UserDefaults.standard.object(forKey: $0) as? Int },
        optionalDouble: { UserDefaults.standard.object(forKey: $0) as? Double },
        stringArray: { UserDefaults.standard.stringArray(forKey: $0) },
        setInt: { UserDefaults.standard.set($0, forKey: $1) },
        setDouble: { UserDefaults.standard.set($0, forKey: $1) },
        setStringArray: { UserDefaults.standard.set($0, forKey: $1) },
        setBool: { UserDefaults.standard.set($0, forKey: $1) },
        removePersistentDomain: { UserDefaults.standard.removePersistentDomain(forName: $0) },
        persistentDomain: { UserDefaults.standard.persistentDomain(forName: $0) }
    )

    public static let testValue = Self(
        bool: { _ in false },
        optionalBool: { _ in nil },
        optionalInt: { _ in nil },
        optionalDouble: { _ in nil },
        stringArray: { _ in nil },
        setInt: { _, _ in },
        setDouble: { _, _ in },
        setStringArray: { _, _ in },
        setBool: { _, _ in },
        removePersistentDomain: { _ in },
        persistentDomain: { _ in nil }
    )
}

extension UserDefaults: @retroactive @unchecked Sendable {}

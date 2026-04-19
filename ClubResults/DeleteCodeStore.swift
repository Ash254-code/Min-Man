import Foundation

enum DeleteCodeStore {
    private static let key = "deleteProtectionCode"
    private static let defaultCode = "1234"

    static var currentCode: String {
        let stored = UserDefaults.standard.string(forKey: key) ?? defaultCode
        return isValidCode(stored) ? stored : defaultCode
    }

    static func verify(_ code: String) -> Bool {
        code == currentCode
    }

    static func save(_ code: String) {
        guard isValidCode(code) else { return }
        UserDefaults.standard.set(code, forKey: key)
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == 4 && code.allSatisfy(\.isNumber)
    }
}

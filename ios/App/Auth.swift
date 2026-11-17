// The Access token: kept in the Keychain (this device only), its expiry read from the JWT itself. It comes from the
// page's own sign-in (/app/health/app-signin), which Cloudflare Access puts behind Deyao's Google login.
import Foundation
import Security

enum TokenStore {
    private static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                              kSecAttrService as String: "dev.de0ch.yycsystems", kSecAttrAccount as String: "access-token"]

    static func get() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ token: String) {
        delete()
        var q = base
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() { SecItemDelete(base as CFDictionary) }

    /** the token's `exp`, or nil when it is not a JWT with one */
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /** a token that is still good for a minute */
    static func usable(_ token: String?) -> Bool {
        guard let t = token, let e = expiry(t) else { return false }
        return e.timeIntervalSinceNow > 60
    }

    /** the app's own random value for one sign-in */
    static func newState() -> String {
        var b = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return Data(b).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

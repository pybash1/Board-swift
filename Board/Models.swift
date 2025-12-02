import Foundation

struct APIInfo: Codable {
    let message: String
    let endpoints: [APIEndpoint]
}

struct APIEndpoint: Codable {
    let method: String
    let path: String
    let description: String
}

struct Paste: Identifiable, Codable {
    let id: String
    let content: String
    let createdAt: Date
    
    init(id: String, content: String) {
        self.id = id
        self.content = content
        self.createdAt = Date()
    }
}

struct AppSettings {
    var serverURL: String
    var deviceCode: String?
    var appPassword: String?
    var passphrase: String?
    var notificationsEnabled: Bool
    
    static let defaultServerURL = "https://board-api.pybash.xyz"

    init() {
        // Read from Info.plist (set via xcconfig)
        let bundle = Bundle.main
        
        // Debug: print all Info.plist keys to see what's available
        if let infoPlist = bundle.infoDictionary {
            NSLog("Available Info.plist keys:")
            for (key, value) in infoPlist {
                if key.contains("Server") || key.contains("API") || key.contains("Password") {
                    NSLog("  \(key): \(value)")
                }
            }
        }
        
        // Load serverURL from UserDefaults, fallback to Info.plist, then default URL
        if let savedURL = UserDefaults.standard.string(forKey: "serverURL"), !savedURL.isEmpty {
            self.serverURL = savedURL
        } else if let plistURL = bundle.object(forInfoDictionaryKey: "SERVER_URL") as? String {
            self.serverURL = plistURL
        } else {
            self.serverURL = AppSettings.defaultServerURL
        }
        
        // Load appPassword logic
        if self.serverURL == AppSettings.defaultServerURL {
            self.appPassword = bundle.object(forInfoDictionaryKey: "API_PASSWORD") as? String
        } else {
            self.appPassword = AppSettings.loadAppPasswordFromKeychain()
        }
        
        self.deviceCode = UserDefaults.standard.string(forKey: "deviceCode")
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.passphrase = AppSettings.loadPassphraseFromKeychain()
        
        NSLog("AppSettings - ServerURL: \(serverURL)")
        NSLog("AppSettings - AppPassword: \(appPassword == nil ? "nil" : "******")")
    }
    
    mutating func save() {
        UserDefaults.standard.set(deviceCode, forKey: "deviceCode")
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        
        // Save passphrase to keychain
        if let passphrase = passphrase {
            savePassphraseToKeychain(passphrase)
        }
        
        // Save app password to keychain only if using custom server
        if serverURL != AppSettings.defaultServerURL {
            if let appPassword = appPassword, !appPassword.isEmpty {
                saveAppPasswordToKeychain(appPassword)
            } else {
                deleteAppPasswordFromKeychain()
            }
        }
    }
    
    mutating func updatePassphrase(_ newPassphrase: String?) {
        self.passphrase = newPassphrase
        if let passphrase = newPassphrase {
            savePassphraseToKeychain(passphrase)
        } else {
            deletePassphraseFromKeychain()
        }
    }
    
    private static func loadPassphraseFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.pybash.Board",
            kSecAttrAccount as String: "user_passphrase",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    private func savePassphraseToKeychain(_ passphrase: String) {
        guard let data = passphrase.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.pybash.Board",
            kSecAttrAccount as String: "user_passphrase",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        deletePassphraseFromKeychain()
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deletePassphraseFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.pybash.Board",
            kSecAttrAccount as String: "user_passphrase"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - App Password Keychain Helpers
    
    private static func loadAppPasswordFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.pybash.Board",
            kSecAttrAccount as String: "app_password",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    private func loadAppPasswordFromKeychain() -> String? {
        return AppSettings.loadAppPasswordFromKeychain()
    }
    
    private func saveAppPasswordToKeychain(_ password: String) {
        guard let data = password.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.pybash.Board",
            kSecAttrAccount as String: "app_password",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        deleteAppPasswordFromKeychain()
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deleteAppPasswordFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "xyz.pybash.Board",
            kSecAttrAccount as String: "app_password"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    static func load() -> AppSettings {
        return AppSettings()
    }
}
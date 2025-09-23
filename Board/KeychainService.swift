import Foundation
import Security
import CryptoKit

class KeychainService {
    enum KeychainError: Error {
        case itemNotFound
        case invalidData
        case unexpectedStatus(OSStatus)
    }
    
    enum KeyType: String {
        case accountMasterKey = "AccountMasterKey"
        case devicePrivateKey = "DevicePrivateKey"
        case devicePublicKey = "DevicePublicKey"
        case accountHash = "AccountHash"
        case deviceCode = "DeviceCode"
    }
    
    private static let serviceName = "xyz.pybash.Board"
    
    static func store(_ data: Data, for keyType: KeyType) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyType.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    static func retrieve(for keyType: KeyType) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyType.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    static func delete(for keyType: KeyType) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyType.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    static func exists(for keyType: KeyType) -> Bool {
        do {
            _ = try retrieve(for: keyType)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Convenience methods for specific key types
    
    static func storeAccountMasterKey(_ key: SymmetricKey) throws {
        try store(key.withUnsafeBytes { Data($0) }, for: .accountMasterKey)
    }
    
    static func retrieveAccountMasterKey() throws -> SymmetricKey {
        let data = try retrieve(for: .accountMasterKey)
        return SymmetricKey(data: data)
    }
    
    static func storeDevicePrivateKey(_ key: P256.KeyAgreement.PrivateKey) throws {
        try store(key.rawRepresentation, for: .devicePrivateKey)
    }
    
    static func retrieveDevicePrivateKey() throws -> P256.KeyAgreement.PrivateKey {
        let data = try retrieve(for: .devicePrivateKey)
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
    
    static func storeDevicePublicKey(_ key: P256.KeyAgreement.PublicKey) throws {
        try store(key.rawRepresentation, for: .devicePublicKey)
    }
    
    static func retrieveDevicePublicKey() throws -> P256.KeyAgreement.PublicKey {
        let data = try retrieve(for: .devicePublicKey)
        return try P256.KeyAgreement.PublicKey(rawRepresentation: data)
    }
    
    static func storeAccountHash(_ hash: String) throws {
        try store(hash.data(using: .utf8)!, for: .accountHash)
    }
    
    static func retrieveAccountHash() throws -> String {
        let data = try retrieve(for: .accountHash)
        guard let hash = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return hash
    }
    
    static func storeDeviceCode(_ code: String) throws {
        try store(code.data(using: .utf8)!, for: .deviceCode)
    }
    
    static func retrieveDeviceCode() throws -> String {
        let data = try retrieve(for: .deviceCode)
        guard let code = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return code
    }
    
    // MARK: - Device management
    
    static func isDeviceSetup() -> Bool {
        return exists(for: .accountMasterKey) && 
               exists(for: .devicePrivateKey) && 
               exists(for: .devicePublicKey) &&
               exists(for: .accountHash) &&
               exists(for: .deviceCode)
    }
    
    static func clearAllKeys() throws {
        try delete(for: .accountMasterKey)
        try delete(for: .devicePrivateKey)
        try delete(for: .devicePublicKey)
        try delete(for: .accountHash)
        try delete(for: .deviceCode)
    }
}
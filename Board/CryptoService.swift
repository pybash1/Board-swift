import Foundation
import CryptoKit
import Crypto

class CryptoService {
    enum CryptoError: Error {
        case keyDerivationFailed
        case encryptionFailed
        case decryptionFailed
        case invalidKeyFormat
        case hashingFailed
    }
    
    // MARK: - Key Generation
    
    static func generateAccountMasterKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    static func generateDeviceKeyPair() -> (privateKey: P256.KeyAgreement.PrivateKey, publicKey: P256.KeyAgreement.PublicKey) {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        return (privateKey, publicKey)
    }
    
    static func generateDeviceCode() -> String {
        // Generate 8-character fingerprint from device public key
        do {
            let devicePublicKey = try KeychainService.retrieveDevicePublicKey()
            let hash = SHA256.hash(data: devicePublicKey.rawRepresentation)
            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
            return String(hashString.prefix(8)).uppercased()
        } catch {
            // Fallback: generate random 8-character code
            let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            return String((0..<8).map { _ in characters.randomElement()! })
        }
    }
    
    // MARK: - Account Hash Generation
    
    static func generateAccountHash(from masterKey: SymmetricKey) throws -> String {
        // Use HKDF to derive a hash from the master key
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: "BoardAccountHash".data(using: .utf8)!,
            info: Data(),
            outputByteCount: 32
        )
        
        let hash = SHA256.hash(data: derived.withUnsafeBytes { Data($0) })
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - X3DH Key Agreement
    
    static func performKeyAgreement(
        devicePrivateKey: P256.KeyAgreement.PrivateKey,
        recipientPublicKey: P256.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        // Perform ECDH key agreement
        let sharedSecret = try devicePrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        
        // Derive encryption key using HKDF
        let encryptionKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "BoardEncryption".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        return encryptionKey
    }
    
    // MARK: - Paste Encryption/Decryption
    
    static func encryptPaste(
        _ content: String,
        using encryptionKey: SymmetricKey
    ) throws -> Data {
        guard let contentData = content.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        
        do {
            let sealedBox = try ChaChaPoly.seal(contentData, using: encryptionKey)
            return sealedBox.combined
        } catch {
            throw CryptoError.encryptionFailed
        }
    }
    
    static func decryptPaste(
        _ encryptedData: Data,
        using encryptionKey: SymmetricKey
    ) throws -> String {
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
            let decryptedData = try ChaChaPoly.open(sealedBox, using: encryptionKey)
            
            guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                throw CryptoError.decryptionFailed
            }
            
            return decryptedString
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
    
    // MARK: - Device Registration
    
    static func setupNewDevice() throws -> (accountHash: String, deviceCode: String) {
        // Generate new master key and device keys
        let masterKey = generateAccountMasterKey()
        let (privateKey, publicKey) = generateDeviceKeyPair()
        
        // Store keys in keychain
        try KeychainService.storeAccountMasterKey(masterKey)
        try KeychainService.storeDevicePrivateKey(privateKey)
        try KeychainService.storeDevicePublicKey(publicKey)
        
        // Generate account hash and device code
        let accountHash = try generateAccountHash(from: masterKey)
        let deviceCode = generateDeviceCode()
        
        // Store identifiers
        try KeychainService.storeAccountHash(accountHash)
        try KeychainService.storeDeviceCode(deviceCode)
        
        return (accountHash, deviceCode)
    }
    
    static func linkExistingDevice(accountHash: String) throws -> String {
        // For linking existing device, we need the master key to be provided
        // This would typically come from QR code scanning or manual entry
        // For now, we'll assume the master key is already stored
        
        // Generate new device key pair
        let (privateKey, publicKey) = generateDeviceKeyPair()
        
        // Store device keys
        try KeychainService.storeDevicePrivateKey(privateKey)
        try KeychainService.storeDevicePublicKey(publicKey)
        
        // Store account hash
        try KeychainService.storeAccountHash(accountHash)
        
        // Generate and store device code
        let deviceCode = generateDeviceCode()
        try KeychainService.storeDeviceCode(deviceCode)
        
        return deviceCode
    }
    
    // MARK: - Utility Functions
    
    static func getCurrentDeviceInfo() throws -> (accountHash: String, deviceCode: String, publicKey: Data) {
        let accountHash = try KeychainService.retrieveAccountHash()
        let deviceCode = try KeychainService.retrieveDeviceCode()
        let publicKey = try KeychainService.retrieveDevicePublicKey()
        
        return (accountHash, deviceCode, publicKey.rawRepresentation)
    }
    
    static func encryptForRecipient(
        content: String,
        recipientPublicKey: Data
    ) throws -> Data {
        // Convert recipient public key from raw data
        let recipientKey = try P256.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        
        // Get our device private key
        let devicePrivateKey = try KeychainService.retrieveDevicePrivateKey()
        
        // Perform key agreement
        let encryptionKey = try performKeyAgreement(
            devicePrivateKey: devicePrivateKey,
            recipientPublicKey: recipientKey
        )
        
        // Encrypt the content
        return try encryptPaste(content, using: encryptionKey)
    }
    
    static func decryptFromSender(
        encryptedData: Data,
        senderPublicKey: Data
    ) throws -> String {
        // Convert sender public key from raw data
        let senderKey = try P256.KeyAgreement.PublicKey(rawRepresentation: senderPublicKey)
        
        // Get our device private key
        let devicePrivateKey = try KeychainService.retrieveDevicePrivateKey()
        
        // Perform key agreement
        let encryptionKey = try performKeyAgreement(
            devicePrivateKey: devicePrivateKey,
            recipientPublicKey: senderKey
        )
        
        // Decrypt the content
        return try decryptPaste(encryptedData, using: encryptionKey)
    }
}
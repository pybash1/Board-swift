import Foundation
import CryptoKit

/**
 * Secure text encryption and decryption utilities using CryptoKit
 * 
 * This implementation provides:
 * - PBKDF2 key derivation with HMAC-SHA256
 * - AES-GCM encryption with authentication
 * - Base64 encoded output containing [salt || nonce || ciphertext || tag]
 */
struct CryptoUtils {
    
    /**
     * Encrypts plaintext using a passphrase with AES-GCM encryption
     * 
     * @param text The plaintext string to encrypt
     * @param passphrase The user-provided passphrase for encryption
     * @return Base64 encoded string containing [salt || nonce || ciphertext || tag], or nil if encryption fails
     */
    static func encrypt(text: String, passphrase: String) -> String? {
        guard let textData = text.data(using: .utf8) else {
            return nil
        }
        
        // Generate a random 16-byte salt for key derivation
        // Salt prevents rainbow table attacks and ensures unique keys even with same passphrase
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        // Derive a 256-bit AES key from the passphrase using PBKDF2 with HMAC-SHA256
        // PBKDF2 makes brute force attacks computationally expensive
        guard let derivedKey = deriveKey(from: passphrase, salt: salt) else {
            return nil
        }
        
        // Generate a random 12-byte nonce for AES-GCM
        // Nonce ensures that identical plaintexts produce different ciphertexts
        let nonce = AES.GCM.Nonce()
        
        do {
            // Encrypt the text using AES-GCM
            // GCM provides both confidentiality and authenticity
            let sealedBox = try AES.GCM.seal(textData, using: derivedKey, nonce: nonce)
            
            // Extract the ciphertext and authentication tag
            // Tag allows verification that data hasn't been tampered with
            let ciphertext = sealedBox.ciphertext
            let tag = sealedBox.tag
            
            // Combine all components: [salt || nonce || ciphertext || tag]
            var combinedData = Data()
            combinedData.append(salt)                    // 16 bytes
            combinedData.append(nonce.withUnsafeBytes { Data($0) }) // 12 bytes
            combinedData.append(ciphertext)              // Variable length
            combinedData.append(tag)                     // 16 bytes
            
            // Return as Base64 encoded string
            return combinedData.base64EncodedString()
        } catch {
            print("Encryption failed: \(error)")
            return nil
        }
    }
    
    /**
     * Decrypts a Base64 encoded token using a passphrase
     * 
     * @param token Base64 encoded string containing [salt || nonce || ciphertext || tag]
     * @param passphrase The same passphrase used for encryption
     * @return The original plaintext string, or nil if decryption fails
     */
    static func decrypt(token: String, passphrase: String) -> String? {
        // Normalize the token: remove ALL whitespace (including newlines) and add padding if needed
        var normalizedToken = token.components(separatedBy: .whitespacesAndNewlines).joined()
        
        // Add padding if needed (base64 must be multiple of 4)
        let remainder = normalizedToken.count % 4
        if remainder > 0 {
            normalizedToken += String(repeating: "=", count: 4 - remainder)
            NSLog("CryptoUtils.decrypt: Added \(4 - remainder) padding characters")
        }
        
        NSLog("CryptoUtils.decrypt: Normalized token length: \(normalizedToken.count) (original: \(token.count))")
        
        // Decode the Base64 token
        guard let combinedData = Data(base64Encoded: normalizedToken) else {
            print("CryptoUtils.decrypt: Failed to decode base64 token")
            return nil
        }
        
        // Verify minimum length: 16 (salt) + 12 (nonce) + 16 (tag) = 44 bytes minimum
        guard combinedData.count >= 44 else {
            print("CryptoUtils.decrypt: Token too short (\(combinedData.count) bytes, need at least 44)")
            return nil
        }
        
        // Extract components from the combined data
        let salt = combinedData.prefix(16)                              // First 16 bytes
        let nonce = combinedData.dropFirst(16).prefix(12)              // Next 12 bytes
        let ciphertextAndTag = combinedData.dropFirst(28)              // Remaining bytes
        let tag = ciphertextAndTag.suffix(16)                          // Last 16 bytes
        let ciphertext = ciphertextAndTag.dropLast(16)                 // Everything except last 16 bytes
        
        // Derive the same key using the extracted salt
        guard let derivedKey = deriveKey(from: passphrase, salt: Data(salt)) else {
            return nil
        }
        
        do {
            // Create nonce from extracted bytes
            let gcmNonce = try AES.GCM.Nonce(data: Data(nonce))
            
            // Create sealed box from ciphertext and tag
            let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: Data(ciphertext), tag: Data(tag))
            
            // Decrypt and verify authenticity
            let decryptedData = try AES.GCM.open(sealedBox, using: derivedKey)
            
            // Convert back to string
            guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                print("CryptoUtils.decrypt: Failed to convert decrypted data to UTF-8 string")
                return nil
            }
            
            print("CryptoUtils.decrypt: Successfully decrypted \(decryptedData.count) bytes")
            return decryptedString
        } catch {
            print("CryptoUtils.decrypt: Decryption failed - \(error.localizedDescription)")
            return nil
        }
    }
    
    /**
     * Derives a 256-bit AES key from a passphrase using PBKDF2 with HMAC-SHA256
     * 
     * @param passphrase The user-provided passphrase
     * @param salt Random salt to prevent rainbow table attacks
     * @return 256-bit AES key, or nil if derivation fails
     */
    private static func deriveKey(from passphrase: String, salt: Data) -> SymmetricKey? {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            return nil
        }
        
        // Use PBKDF2 with HMAC-SHA256, 100,000 iterations for good security/performance balance
        // Higher iteration count makes brute force attacks more expensive
        let iterations = 100_000
        let keyLength = 32 // 256 bits
        
        var derivedKeyData = Data(count: keyLength)
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passphraseData.withUnsafeBytes { passphraseBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphraseBytes.bindMemory(to: Int8.self).baseAddress,
                        passphraseData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            return nil
        }
        
        return SymmetricKey(data: derivedKeyData)
    }
}

// Import CommonCrypto for PBKDF2
import CommonCrypto
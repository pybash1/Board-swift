import Foundation
import CryptoKit
import CommonCrypto

/**
 * Debug utilities to help diagnose crypto compatibility issues
 */
struct CryptoDebugUtils {
    
    /**
     * Analyzes an encrypted token and prints detailed information about its structure
     */
    static func analyzeToken(_ token: String) {
        print("=== CRYPTO TOKEN ANALYSIS ===")
        
        // Decode the Base64 token
        guard let combinedData = Data(base64Encoded: token) else {
            print("❌ Failed to decode base64 token")
            print("Token length: \(token.count) characters")
            print("First 50 chars: \(String(token.prefix(50)))")
            return
        }
        
        print("✅ Base64 decoded successfully")
        print("Total bytes: \(combinedData.count)")
        
        // Check minimum length
        if combinedData.count < 44 {
            print("❌ Token too short (need at least 44 bytes)")
            print("   Expected: 16 (salt) + 12 (nonce) + 16 (tag) + ciphertext")
            return
        }
        
        // Extract components
        let salt = combinedData.prefix(16)
        let nonce = combinedData.dropFirst(16).prefix(12)
        let ciphertextAndTag = combinedData.dropFirst(28)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.dropLast(16)
        
        print("\n📊 Component Breakdown:")
        print("   Salt:       \(salt.count) bytes - \(salt.hexString)")
        print("   Nonce:      \(nonce.count) bytes - \(nonce.hexString)")
        print("   Ciphertext: \(ciphertext.count) bytes")
        print("   Tag:        \(tag.count) bytes - \(tag.hexString)")
        
        print("\n=== END ANALYSIS ===\n")
    }
    
    /**
     * Tests decryption with detailed logging
     */
    static func testDecrypt(token: String, passphrase: String) -> (success: Bool, result: String?, error: String?) {
        print("=== DECRYPTION TEST ===")
        print("Passphrase length: \(passphrase.count) characters")
        print("Passphrase bytes: \(passphrase.data(using: .utf8)?.count ?? 0)")
        
        // Decode the Base64 token
        guard let combinedData = Data(base64Encoded: token) else {
            let error = "Failed to decode base64 token"
            print("❌ \(error)")
            return (false, nil, error)
        }
        
        print("✅ Token decoded: \(combinedData.count) bytes")
        
        // Verify minimum length
        guard combinedData.count >= 44 else {
            let error = "Token too short (\(combinedData.count) bytes)"
            print("❌ \(error)")
            return (false, nil, error)
        }
        
        // Extract components
        let salt = combinedData.prefix(16)
        let nonce = combinedData.dropFirst(16).prefix(12)
        let ciphertextAndTag = combinedData.dropFirst(28)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.dropLast(16)
        
        print("✅ Components extracted")
        
        // Test key derivation with different iteration counts
        let iterationCounts = [100_000, 10_000, 1_000, 100, 210_000]
        
        for iterations in iterationCounts {
            print("\n🔑 Testing with \(iterations) iterations...")
            
            guard let derivedKey = deriveKey(from: passphrase, salt: Data(salt), iterations: iterations) else {
                print("❌ Key derivation failed")
                continue
            }
            
            do {
                let gcmNonce = try AES.GCM.Nonce(data: Data(nonce))
                let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: Data(ciphertext), tag: Data(tag))
                let decryptedData = try AES.GCM.open(sealedBox, using: derivedKey)
                
                if let decryptedString = String(data: decryptedData, encoding: .utf8) {
                    print("✅ SUCCESS with \(iterations) iterations!")
                    print("   Decrypted: \(decryptedString.prefix(100))")
                    print("=== END TEST ===\n")
                    return (true, decryptedString, nil)
                } else {
                    print("❌ Decrypted but not valid UTF-8")
                }
            } catch {
                print("❌ \(error.localizedDescription)")
            }
        }
        
        let error = "All iteration counts failed"
        print("\n❌ \(error)")
        print("=== END TEST ===\n")
        return (false, nil, error)
    }
    
    /**
     * Derives a key with configurable iteration count
     */
    private static func deriveKey(from passphrase: String, salt: Data, iterations: Int) -> SymmetricKey? {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            return nil
        }
        
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
    
    /**
     * Tests encryption to verify round-trip
     */
    static func testEncryptDecrypt(plaintext: String, passphrase: String) {
        print("=== ROUND-TRIP TEST ===")
        print("Plaintext: \(plaintext)")
        
        guard let encrypted = CryptoUtils.encrypt(text: plaintext, passphrase: passphrase) else {
            print("❌ Encryption failed")
            return
        }
        
        print("✅ Encrypted: \(encrypted.prefix(50))...")
        
        analyzeToken(encrypted)
        
        guard let decrypted = CryptoUtils.decrypt(token: encrypted, passphrase: passphrase) else {
            print("❌ Decryption failed")
            return
        }
        
        if decrypted == plaintext {
            print("✅ Round-trip successful!")
        } else {
            print("❌ Decrypted text doesn't match original")
            print("   Expected: \(plaintext)")
            print("   Got: \(decrypted)")
        }
        
        print("=== END TEST ===\n")
    }
}

// Helper extension for hex encoding
extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

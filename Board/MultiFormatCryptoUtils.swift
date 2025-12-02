import Foundation
import CryptoKit
import CommonCrypto

/**
 * Multi-format crypto utilities that can handle different encoding schemes
 * This is for compatibility with Android clients that might use different encodings
 */
struct MultiFormatCryptoUtils {
    
    /**
     * Attempts to decrypt content that might be in various formats
     */
    static func smartDecrypt(content: String, passphrase: String) -> String? {
        NSLog("🔐 SmartDecrypt: Attempting to decrypt content of length \(content.count)")
        
        // Normalize the content (trim whitespace, add padding)
        let normalizedContent = normalizeBase64(content)
        
        // Strategy 1: Standard base64
        if let decrypted = tryBase64Decrypt(content: normalizedContent, passphrase: passphrase) {
            NSLog("✅ SmartDecrypt: Success with standard base64")
            return decrypted
        }
        
        // Strategy 2: URL-safe base64 (Android might use this)
        if let decrypted = tryUrlSafeBase64Decrypt(content: normalizedContent, passphrase: passphrase) {
            NSLog("✅ SmartDecrypt: Success with URL-safe base64")
            return decrypted
        }
        
        // Strategy 3: Hex encoding (some Android libraries use this)
        if let decrypted = tryHexDecrypt(content: normalizedContent, passphrase: passphrase) {
            NSLog("✅ SmartDecrypt: Success with hex encoding")
            return decrypted
        }
        
        // Strategy 4: Base64 with different iteration counts
        if let decrypted = tryDifferentIterations(content: normalizedContent, passphrase: passphrase) {
            NSLog("✅ SmartDecrypt: Success with different iteration count")
            return decrypted
        }
        
        NSLog("❌ SmartDecrypt: All strategies failed")
        return nil
    }
    
    // MARK: - Helper Functions
    
    /**
     * Normalizes base64 string by removing ALL whitespace and adding padding
     */
    private static func normalizeBase64(_ input: String) -> String {
        // Remove ALL whitespace characters (spaces, tabs, newlines, etc.)
        var normalized = input.components(separatedBy: .whitespacesAndNewlines).joined()
        
        // Add padding if needed (base64 must be multiple of 4)
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        
        return normalized
    }
    
    // MARK: - Decryption Strategies
    
    private static func tryBase64Decrypt(content: String, passphrase: String) -> String? {
        NSLog("🔐 Trying standard base64 decryption...")
        return CryptoUtils.decrypt(token: content, passphrase: passphrase)
    }
    
    private static func tryUrlSafeBase64Decrypt(content: String, passphrase: String) -> String? {
        NSLog("🔐 Trying URL-safe base64 decryption...")
        
        // Convert URL-safe base64 to standard base64
        // Replace - with + and _ with /
        var standardBase64 = content
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = standardBase64.count % 4
        if remainder > 0 {
            standardBase64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return CryptoUtils.decrypt(token: standardBase64, passphrase: passphrase)
    }
    
    private static func tryHexDecrypt(content: String, passphrase: String) -> String? {
        NSLog("🔐 Trying hex decryption...")
        
        // Check if content looks like hex (only contains 0-9, a-f, A-F)
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard content.rangeOfCharacter(from: hexCharacterSet.inverted) == nil else {
            NSLog("   Not hex format")
            return nil
        }
        
        // Convert hex to data
        guard let hexData = hexStringToData(content) else {
            NSLog("   Failed to convert hex to data")
            return nil
        }
        
        // Convert to base64 and try to decrypt
        let base64String = hexData.base64EncodedString()
        return CryptoUtils.decrypt(token: base64String, passphrase: passphrase)
    }
    
    private static func tryDifferentIterations(content: String, passphrase: String) -> String? {
        NSLog("🔐 Trying different iteration counts...")
        
        guard let combinedData = Data(base64Encoded: content) else {
            return nil
        }
        
        guard combinedData.count >= 44 else {
            return nil
        }
        
        // Extract components
        let salt = combinedData.prefix(16)
        let nonce = combinedData.dropFirst(16).prefix(12)
        let ciphertextAndTag = combinedData.dropFirst(28)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.dropLast(16)
        
        // Common iteration counts used by different platforms
        let iterationCounts = [
            10000,    // Common Android default
            100000,   // Mac default
            1000,     // Low security but sometimes used
            65536,    // Java default
            250000,   // CryptoJS default
            4096,     // Old Android default
            210000    // OWASP recommendation
        ]
        
        for iterations in iterationCounts {
            NSLog("   Testing \(iterations) iterations...")
            
            guard let derivedKey = deriveKey(
                from: passphrase,
                salt: Data(salt),
                iterations: iterations
            ) else {
                continue
            }
            
            do {
                let gcmNonce = try AES.GCM.Nonce(data: Data(nonce))
                let sealedBox = try AES.GCM.SealedBox(
                    nonce: gcmNonce,
                    ciphertext: Data(ciphertext),
                    tag: Data(tag)
                )
                let decryptedData = try AES.GCM.open(sealedBox, using: derivedKey)
                
                if let decryptedString = String(data: decryptedData, encoding: .utf8) {
                    NSLog("✅ Success with \(iterations) iterations!")
                    return decryptedString
                }
            } catch {
                // Try next iteration count
                continue
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Functions
    
    private static func hexStringToData(_ hex: String) -> Data? {
        var data = Data()
        var hex = hex
        
        // Remove any whitespace
        hex = hex.replacingOccurrences(of: " ", with: "")
        
        // Ensure even length
        guard hex.count % 2 == 0 else { return nil }
        
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            
            data.append(byte)
            index = nextIndex
        }
        
        return data
    }
    
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
}

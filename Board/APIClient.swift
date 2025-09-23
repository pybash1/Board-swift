import Foundation

class APIClient {
    enum APIError: Error {
        case invalidURL
        case noData
        case decodingError(Error)
        case serverError(String)
        case networkError(Error)
        case authenticationRequired
    }
    
    private let baseURL = "http://127.0.0.1:8820"
    private let session = URLSession.shared
    
    // MARK: - Data Models
    
    struct DeviceKey: Codable {
        let publicKey: String
        let deviceCode: String
    }
    
    struct KeysResponse: Codable {
        let keys: [DeviceKey]
    }
    
    struct CreatePasteRequest: Codable {
        let content: String
        let encryptedFor: [String]? // Device codes
    }
    
    struct CreatePasteResponse: Codable {
        let id: String
        let url: String
    }
    
    struct PasteResponse: Codable {
        let id: String
        let content: String
        let createdAt: String
        let encryptedBy: String? // Device code of sender
    }
    
    // MARK: - Request Helpers
    
    private func createRequest(url: URL, method: String = "GET") throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Add required headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Board/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        
        // Add Device-Code header if available
        if let deviceCode = try? KeychainService.retrieveDeviceCode() {
            request.setValue(deviceCode, forHTTPHeaderField: "Device-Code")
        }
        
        return request
    }
    
    private func performRequest<T: Codable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw APIError.serverError(errorMessage)
                }
                throw APIError.serverError("HTTP \(httpResponse.statusCode)")
            }
            
            guard !data.isEmpty else {
                throw APIError.noData
            }
            
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(responseType, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Device Registration
    
    func registerDevice() async throws {
        guard let url = URL(string: "\(baseURL)/keys") else {
            throw APIError.invalidURL
        }
        
        // Get current device info
        let (accountHash, deviceCode, publicKeyData) = try CryptoService.getCurrentDeviceInfo()
        let publicKeyBase64 = publicKeyData.base64EncodedString()
        
        var request = try createRequest(url: url, method: "POST")
        
        let payload = [
            "accountHash": accountHash,
            "deviceCode": deviceCode,
            "publicKey": publicKeyBase64
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        // For device registration, we expect a simple success response
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw APIError.serverError("Failed to register device")
        }
    }
    
    // MARK: - Key Management
    
    func fetchKeys(for accountHash: String) async throws -> KeysResponse {
        guard let url = URL(string: "\(baseURL)/keys/\(accountHash)") else {
            throw APIError.invalidURL
        }
        
        let request = try createRequest(url: url)
        return try await performRequest(request, responseType: KeysResponse.self)
    }
    
    // MARK: - Paste Operations
    
    func createPaste(content: String, encryptedFor deviceCodes: [String]? = nil) async throws -> CreatePasteResponse {
        guard let url = URL(string: "\(baseURL)/pastes/new") else {
            throw APIError.invalidURL
        }
        
        var request = try createRequest(url: url, method: "POST")
        
        let payload = CreatePasteRequest(content: content, encryptedFor: deviceCodes)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        return try await performRequest(request, responseType: CreatePasteResponse.self)
    }
    
    func fetchPaste(id: String) async throws -> PasteResponse {
        guard let url = URL(string: "\(baseURL)/\(id)") else {
            throw APIError.invalidURL
        }
        
        let request = try createRequest(url: url)
        return try await performRequest(request, responseType: PasteResponse.self)
    }
    
    // MARK: - High-Level Operations
    
    func createEncryptedPaste(content: String, for accountHash: String) async throws -> CreatePasteResponse {
        // Fetch recipient keys
        let keysResponse = try await fetchKeys(for: accountHash)
        
        var encryptedContent: [String: String] = [:]
        
        // Encrypt for each device
        for deviceKey in keysResponse.keys {
            // Skip our own device
            if let ownDeviceCode = try? KeychainService.retrieveDeviceCode(),
               deviceKey.deviceCode == ownDeviceCode {
                continue
            }
            
            // Convert base64 public key to Data
            guard let publicKeyData = Data(base64Encoded: deviceKey.publicKey) else {
                continue
            }
            
            do {
                let encryptedData = try CryptoService.encryptForRecipient(
                    content: content,
                    recipientPublicKey: publicKeyData
                )
                encryptedContent[deviceKey.deviceCode] = encryptedData.base64EncodedString()
            } catch {
                // Skip devices we can't encrypt for
                continue
            }
        }
        
        // Create paste with encrypted content
        let pasteContent = try JSONSerialization.data(withJSONObject: encryptedContent)
        let pasteContentString = String(data: pasteContent, encoding: .utf8) ?? ""
        
        return try await createPaste(
            content: pasteContentString,
            encryptedFor: Array(encryptedContent.keys)
        )
    }
    
    func fetchAndDecryptPaste(id: String) async throws -> String {
        let paste = try await fetchPaste(id: id)
        
        // Try to parse as encrypted content
        guard let contentData = paste.content.data(using: .utf8),
              let encryptedContent = try? JSONSerialization.jsonObject(with: contentData) as? [String: String] else {
            // Return as plain text if not encrypted
            return paste.content
        }
        
        // Get our device code
        guard let deviceCode = try? KeychainService.retrieveDeviceCode() else {
            throw APIError.authenticationRequired
        }
        
        // Find our encrypted content
        guard let encryptedString = encryptedContent[deviceCode],
              let encryptedData = Data(base64Encoded: encryptedString) else {
            throw APIError.serverError("No content encrypted for this device")
        }
        
        // Get sender's public key for decryption
        guard let senderDeviceCode = paste.encryptedBy else {
            throw APIError.serverError("No sender information")
        }
        
        // Fetch sender's public key
        let accountHash = try KeychainService.retrieveAccountHash()
        let keysResponse = try await fetchKeys(for: accountHash)
        
        guard let senderKey = keysResponse.keys.first(where: { $0.deviceCode == senderDeviceCode }),
              let senderPublicKeyData = Data(base64Encoded: senderKey.publicKey) else {
            throw APIError.serverError("Sender's public key not found")
        }
        
        // Decrypt content
        return try CryptoService.decryptFromSender(
            encryptedData: encryptedData,
            senderPublicKey: senderPublicKeyData
        )
    }
    
    // MARK: - Convenience Methods
    
    func isServerReachable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            return false
        }
        
        do {
            let request = try createRequest(url: url)
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
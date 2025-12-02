import Foundation
import Combine

class BoardAPIClient: ObservableObject {
    private let baseURL: String
    private let deviceCode: String
    private let appPassword: String?
    
    init(baseURL: String = "https://board-api.pybash.xyz", deviceCode: String, appPassword: String? = nil) {
        self.baseURL = baseURL
        self.deviceCode = deviceCode
        self.appPassword = appPassword
    }
    
    private func createRequest(path: String, method: String = "GET") -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            fatalError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(deviceCode, forHTTPHeaderField: "Device-Code")
        
        if let password = appPassword {
            request.setValue(password, forHTTPHeaderField: "App-Password")
        }
        
        return request
    }
    
    func generateDeviceCode() async throws -> String {
        var request = createRequest(path: "/device", method: "POST")
        
        if let password = appPassword {
            request.setValue(password, forHTTPHeaderField: "App-Password")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BoardAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return String(data: data, encoding: .utf8) ?? ""
        case 401:
            throw BoardAPIError.unauthorized
        default:
            throw BoardAPIError.serverError(httpResponse.statusCode)
        }
    }
    
    func createPaste(content: String) async throws -> String {
        var request = createRequest(path: "/", method: "PUT")
        request.httpBody = content.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BoardAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return String(data: data, encoding: .utf8) ?? ""
        case 400:
            throw BoardAPIError.badRequest
        case 401:
            throw BoardAPIError.unauthorized
        case 413:
            throw BoardAPIError.payloadTooLarge
        default:
            throw BoardAPIError.serverError(httpResponse.statusCode)
        }
    }
    
    func getAllPastes() async throws -> [String] {
        let request = createRequest(path: "/all")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BoardAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode([String].self, from: data)
        case 400:
            throw BoardAPIError.badRequest
        case 401:
            throw BoardAPIError.unauthorized
        default:
            throw BoardAPIError.serverError(httpResponse.statusCode)
        }
    }
    
    func getPaste(id: String) async throws -> String {
        let request = createRequest(path: "/\(id)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BoardAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return String(data: data, encoding: .utf8) ?? ""
        case 400:
            throw BoardAPIError.badRequest
        case 401:
            throw BoardAPIError.unauthorized
        case 404:
            throw BoardAPIError.notFound
        default:
            throw BoardAPIError.serverError(httpResponse.statusCode)
        }
    }
    
    func getAPIInfo() async throws -> APIInfo {
        let request = createRequest(path: "/")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BoardAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(APIInfo.self, from: data)
        default:
            throw BoardAPIError.serverError(httpResponse.statusCode)
        }
    }
}

enum BoardAPIError: Error, LocalizedError {
    case invalidResponse
    case badRequest
    case unauthorized
    case notFound
    case payloadTooLarge
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .badRequest:
            return "Bad request - check device code"
        case .unauthorized:
            return "Unauthorized - check password or device code"
        case .notFound:
            return "Paste not found"
        case .payloadTooLarge:
            return "Paste too large"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
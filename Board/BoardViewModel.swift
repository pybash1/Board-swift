import Foundation
import Combine
import AppKit
import UserNotifications

@MainActor
class BoardViewModel: ObservableObject {
    @Published var pastes: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var settings = AppSettings.load()
    @Published var isSettingsWindowVisible = false
    @Published var isClipboardMonitoringEnabled = true
    
    var pollingInterval: TimeInterval {
        return _pollingInterval
    }
    
    var apiClient: BoardAPIClient?
    private var clipboardMonitorTimer: Timer?
    private var pastePollingTimer: Timer?
    private var lastClipboardContent: String = ""
    private var isUploadingClipboard = false
    private var lastProcessedPasteIds: Set<String> = []
    private var _pollingInterval: TimeInterval = 1.0
    
    var isSetupComplete: Bool {
        return settings.deviceCode != nil
    }
    
    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("Notification permission granted: \(granted)")
            if !granted {
                print("Notification permission denied")
            } else {
                print("Notification permission granted successfully")
            }
        } catch {
            print("Failed to request notification permission: \(error)")
        }
    }
    
    func requestInitialNotificationPermission() async {
        await requestNotificationPermission()
    }
    
    func initialize() async {
        guard let deviceCode = settings.deviceCode else { return }
        
        apiClient = BoardAPIClient(
            baseURL: settings.serverURL,
            deviceCode: deviceCode,
            appPassword: settings.appPassword
        )
        
        await loadPastes()
        startClipboardMonitoring()
        startPastePolling()
    }
    
    func generateDeviceCode() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let tempClient = BoardAPIClient(
                baseURL: settings.serverURL,
                deviceCode: "",
                appPassword: settings.appPassword
            )
            
            let newDeviceCode = try await tempClient.generateDeviceCode()
            
            var updatedSettings = settings
            updatedSettings.deviceCode = newDeviceCode.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedSettings.save()
            settings = updatedSettings
            
            apiClient = BoardAPIClient(
                baseURL: settings.serverURL,
                deviceCode: settings.deviceCode!,
                appPassword: settings.appPassword
            )
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func setDeviceCode(_ deviceCode: String) async {
        isLoading = true
        errorMessage = nil
        
        // Validate device code format (should be 8 characters)
        let cleanedCode = deviceCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleanedCode.count == 8 else {
            errorMessage = "Device code must be exactly 8 characters"
            isLoading = false
            return
        }
        
        // Test the device code by trying to connect to the API
        do {
            let testClient = BoardAPIClient(
                baseURL: settings.serverURL,
                deviceCode: cleanedCode,
                appPassword: settings.appPassword
            )
            
            // Try to get API info to verify the device code works
            _ = try await testClient.getAPIInfo()
            
            // If successful, save the device code
            var updatedSettings = settings
            updatedSettings.deviceCode = cleanedCode
            updatedSettings.save()
            settings = updatedSettings
            
            apiClient = BoardAPIClient(
                baseURL: settings.serverURL,
                deviceCode: cleanedCode,
                appPassword: settings.appPassword
            )
            
            isLoading = false
        } catch {
            errorMessage = "Failed to connect with device code: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func loadPastes() async {
        guard let client = apiClient else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let pasteIds = try await client.getAllPastes()
            pastes = pasteIds
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func createPaste(content: String) async throws -> String {
        guard let client = apiClient else {
            throw BoardAPIError.invalidResponse
        }
        
        // Encrypt content if passphrase is provided
        let finalContent: String
        if let passphrase = settings.passphrase, !passphrase.isEmpty {
            guard let encryptedContent = CryptoUtils.encrypt(text: content, passphrase: passphrase) else {
                throw BoardAPIError.badRequest // Could create a specific encryption error
            }
            finalContent = encryptedContent
        } else {
            finalContent = content
        }
        
        return try await client.createPaste(content: finalContent)
    }
    
    func getPaste(id: String) async throws -> String {
        NSLog("📥 getPaste: Called for id: \(id)")
        guard let client = apiClient else {
            NSLog("📥 getPaste: ERROR - No API client!")
            throw BoardAPIError.invalidResponse
        }
        
        let content = try await client.getPaste(id: id)
        NSLog("📥 getPaste: Retrieved content from API, length: \(content.count) characters")
        NSLog("📥 getPaste: Content preview (first 100 chars): \(String(content.prefix(100)))")
        
        // Detailed content analysis
        if let contentData = content.data(using: .utf8) {
            NSLog("📥 getPaste: Content as UTF-8 data: \(contentData.count) bytes")
            let hexDump = contentData.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
            NSLog("📥 getPaste: First 32 bytes (hex): \(hexDump)")
        }
        
        // Check if it looks like base64
        let isLikelyBase64 = content.range(of: "^[A-Za-z0-9+/]+=*$", options: .regularExpression) != nil
        NSLog("📥 getPaste: Looks like base64: \(isLikelyBase64)")
        
        // Try to decode as base64 to see what we get
        if let base64Data = Data(base64Encoded: content) {
            NSLog("📥 getPaste: Successfully decoded as base64: \(base64Data.count) bytes")
            let hexDump = base64Data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
            NSLog("📥 getPaste: Decoded first 32 bytes (hex): \(hexDump)")
        } else {
            NSLog("📥 getPaste: ⚠️ CANNOT decode as base64 - this is the issue!")
            NSLog("📥 getPaste: Content starts with: \(String(content.prefix(50)))")
        }
        
        NSLog("📥 getPaste: Passphrase configured: \(settings.passphrase != nil && !settings.passphrase!.isEmpty)")
        
        // Attempt to decrypt if passphrase is provided
        if let passphrase = settings.passphrase, !passphrase.isEmpty {
            NSLog("📥 getPaste: Attempting decryption with passphrase")
            
            // Use smart decryption which tries multiple formats
            if let decryptedContent = MultiFormatCryptoUtils.smartDecrypt(content: content, passphrase: passphrase) {
                NSLog("✅ Successfully decrypted paste \(id)")
                return decryptedContent
            } else {
                NSLog("❌ All decryption strategies failed")
                
                // Determine failure reason for user feedback
                let failureReason: String
                if content.isEmpty {
                    failureReason = "empty content"
                } else if Data(base64Encoded: content) == nil {
                    // Try URL-safe base64
                    let urlSafeConverted = content
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    if Data(base64Encoded: urlSafeConverted) == nil {
                        failureReason = "invalid encoding (not base64 or hex)"
                    } else {
                        failureReason = "wrong passphrase"
                    }
                } else {
                    failureReason = "wrong passphrase or incompatible encryption"
                }
                
                // Return user-friendly error message with more details for debugging
                NSLog("📥 getPaste: Returning error message to user")
                return "[encryption failed - \(failureReason)]"
            }
        } else {
            NSLog("⚠️ No passphrase configured - returning content as-is")
        }
        
        // Return original content if no passphrase
        NSLog("📥 getPaste: Returning original (encrypted?) content")
        return content
    }
    
    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        settings.save()
        
        // Reinitialize API client with updated settings
        if let deviceCode = settings.deviceCode {
            apiClient = BoardAPIClient(
                baseURL: settings.serverURL,
                deviceCode: deviceCode,
                appPassword: settings.appPassword
            )
            
            // Restart clipboard monitoring with new API client
            if isClipboardMonitoringEnabled {
                stopClipboardMonitoring()
                startClipboardMonitoring()
            }
            
            // Restart paste polling with new API client
            stopPastePolling()
            startPastePolling()
        }
    }
    
    // MARK: - Menu Bar Actions
    
    func copyLastPaste() async {
        guard let lastPasteId = pastes.first else { 
            showNotification(title: "No Pastes", message: "Looks like your clipboard's empty!")
            return
        }
        
        do {
            let content = try await getPaste(id: lastPasteId)
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            
            showNotification(title: "Copied", message: "Last paste's on your clipboard now.")
        } catch {
            showNotification(title: "Failed!", message: "Failed to copy: \(error.localizedDescription)")
        }
    }
    
    func pasteFromClipboard() async {
        let pasteboard = NSPasteboard.general
        guard let content = pasteboard.string(forType: .string), !content.isEmpty else {
            showNotification(title: "Empty Clipboard", message: "Looks like theres nothing to copy right now.")
            return
        }
        
        // Update last known content to prevent auto-upload duplication
        lastClipboardContent = content
        
        do {
            let pasteId = try await createPaste(content: content)
            await loadPastes() // Refresh the pastes list
            showNotification(title: "Synced", message: "Clipboard synced to other devices")
        } catch {
            showNotification(title: "Failed!", message: "Failed to sync: \(error.localizedDescription)")
        }
    }
    
    func pasteFromFile(url: URL) async {
        do {
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let content = try String(contentsOf: url, encoding: .utf8)
            let pasteId = try await createPaste(content: content)
            await loadPastes() // Refresh the pastes list
            showNotification(title: "Synced", message: "Uploaded file contents to other devices")
        } catch {
            showNotification(title: "Failed!", message: "Failed to sync file: \(error.localizedDescription)")
        }
    }
    
    func showNotification(title: String, message: String) {
        print("showNotification called - title: \(title), message: \(message)")
        print("notificationsEnabled: \(settings.notificationsEnabled)")
        
        guard settings.notificationsEnabled else { 
            print("Notifications disabled, skipping notification")
            return 
        }
        
        // Check current authorization status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("Notification authorization status: \(settings.authorizationStatus.rawValue)")
            print("Alert setting: \(settings.alertSetting.rawValue)")
            print("Sound setting: \(settings.soundSetting.rawValue)")
            print("Badge setting: \(settings.badgeSetting.rawValue)")
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
            } else {
                print("Notification added successfully")
            }
        }
    }
    
    func updateSettingsWindowVisibility(_ isVisible: Bool) {
        isSettingsWindowVisible = isVisible
        updateDockIconVisibility()
    }
    
    private func updateDockIconVisibility() {
        if isSettingsWindowVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - Clipboard Monitoring
    
    func startClipboardMonitoring() {
        guard isClipboardMonitoringEnabled else { return }
        
        // Initialize with current clipboard content to avoid immediate upload
        let pasteboard = NSPasteboard.general
        lastClipboardContent = pasteboard.string(forType: .string) ?? ""
        
        // Start timer to check clipboard every 1 second
        clipboardMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkClipboardForChanges()
            }
        }
    }
    
    func stopClipboardMonitoring() {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
    }
    
    func toggleClipboardMonitoring() {
        isClipboardMonitoringEnabled.toggle()
        
        if isClipboardMonitoringEnabled {
            startClipboardMonitoring()
        } else {
            stopClipboardMonitoring()
        }
    }
    
    private func checkClipboardForChanges() async {
        guard !isUploadingClipboard else { return }
        
        let pasteboard = NSPasteboard.general
        guard let currentContent = pasteboard.string(forType: .string),
              !currentContent.isEmpty,
              currentContent != lastClipboardContent else {
            return
        }
        
        // Update last known content immediately to prevent duplicate uploads
        lastClipboardContent = currentContent
        
        // Upload new clipboard content
        await uploadClipboardContent(currentContent)
    }
    
    private func uploadClipboardContent(_ content: String) async {
        guard apiClient != nil else { return }
        
        isUploadingClipboard = true
        
        do {
            let pasteId = try await createPaste(content: content)
            await loadPastes() // Refresh the pastes list
            showNotification(title: "Synced", message: "Clipboard content synced to other devices")
        } catch {
            // Don't show error notifications for auto-uploads to avoid spam
            print("Failed to auto-upload clipboard content: \(error.localizedDescription)")
        }
        
        isUploadingClipboard = false
    }
    
    deinit {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
        pastePollingTimer?.invalidate()
        pastePollingTimer = nil
    }
    
    // MARK: - Paste Polling
    
    func startPastePolling() {
        guard apiClient != nil else { return }
        
        // Initialize with current pastes to avoid processing existing ones
        Task {
            await loadPastes()
            lastProcessedPasteIds = Set(pastes)
        }
        
        // Start timer to poll for new pastes every interval
        pastePollingTimer = Timer.scheduledTimer(withTimeInterval: _pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForNewPastes()
            }
        }
    }
    
    func stopPastePolling() {
        pastePollingTimer?.invalidate()
        pastePollingTimer = nil
    }
    
    func setPollingInterval(_ interval: TimeInterval) {
        _pollingInterval = max(1.0, interval) // Minimum 1 second
        
        // Restart polling with new interval if currently running
        if pastePollingTimer != nil {
            stopPastePolling()
            startPastePolling()
        }
    }
    
    private func checkForNewPastes() async {
        guard let client = apiClient else { return }
        
        do {
            let currentPasteIds = try await client.getAllPastes()
            let newPasteIds = Set(currentPasteIds).subtracting(lastProcessedPasteIds)
            
            // Process new pastes in order (most recent first, assuming API returns them in order)
            for pasteId in currentPasteIds where newPasteIds.contains(pasteId) {
                await processNewPaste(id: pasteId)
            }
            
            // Update our tracking set
            lastProcessedPasteIds = Set(currentPasteIds)
            
            // Update the pastes list for UI
            if !newPasteIds.isEmpty {
                pastes = currentPasteIds
            }
        } catch {
            // Silently handle errors to avoid spamming notifications
            print("Failed to check for new pastes: \(error.localizedDescription)")
        }
    }
    
    private func processNewPaste(id: String) async {
        NSLog("🔔 processNewPaste: Starting to process new paste with id: \(id)")
        do {
            NSLog("🔔 processNewPaste: Calling getPaste for id: \(id)")
            let content = try await getPaste(id: id)
            NSLog("🔔 processNewPaste: Received content of length: \(content.count)")
            
            // Only auto-copy if it's different from current clipboard
            let pasteboard = NSPasteboard.general
            let currentClipboard = pasteboard.string(forType: .string) ?? ""
            
            if content != currentClipboard {
                NSLog("🔔 processNewPaste: Content is different, updating clipboard")
                // Update our tracking BEFORE updating clipboard to prevent re-uploading
                lastClipboardContent = content
                
                // Set upload flag to prevent clipboard monitoring from triggering during this update
                isUploadingClipboard = true
                
                // Update clipboard with new content
                pasteboard.clearContents()
                pasteboard.setString(content, forType: .string)
                
                // Reset upload flag after a brief delay to ensure clipboard update is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUploadingClipboard = false
                }
                
                showNotification(title: "Synced", message: "Got something new from your other device ✨")
            } else {
                NSLog("🔔 processNewPaste: Content is the same as current clipboard, skipping update")
            }
        } catch {
            NSLog("❌ Failed to process new paste \(id): \(error.localizedDescription)")
        }
    }
}

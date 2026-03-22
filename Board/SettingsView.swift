import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var viewModel: BoardViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var deviceCode: String = ""
    @State private var passphrase: String = ""
    @State private var serverURL: String = ""
    @State private var appPassword: String = ""
    @State private var isAppPasswordVisible = false
    @State private var notificationsEnabled: Bool = true
    @State private var pollingInterval: Double = 1.0
    @State private var showingRegenerateAlert = false
    @State private var showingDeviceCodeInput = false
    @State private var newDeviceCode = ""
    @State private var isPassphraseVisible = false
    
    init() {
        // Initialize with default values - will be updated in onAppear
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Device Configuration") {
                    HStack {
                        Text("Device Code")
                        Spacer()
                        Text(deviceCode)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Button("Generate New Device Code") {
                            showingRegenerateAlert = true
                        }
                        .foregroundColor(.blue)
                        
                        Button("Enter Existing Code") {
                            showingDeviceCodeInput = true
                        }
                        .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if isPassphraseVisible {
                                TextField("Passphrase", text: $passphrase)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("Passphrase", text: $passphrase)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button(action: {
                                isPassphraseVisible.toggle()
                            }) {
                                Image(systemName: isPassphraseVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isPassphraseVisible ? "Hide passphrase" : "Show passphrase")
                        }
                        Text("Optional: Additional security for clipboard encryption")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Server Configuration") {
                    HStack {
                        Text("Server URL")
                        TextField("", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: serverURL) { oldValue, newValue in
                                if oldValue == AppSettings.defaultServerURL && newValue != AppSettings.defaultServerURL {
                                    appPassword = ""
                                } else if newValue == AppSettings.defaultServerURL {
                                    appPassword = Bundle.main.object(forInfoDictionaryKey: "API_PASSWORD") as? String ?? ""
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Server Password")
                            
                            if isAppPasswordVisible {
                                TextField("", text: $appPassword)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("", text: $appPassword)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button(action: {
                                isAppPasswordVisible.toggle()
                            }) {
                                Image(systemName: isAppPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isAppPasswordVisible ? "Hide password" : "Show password")
                        }
                        .disabled(serverURL == AppSettings.defaultServerURL)
                        
                        if serverURL != AppSettings.defaultServerURL {
                            Text("Password for your custom server")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Preferences") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .help("Show notifications when clipboard is synced or operations complete")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Slider(value: $pollingInterval, in: 1.0...30.0, step: 0.5) {
                            Text("Polling Interval")
                        } minimumValueLabel: {
                            Text("1s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("30s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("How often to check for new clipboard content from other devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("API Information") {
                    Button("Test Connection") {
                        Task {
                            await testConnection()
                        }
                    }
                    .disabled(viewModel.isLoading)
                    
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing...")
                        }
                    }
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 450, minHeight: 400)
            .navigationTitle("Settings")
            
            // Bottom button bar
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .alert("Generate New Device Code", isPresented: $showingRegenerateAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Generate", role: .confirm) {
                regenerateDeviceCode()
            }
        } message: {
            Text("This will generate a new device code. You will lose access to all existing pastes from this device.")
        }
        .alert("Enter Device Code", isPresented: $showingDeviceCodeInput) {
            TextField("Device Code", text: $newDeviceCode)
                .autocorrectionDisabled()
                .onChange(of: newDeviceCode) { _, newValue in
                    let filtered = String(newValue.uppercased().prefix(8))
                    if filtered != newValue {
                        newDeviceCode = filtered
                    }
                }
            Button("Cancel", role: .cancel) {
                newDeviceCode = ""
            }
            Button("Set Code", role: .confirm) {
                setDeviceCode()
            }
            .disabled(newDeviceCode.count != 8)
        } message: {
            Text("Enter an 8-character device code from another device to link this device.")
        }
        .onAppear {
            // Update state values when the view appears
            deviceCode = viewModel.settings.deviceCode ?? ""
            passphrase = viewModel.settings.passphrase ?? ""
            serverURL = viewModel.settings.serverURL
            appPassword = viewModel.settings.appPassword ?? ""
            notificationsEnabled = viewModel.settings.notificationsEnabled
            pollingInterval = viewModel.pollingInterval
            
            // Notify that settings window is now visible
            viewModel.updateSettingsWindowVisibility(true)
            
            // Focus and bring the settings window to front with delay for window setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focusSettingsWindow()
            }
        }
        .onDisappear {
            // Notify that settings window is no longer visible
            viewModel.updateSettingsWindowVisibility(false)
        }
    }
    
    private func focusSettingsWindow() {
        // Activate the application first
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Multiple strategies to find and focus the settings window
        var settingsWindow: NSWindow?
        
        // Strategy 1: Look for window with "Settings" in title or identifier
        for window in NSApplication.shared.windows {
            if window.isVisible && 
               (window.title.contains("Settings") || 
                window.title.contains("Preferences") ||
                window.identifier?.rawValue.contains("Settings") == true) {
                settingsWindow = window
                break
            }
        }
        
        // Strategy 2: Find the frontmost non-menubar window
        if settingsWindow == nil {
            for window in NSApplication.shared.windows {
                if window.isVisible && 
                   !window.isSheet &&
                   window.level == .normal &&
                   window.canBecomeKey {
                    settingsWindow = window
                    break
                }
            }
        }
        
        // Strategy 3: Use key window as fallback
        if settingsWindow == nil {
            settingsWindow = NSApplication.shared.keyWindow
        }
        
        // Apply aggressive focusing
        if let window = settingsWindow {
            // Use multiple window levels for reliable focusing
            let originalLevel = window.level
            
            // Set to status level temporarily (higher than normal)
            window.level = .statusBar
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            // Also try collectionBehavior for better window management
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // Reset to floating level after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
            }
            
            // Finally reset to normal level
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                window.level = originalLevel
                window.collectionBehavior = []
            }
        } else {
            // Fallback: Try to find any window and force app activation
            NSApplication.shared.unhide(nil)
            NSApplication.shared.arrangeInFront(nil)
        }
    }
    
    private func saveSettings() {
        var updatedSettings = viewModel.settings
        let cleanedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSettings.serverURL = cleanedURL
        
        if cleanedURL == AppSettings.defaultServerURL {
            // Use default password from bundle
            updatedSettings.appPassword = Bundle.main.object(forInfoDictionaryKey: "API_PASSWORD") as? String
        } else {
            // Use user-provided password
            updatedSettings.appPassword = appPassword.isEmpty ? nil : appPassword
        }
        
        updatedSettings.updatePassphrase(passphrase.isEmpty ? nil : passphrase)
        updatedSettings.notificationsEnabled = notificationsEnabled
        updatedSettings.save()
        viewModel.updateSettings(updatedSettings)
        viewModel.setPollingInterval(pollingInterval)
    }
    
    private func regenerateDeviceCode() {
        Task {
            await viewModel.generateDeviceCode()
            if let newCode = viewModel.settings.deviceCode {
                deviceCode = newCode
            }
        }
    }
    
    private func setDeviceCode() {
        Task {
            await viewModel.setDeviceCode(newDeviceCode)
            if let updatedCode = viewModel.settings.deviceCode {
                deviceCode = updatedCode
            }
            newDeviceCode = ""
        }
    }
    
    private func testConnection() async {
        viewModel.errorMessage = nil
        
        let tempClient = BoardAPIClient(
            baseURL: viewModel.settings.serverURL,
            deviceCode: deviceCode,
            appPassword: viewModel.settings.appPassword
        )
        
        do {
            let apiInfo = try await tempClient.getAPIInfo()
            await MainActor.run {
                viewModel.errorMessage = "✅ Connected successfully to: \(apiInfo.message)"
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = "❌ Connection failed: \(error.localizedDescription)"
            }
        }
    }
}

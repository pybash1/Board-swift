//
//  MenuView.swift
//  Board
//
//  Created by Ananjan Mitra on 23/09/25.
//

import SwiftUI
import Foundation

struct MenuView: View {
    @State private var lastPasteURL: String?
    @State private var recentPastes: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Error display
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            
            // Loading indicator
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)
            }
            
            // Last paste actions
            Group {
                Button("Copy Last Paste") {
                    copyLastPaste()
                }
                .disabled(lastPasteURL == nil || isLoading)
                
                Button("View Last Paste") {
                    viewLastPaste()
                }
                .disabled(lastPasteURL == nil)
            }
            
            Divider()
            
            // Paste creation
            Group {
                Button("Paste from Clipboard") {
                    pasteFromClipboard()
                }
                .disabled(isLoading)
                
                Button("Paste from File...") {
                    pasteFromFile()
                }
                .disabled(isLoading)
            }
            
            Divider()
            
            // Recent pastes submenu
            Menu("Recent Pastes") {
                if recentPastes.isEmpty {
                    Text("No recent pastes")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentPastes, id: \.self) { pasteURL in
                        Button(extractPasteID(from: pasteURL)) {
                            Task {
                                await fetchAndCopyPaste(pasteURL)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Settings and quit
            Group {
                SettingsLink {
                    Text("Settings...")
                }
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadRecentPastes()
        }
    }
    
    private func copyLastPaste() {
        guard let url = lastPasteURL else { return }
        Task {
            await fetchAndCopyPaste(url)
        }
    }
    
    private func viewLastPaste() {
        guard let url = lastPasteURL else { return }
        NSWorkspace.shared.open(URL(string: url)!)
    }
    
    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let content = pasteboard.string(forType: .string) {
            Task {
                await createPaste(content: content)
            }
        }
    }
    
    private func pasteFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                Task {
                    await createPaste(content: content)
                }
            } catch {
                Task {
                    await MainActor.run {
                        self.errorMessage = "Error reading file: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    @MainActor
    private func createPaste(content: String) async {
        guard KeychainService.isDeviceSetup() else {
            errorMessage = "Device not set up. Please complete onboarding in Settings."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Get account hash for recipient lookup
            guard let accountMasterKey = try? KeychainService.retrieveAccountMasterKey(),
                  let devicePrivateKey = try? KeychainService.retrieveDevicePrivateKey() else {
                errorMessage = "Failed to retrieve device keys"
                isLoading = false
                return
            }
            
            let accountHash = try CryptoService.generateAccountHash(from: accountMasterKey)
            
            // Create encrypted paste using the high-level API method
            let apiClient = APIClient()
            let pasteResponse = try await apiClient.createEncryptedPaste(content: content, for: accountHash)
            let pasteURL = pasteResponse.url
            
            // Update UI
            lastPasteURL = pasteURL
            recentPastes.insert(pasteURL, at: 0)
            if recentPastes.count > 10 {
                recentPastes.removeLast()
            }
            
            // Save to UserDefaults
            saveRecentPastes()
            
            print("Paste created successfully: \(pasteURL)")
            
        } catch {
            errorMessage = "Failed to create paste: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor 
    private func fetchAndCopyPaste(_ pasteURL: String) async {
        guard KeychainService.isDeviceSetup() else {
            errorMessage = "Device not set up. Please complete onboarding in Settings."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Extract paste ID from URL
            let pasteId = extractPasteID(from: pasteURL)
            
            // Fetch and decrypt using the high-level API method
            let apiClient = APIClient()
            let decryptedContent = try await apiClient.fetchAndDecryptPaste(id: pasteId)
            
            // Copy to clipboard
            copyToClipboard(decryptedContent)
            
            print("Paste fetched and copied to clipboard")
            
        } catch {
            errorMessage = "Failed to fetch paste: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func extractPasteID(from url: String) -> String {
        return URL(string: url)?.lastPathComponent ?? url
    }
    
    private func loadRecentPastes() {
        recentPastes = UserDefaults.standard.stringArray(forKey: "RecentPastes") ?? []
        lastPasteURL = recentPastes.first
    }
    
    private func saveRecentPastes() {
        UserDefaults.standard.set(recentPastes, forKey: "RecentPastes")
    }
}

#Preview {
    MenuView()
}
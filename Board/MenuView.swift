//
//  MenuView.swift
//  Board
//
//  Created by Ananjan Mitra on 23/09/25.
//

import SwiftUI

struct MenuView: View {
    @State private var lastPasteURL: String?
    @State private var recentPastes: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Last paste actions
            Group {
                Button("Copy Last Paste") {
                    copyLastPaste()
                }
                .disabled(lastPasteURL == nil)
                
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
                
                Button("Paste from File...") {
                    pasteFromFile()
                }
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
                            copyToClipboard(pasteURL)
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
    }
    
    private func copyLastPaste() {
        guard let url = lastPasteURL else { return }
        copyToClipboard(url)
    }
    
    private func viewLastPaste() {
        guard let url = lastPasteURL else { return }
        NSWorkspace.shared.open(URL(string: url)!)
    }
    
    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let content = pasteboard.string(forType: .string) {
            createPaste(content: content)
        }
    }
    
    private func pasteFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url)
                createPaste(content: content)
            } catch {
                print("Error reading file: \(error)")
            }
        }
    }
    
    private func createPaste(content: String) {
        // TODO: Implement paste creation with encryption
        print("Creating paste with content: \(content.prefix(50))...")
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func extractPasteID(from url: String) -> String {
        return URL(string: url)?.lastPathComponent ?? url
    }
}

#Preview {
    MenuView()
}
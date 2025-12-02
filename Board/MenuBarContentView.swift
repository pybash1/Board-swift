import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
    @EnvironmentObject var viewModel: BoardViewModel
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Actions
            Button("Copy Last Paste") {
                Task {
                    await viewModel.copyLastPaste()
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(viewModel.pastes.isEmpty)
            
            Button("Paste from Clipboard") {
                Task {
                    await viewModel.pasteFromClipboard()
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            
            Button("Paste from File...") {
                showingFilePicker = true
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            // Recent Pastes Submenu
            if !viewModel.pastes.isEmpty {
                Menu("Recent Pastes") {
                    ForEach(Array(viewModel.pastes.prefix(10).enumerated()), id: \.offset) { index, pasteId in
                        Button("Paste \(index + 1): \(String(pasteId.prefix(8)))...") {
                            Task {
                                await copyPaste(id: pasteId)
                            }
                        }
                    }
                }
                
                Divider()
            }
            
            // Clipboard Monitoring Toggle
            Button(viewModel.isClipboardMonitoringEnabled ? "Disable Auto-Sync" : "Enable Auto-Sync") {
                viewModel.toggleClipboardMonitoring()
            }
            
            Divider()
            
            // Settings and Quit
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button("Quit Board") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.pasteFromFile(url: url)
                    }
                }
            case .failure(let error):
                viewModel.showNotification(title: "File Selection Error", message: error.localizedDescription)
            }
        }
        .task {
            // Always request notification permissions first
            await viewModel.requestInitialNotificationPermission()
            
            // Then initialize if setup is complete
            if viewModel.isSetupComplete {
                await viewModel.initialize()
            }
        }
    }
    
    private func copyPaste(id: String) async {
        do {
            let content = try await viewModel.getPaste(id: id)
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            
            viewModel.showNotification(title: "Copied", message: "Paste copied to clipboard")
        } catch {
            viewModel.showNotification(title: "Failed!", message: "Failed to copy paste: \(error.localizedDescription)")
        }
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(BoardViewModel())
}

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = BoardViewModel()
    @State private var showingSettings = false
    @State private var newPasteContent = ""
    @State private var showingCreatePaste = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if viewModel.isSetupComplete {
                    mainContent
                } else {
                    setupView
                }
            }
            .padding()
            .navigationTitle("Board")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingCreatePaste) {
            CreatePasteView(viewModel: viewModel, content: $newPasteContent)
        }
        .task {
            await viewModel.initialize()
        }
    }
    
    private var setupView: some View {
        VStack(spacing: 20) {
            Text("Welcome to Board")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("You need to set up your device code to get started")
                .multilineTextAlignment(.center)
            
            DeviceCodeSetupView(viewModel: viewModel)
            
            if viewModel.isLoading {
                ProgressView("Setting up...")
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Create Paste") {
                    showingCreatePaste = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Refresh") {
                    Task {
                        await viewModel.loadPastes()
                    }
                }
                .disabled(viewModel.isLoading)
            }
            
            if viewModel.isLoading {
                ProgressView("Loading...")
            } else if viewModel.pastes.isEmpty {
                Text("No pastes yet")
                    .foregroundColor(.secondary)
            } else {
                List(viewModel.pastes, id: \.self) { pasteId in
                    PasteRowView(pasteId: pasteId, viewModel: viewModel)
                }
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
}

struct PasteRowView: View {
    let pasteId: String
    @ObservedObject var viewModel: BoardViewModel
    @State private var pasteContent: String?
    @State private var isLoading = false
    @State private var showingContent = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(pasteId)
                    .font(.headline)
                
                if let content = pasteContent {
                    Text(String(content.prefix(50)) + (content.count > 50 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("View") {
                    showingContent = true
                }
                .buttonStyle(.bordered)
            }
        }
        .onTapGesture {
            if pasteContent == nil && !isLoading {
                loadContent()
            }
        }
        .sheet(isPresented: $showingContent) {
            PasteDetailView(pasteId: pasteId, content: pasteContent ?? "")
        }
    }
    
    private func loadContent() {
        isLoading = true
        Task {
            do {
                let content = try await viewModel.getPaste(id: pasteId)
                await MainActor.run {
                    self.pasteContent = content
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct PasteDetailView: View {
    let pasteId: String
    let content: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(pasteId)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        #if os(macOS)
                        NSPasteboard.general.setString(content, forType: .string)
                        #else
                        UIPasteboard.general.string = content
                        #endif
                    }
                }
            }
        }
    }
}

struct CreatePasteView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var content: String
    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .border(Color.gray.opacity(0.3))
                
                if isCreating {
                    ProgressView("Creating paste...")
                        .padding()
                }
            }
            .padding()
            .navigationTitle("New Paste")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createPaste()
                    }
                    .disabled(content.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createPaste() {
        isCreating = true
        Task {
            do {
                _ = try await viewModel.createPaste(content: content)
                await MainActor.run {
                    content = ""
                    isCreating = false
                    dismiss()
                }
                await viewModel.loadPastes()
            } catch {
                await MainActor.run {
                    isCreating = false
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct DeviceCodeSetupView: View {
    @ObservedObject var viewModel: BoardViewModel
    @State private var enteredDeviceCode = ""
    @State private var setupMode: SetupMode = .generate
    
    enum SetupMode: String, CaseIterable {
        case generate = "Generate New Code"
        case enter = "Enter Existing Code"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Setup Mode", selection: $setupMode) {
                ForEach(SetupMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            switch setupMode {
            case .generate:
                generateModeView
            case .enter:
                enterModeView
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var generateModeView: some View {
        VStack(spacing: 12) {
            Text("Generate a new device code for this device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Generate Device Code") {
                Task {
                    await viewModel.generateDeviceCode()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
    }
    
    private var enterModeView: some View {
        VStack(spacing: 12) {
            Text("Enter an existing device code from another device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("Device Code (8 characters)", text: $enteredDeviceCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .onChange(of: enteredDeviceCode) { _, newValue in
                    // Limit to 8 characters and uppercase
                    let filtered = String(newValue.uppercased().prefix(8))
                    if filtered != newValue {
                        enteredDeviceCode = filtered
                    }
                }
            
            Button("Use This Device Code") {
                Task {
                    await viewModel.setDeviceCode(enteredDeviceCode)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading || enteredDeviceCode.count != 8)
        }
    }
}

#Preview {
    ContentView()
}

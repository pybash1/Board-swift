//
//  SettingsView.swift
//  Board
//
//  Created by Ananjan Mitra on 23/09/25.
//

import SwiftUI
import Foundation
import CryptoKit

struct SettingsView: View {
    @State private var hasAccount = false
    @State private var accountHash = ""
    @State private var deviceFingerprint = ""
    @State private var showingLinkDevice = false
    @State private var masterKeyInput = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    private let apiClient = APIClient()
    
    var body: some View {
        VStack(spacing: 20) {
            if hasAccount {
                // Main settings view for existing account
                VStack(alignment: .leading, spacing: 15) {
                    Text("Board Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Account info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account Information")
                            .font(.headline)
                        
                        HStack {
                            Text("Account Hash:")
                            Text(accountHash.isEmpty ? "Loading..." : String(accountHash.prefix(16)) + "...")
                                .foregroundColor(.secondary)
                                .font(.monospaced(.body)())
                        }
                        
                        HStack {
                            Text("Device ID:")
                            Text(deviceFingerprint.isEmpty ? "Loading..." : deviceFingerprint)
                                .foregroundColor(.secondary)
                                .font(.monospaced(.body)())
                        }
                    }
                    
                    Divider()
                    
                    // Device management
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Device Management")
                            .font(.headline)
                        
                        Button("Link Another Device") {
                            showingLinkDevice = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("View Connected Devices") {
                            Task {
                                await fetchConnectedDevices()
                }
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            } else {
                // Onboarding view
                OnboardingView(hasAccount: $hasAccount)
            }
        }
        .padding(20)
        .frame(width: 400, height: hasAccount ? 300 : 250)
        .onAppear {
            Task {
                await checkForExistingAccount()
            }
        }
        .sheet(isPresented: $showingLinkDevice) {
            LinkDeviceView()
        }
    }
    
    private func checkForExistingAccount() async {
        do {
            if KeychainService.isDeviceSetup() {
                accountHash = try KeychainService.retrieveAccountHash()
                deviceFingerprint = try KeychainService.retrieveDeviceCode()
                hasAccount = true
            } else {
                hasAccount = false
            }
        } catch {
            print("Error checking account: \(error)")
            hasAccount = false
            errorMessage = "Error loading account information"
        }
    }
    
    private func fetchConnectedDevices() async {
        do {
            let accountHashString = try KeychainService.retrieveAccountHash()
            let deviceKeys = try await apiClient.fetchKeys(for: accountHashString)
            print("Found \(deviceKeys.keys.count) connected devices")
        } catch {
            errorMessage = "Failed to fetch connected devices: \(error.localizedDescription)"
        }
    }
}

struct OnboardingView: View {
    @Binding var hasAccount: Bool
    @State private var showingLinkInput = false
    @State private var masterKeyInput = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    private let apiClient = APIClient()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Board")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Secure clipboard syncing across all your devices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                Button("Create New Account") {
                    Task {
                        await createNewAccount()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading)
                
                Button("Link Existing Account") {
                    showingLinkInput = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isLoading)
            }
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .sheet(isPresented: $showingLinkInput) {
            VStack(spacing: 15) {
                Text("Link Existing Account")
                    .font(.headline)
                
                Text("Enter your account master key from another device:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Master Key", text: $masterKeyInput)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Cancel") {
                        showingLinkInput = false
                        masterKeyInput = ""
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Link") {
                        Task {
                            await linkExistingAccount()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(masterKeyInput.isEmpty || isLoading)
                }
            }
            .padding(20)
            .frame(width: 350, height: 200)
        }
    }
    
    private func createNewAccount() async {
        isLoading = true
        errorMessage = ""
        
        do {
            let _ = try CryptoService.setupNewDevice()
            try await apiClient.registerDevice()
            
            hasAccount = true
        } catch {
            print("Error creating account: \(error)")
            errorMessage = "Failed to create account: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func linkExistingAccount() async {
        isLoading = true
        errorMessage = ""
        
        do {
            guard let masterKeyData = Data(base64Encoded: masterKeyInput) else {
                errorMessage = "Invalid master key format"
                isLoading = false
                return
            }
            
            // Store the master key first
            let masterKey = SymmetricKey(data: masterKeyData)
            try KeychainService.storeAccountMasterKey(masterKey)
            
            // Generate account hash and setup device
            let accountHash = try CryptoService.generateAccountHash(from: masterKey)
            let _ = try CryptoService.linkExistingDevice(accountHash: accountHash)
            try await apiClient.registerDevice()
            
            showingLinkInput = false
            masterKeyInput = ""
            hasAccount = true
        } catch {
            print("Error linking account: \(error)")
            errorMessage = "Failed to link account: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct LinkDeviceView: View {
    @State private var masterKey = "Loading..."
    @State private var errorMessage = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Link Another Device")
                .font(.headline)
            
            Text("Scan this QR code or copy the key on your new device:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // TODO: Generate QR code
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 200)
                .overlay(
                    Text("QR Code\n(Coming Soon)")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                )
            
            VStack(spacing: 8) {
                Text("Or copy this key:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(masterKey)
                    .font(.monospaced(.caption)())
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(masterKey, forType: .string)
                    }
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 400, height: 350)
        .onAppear {
            Task {
                await loadMasterKey()
            }
        }
    }
    
    private func loadMasterKey() async {
        do {
            let masterKeySymmetric = try KeychainService.retrieveAccountMasterKey()
            masterKey = masterKeySymmetric.withUnsafeBytes { Data($0) }.base64EncodedString()
        } catch {
            errorMessage = "Failed to load master key: \(error.localizedDescription)"
            masterKey = "Error loading key"
        }
    }
}

#Preview {
    SettingsView()
}
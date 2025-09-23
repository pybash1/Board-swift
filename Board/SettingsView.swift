//
//  SettingsView.swift
//  Board
//
//  Created by Ananjan Mitra on 23/09/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var hasAccount = false
    @State private var accountHash = ""
    @State private var deviceFingerprint = ""
    @State private var showingLinkDevice = false
    @State private var masterKeyInput = ""
    
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
                            Text(accountHash.isEmpty ? "Loading..." : accountHash)
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
                            // TODO: Show connected devices
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                // Onboarding view
                OnboardingView(hasAccount: $hasAccount)
            }
        }
        .padding(20)
        .frame(width: 400, height: hasAccount ? 300 : 250)
        .onAppear {
            checkForExistingAccount()
        }
        .sheet(isPresented: $showingLinkDevice) {
            LinkDeviceView()
        }
    }
    
    private func checkForExistingAccount() {
        // TODO: Check Keychain for existing account
        // For now, assume no account
        hasAccount = false
    }
}

struct OnboardingView: View {
    @Binding var hasAccount: Bool
    @State private var showingLinkInput = false
    @State private var masterKeyInput = ""
    
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
                    createNewAccount()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Link Existing Account") {
                    showingLinkInput = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
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
                        linkExistingAccount()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(masterKeyInput.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 350, height: 200)
        }
    }
    
    private func createNewAccount() {
        // TODO: Generate new master key and device keys
        print("Creating new account...")
        hasAccount = true
    }
    
    private func linkExistingAccount() {
        // TODO: Import master key and generate device keys
        print("Linking existing account with key: \(masterKeyInput)")
        showingLinkInput = false
        masterKeyInput = ""
        hasAccount = true
    }
}

struct LinkDeviceView: View {
    @State private var masterKey = "Loading..."
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
        }
        .padding(20)
        .frame(width: 400, height: 350)
        .onAppear {
            loadMasterKey()
        }
    }
    
    private func loadMasterKey() {
        // TODO: Load actual master key from Keychain
        masterKey = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789=="
    }
}

#Preview {
    SettingsView()
}
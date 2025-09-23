# Bin Client Development Guide: macOS (Swift)

This document provides specific implementation details for building a `bin` client on macOS, intended to be a menu bar application.

**An LLM agent MUST read the `API_DOCS_COMMON.md` document before this one.** This guide assumes full understanding of the core cryptographic and API concepts.

## 1. Project Setup & Dependencies

- **Technology**: Swift, SwiftUI (for settings), AppKit.
- **Application Type**: A menu bar extra app (`NSStatusItem`). The main interface will be an `NSMenu`.
- **Core Dependencies**:
    - **Crypto**: `CryptoKit` (for ChaChaPoly, Secure Enclave), and a third-party library for Curve25519 operations (X25519, Ed25519) and BLAKE3. A recommended choice is `swift-crypto` maintained by Apple. For BLAKE3, a package like `BLAKE3.swift` can be used.
    - **Networking**: `URLSession` for making API calls.
    - **Data Management**: `Codable` for JSON serialization/deserialization.

### Recommended Libraries:

- **`swift-crypto`**: Provides implementations of Ed25519, X25519, and other primitives not found in `CryptoKit`.
- **`BLAKE3.swift`**: For the BLAKE3 hashing function.

## 2. Secure Storage

Security is paramount. All cryptographic keys **MUST** be stored in the macOS Keychain.

- **Account Master Key**:
    - **Storage**: Store as a `Generic Password` item in the Keychain.
    - **Service**: `com.yourcompany.bin.accountmasterkey`
    - **Account**: The user's account identifier (e.g., a username or a fixed string like `default`).
    - **Accessibility**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. This ensures the key is only available on this Mac and only when the user is logged in. It does not sync to iCloud Keychain.

- **Device Private Keys**:
    - **Storage**: Store the serialized `DevicePrivateKeys` struct (as `Data`) as another `Generic Password`.
    - **Service**: `com.yourcompany.bin.deviceprivatekeys`
    - **Account**: The device's 8-character fingerprint.
    - **Accessibility**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

- **Keychain Wrapper**: It is highly recommended to create a `KeychainService` wrapper class to abstract away the complexities of `SecItemAdd`, `SecItemCopyMatching`, etc. This service should have methods like:
    - `saveAccountMasterKey(key: Data)`
    - `getAccountMasterKey() -> Data?`
    - `saveDeviceKeys(keys: DevicePrivateKeys, for fingerprint: String)`
    - `getDeviceKeys(for fingerprint: String) -> DevicePrivateKeys?`

## 3. Application Architecture (Menu Bar App)

The app will live in the system menu bar.

### 3.1. `AppDelegate` or `@main` App Struct

- Initialize the `NSStatusItem` in the menu bar.
- Assign an `NSMenu` to the status item.
- The menu will be the primary user interface.

### 3.2. Menu Structure

The `NSMenu` should contain the following items:

- **`Copy Last Paste`**: Copies the URL of the most recently created paste to the clipboard. (Disabled if none).
- **`View Last Paste`**: Opens the URL of the most recently created paste in the default browser. (Disabled if none).
- **--- (Separator) ---**
- **`Paste from Clipboard`**:
    - Takes the current content of the clipboard (`NSPasteboard`).
    - If the content is text, it triggers the "Create Paste" workflow.
- **`Paste from File...`**:
    - Opens an `NSOpenPanel` to allow the user to select a file.
    - Reads the file content and triggers the "Create Paste" workflow.
- **--- (Separator) ---**
- **`Recent Pastes` (Submenu)**:
    - A dynamically populated list of the last 5-10 pastes created by this device.
    - Each item should show the paste ID (e.g., `cateettary`) and, on click, copy the URL to the clipboard.
- **--- (Separator) ---**
- **`Settings...`**: Opens the settings window.
- **`Quit`**: Terminates the application.

### 3.3. Settings Window (`SwiftUI`)

A simple SwiftUI view hosted in an `NSWindow`.

- **Onboarding View**:
    - If no `AccountMasterKey` is found in the Keychain, this view is shown.
    - It should present two options:
        1.  **`Create New Account`**: Generates a new `AccountMasterKey` and proceeds with the first device setup.
        2.  **`Link Existing Account`**: Shows a text field to paste the Account Master Key string from another device.
- **Main Settings View**:
    - **`Account Info`**:
        - Displays the `account_hash` and the current device's `fingerprint`.
    - **`Link Another Device`**:
        - A button that, when clicked, retrieves the `AccountMasterKey` from the Keychain and displays it as a QR code and a copyable string. **This view should be protected and warn the user about the sensitivity of this key.**
    - **`Device List`**:
        - Fetches and displays the fingerprints of all devices linked to the account.

## 4. Core Workflows in Swift

### 4.1. Onboarding (`SettingsViewModel`)

```swift
class SettingsViewModel: ObservableObject {
    private var keychainService = KeychainService()

    func setupNewAccount() {
        // 1. Generate AccountMasterKey (32 random bytes)
        let masterKey = generateRandomBytes(count: 32)
        try keychainService.saveAccountMasterKey(key: masterKey)

        // 2. Trigger device key generation and registration
        registerDevice(with: masterKey)
    }

    func linkDevice(masterKeyString: String) {
        // 1. Decode the Base64 master key string to Data
        guard let masterKey = Data(base64Encoded: masterKeyString) else { /* show error */ return }
        try keychainService.saveAccountMasterKey(key: masterKey)

        // 2. Trigger device key generation and registration
        registerDevice(with: masterKey)
    }

    private func registerDevice(with masterKey: Data) {
        // Follow steps from API_DOCS_COMMON.md:
        // 1. Generate all device private keys (Ed25519, X25519) using swift-crypto
        // 2. Store them in Keychain associated with the new fingerprint
        // 3. Generate the public X3DHKeyBundle
        // 4. Generate the device fingerprint from the public Ed25519 key using BLAKE3.swift
        // 5. Calculate account_hash from masterKey using BLAKE3.swift
        // 6. Construct PublicKeyInfo object
        // 7. POST to /keys
    }
}
```

### 4.2. Creating a Paste (`PasteViewModel`)

This logic is triggered by the "Paste from Clipboard" or "Paste from File" menu actions.

```swift
class PasteViewModel {
    private var apiClient = APIClient()
    private var cryptoService = CryptoService() // Wrapper for all crypto operations

    func createPaste(content: String) async {
        // 1. Get user's account_hash
        let accountHash = await cryptoService.getAccountHash()

        // 2. Fetch all recipient public key bundles from the server
        let recipientBundles = await apiClient.getPublicKeys(for: accountHash)

        // 3. Encrypt the paste content using the E2EE workflow
        // This is the most complex part. The cryptoService should implement the
        // full "Encrypting and Sending a Paste" workflow from API_DOCS_COMMON.md.
        guard let encryptedPayload = await cryptoService.encryptForX3DH(
            content: content.data(using: .utf8)!,
            recipients: recipientBundles
        ) else { /* handle error */ return }

        // `encryptedPayload` should be a struct containing the final binary data
        // and the list of initial messages.

        // 4. Construct the EncryptedPastePost JSON object
        let postBody = EncryptedPastePost(
            content: encryptedPayload.finalData.base64EncodedString(),
            x3dh_initial_messages: encryptedPayload.initialMessages
        )

        // 5. POST to /pastes/new
        let pasteURL = await apiClient.createEncryptedPaste(body: postBody)

        // 6. Store the pasteURL for "Recent Pastes" and copy to clipboard
        //    - Use UserDefaults for recent pastes list.
        //    - Use NSPasteboard.general.setString(pasteURL, forType: .string)
    }
}
```

### 4.3. Clipboard Integration

- Use `NSPasteboard.general` to get and set clipboard content.
- A background task or timer could be used to monitor clipboard changes for a "quick paste" feature, but this should be an optional setting due to privacy implications.

## 5. Networking Layer (`APIClient`)

Create a dedicated class for handling all `URLSession` tasks.

- **Methods**:
    - `getPublicKeys(for accountHash: String) async -> [PublicKeyInfo]`
    - `createEncryptedPaste(body: EncryptedPastePost) async -> String?`
    - `registerDevice(body: PublicKeyInfo) async -> Bool`
- **Headers**: Ensure every request includes the `Device-Code` (retrieved from Keychain/UserDefaults) and a proper `User-Agent`.
- **Error Handling**: The client should handle network errors, server errors (e.g., 4xx, 5xx status codes), and JSON parsing errors gracefully.

## 6. Final Polish

- **App Icon**: A custom icon for the menu bar status item. It should support both light and dark mode appearances.
- **User Notifications**: Use `UNUserNotificationCenter` to notify the user when a paste has been successfully created and its URL copied to the clipboard.
- **Sandboxing**: Ensure the app is properly sandboxed and requests the necessary entitlements (e.g., network access).
- **Code Signing & Notarization**: The final app must be code-signed and notarized to run on modern macOS without security warnings.

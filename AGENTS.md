# Board - E2E Encrypted Clipboard Sync App

## App Overview
Board is a menubar-based application for syncing device clipboard across macOS, iOS, Android, Windows, and Linux using end-to-end encryption (X3DH protocol). All clipboard data is encrypted locally before being sent to the server.

## Build Commands
- **Build**: `xcodebuild -project Board.xcodeproj -scheme Board -configuration Debug build`
- **Run iOS Simulator**: `xcodebuild -project Board.xcodeproj -scheme Board -destination 'platform=iOS Simulator,name=iPhone 15' build`
- **Run macOS**: `xcodebuild -project Board.xcodeproj -scheme Board -destination 'platform=macOS' build`
- **Test**: `xcodebuild -project Board.xcodeproj -scheme Board -destination 'platform=iOS Simulator,name=iPhone 15' test`
- **Single test**: `xcodebuild test -project Board.xcodeproj -scheme Board -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BoardTests/TestClassName/testMethodName`

## Code Style Guidelines
- **Imports**: Use `import SwiftUI`, `import Foundation`, `import CryptoKit`, `import Crypto` at top of file
- **Naming**: PascalCase for types/structs, camelCase for variables/functions
- **Types**: Use explicit types when needed, prefer type inference otherwise
- **Error Handling**: Use `do-catch` blocks, `throws` functions, and `Result` type
- **Formatting**: 4-space indentation, opening braces on same line
- **Comments**: Use `//` for single line, `/* */` for multi-line, include file headers
- **SwiftUI**: Use declarative syntax, prefer `@State`, `@Binding`, `@ObservedObject`
- **Concurrency**: Use `async/await`, `@MainActor` for UI updates
- **Security**: All cryptographic keys MUST be stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

## Dependencies & Cryptography
- **CryptoKit**: For ChaCha20-Poly1305 encryption and secure random generation
- **swift-crypto**: For X25519 key agreement and Ed25519 signatures
- **BLAKE3.swift**: For BLAKE3 hashing and key derivation
- **URLSession**: For API networking with required headers (`Device-Code`, `User-Agent`)

## API Integration
- **Base URL**: `http://127.0.0.1:8820` (self-hosted service)
- **Key Endpoints**: 
  - `POST /keys` (device registration)
  - `GET /keys/{account_hash}` (fetch recipient keys)
  - `POST /pastes/new` (create encrypted paste)
  - `GET /{paste_id}` (retrieve paste)
- **Headers**: Always include 8-character `Device-Code` fingerprint and non-browser `User-Agent`

## App Architecture (macOS)
- **Type**: NSStatusItem menubar application with NSMenu interface
- **Menu Items**: Copy/view last paste, paste from clipboard/file, recent pastes submenu, settings, quit
- **Settings**: SwiftUI window for onboarding (new account vs link existing device) and device management
- **Security**: Account Master Key and Device Private Keys stored in Keychain, never in UserDefaults

## Project Structure
- Main target: `Board`
- Bundle ID: `xyz.pybash.Board`
- Swift 5.0, Xcode 26.0+
- Multi-platform: iPhone, iPad, Mac, Apple Vision Pro
# Bin Client Development Guide: Common API & Cryptography

This document provides the core technical details required to build a client for the `bin` service. It covers the API endpoints, cryptographic operations, and data structures that are common across all platforms.

**An LLM agent MUST read this document in its entirety before consulting any platform-specific guides.**

## 1. Core Concepts

- **Account**: A logical grouping of devices that can share encrypted pastes. An account is defined by a shared **Account Master Key**. There is no server-side account registration; the account exists implicitly through the keys held by the clients.
- **Device**: A single client instance (e.g., a phone, a laptop). Each device has its own unique set of cryptographic keys.
- **Device Fingerprint**: A unique identifier for a device, derived from its public identity key. It is an 8-character alphanumeric string.
- **Paste**: A snippet of text. Pastes can be public (unencrypted, accessible to anyone with the link) or private (end-to-end encrypted, accessible only to devices within the same account).
- **End-to-End Encryption (E2EE)**: Implemented using the **X3DH (Extended Triple Diffie-Hellman)** protocol. This ensures that only the user's devices can decrypt their private pastes. The server only stores encrypted data.

## 2. Cryptographic Dependencies & Primitives

A client **MUST** implement or use libraries that provide the following cryptographic primitives. The reference implementation uses Rust crates, which are listed for clarity.

| Primitive | Rust Crate | Description |
|---|---|---|
| **X25519** | `x25519-dalek` | Key agreement protocol (Diffie-Hellman). Used for all DH operations in X3DH. |
| **Ed25519** | `ed25519-dalek` | Digital signature algorithm. Used for signing device identity and pre-keys. |
| **ChaCha20-Poly1305** | `chacha20poly1305` | Authenticated Encryption with Associated Data (AEAD) cipher. Used for encrypting paste content and X3DH initial messages. |
| **BLAKE3** | `blake3` | Cryptographic hash function. Used as the Key Derivation Function (KDF) in X3DH. |
| **Base64** | `base64` | For encoding binary key data into JSON strings. Standard encoding is required. |
| **Randomness** | `rand_core` | A cryptographically secure random number generator (CSPRNG) is essential for key generation. |

## 3. Device Onboarding & Key Management

This is the most critical part of the client implementation. All keys must be generated and stored securely on the device.

### 3.1. First Device Setup (New Account)

This flow is for when a user installs the client for the first time.

1.  **Generate Account Master Key**:
    - Generate 32 bytes of random data. This is the `AccountMasterKey`.
    - **This key is the root of the user's identity. It MUST be stored in the most secure storage available on the platform (e.g., Keychain, Keystore). If this key is lost, the account is irrecoverable.**

2.  **Generate Device Keys**:
    - **Ed25519 Identity Key**: Generate an `ed25519_dalek::SigningKey`. This is the long-term identity key for the device.
    - **X25519 Identity Key**: Generate an `x25519_dalek::StaticSecret`.
    - **X25519 Signed Pre-key**: Generate an `x25519_dalek::StaticSecret`.
    - **X25519 One-Time Pre-keys**: Generate a list (e.g., 10) of `x25519_dalek::StaticSecret` keys.

3.  **Store Private Keys**:
    - All the secret keys generated in step 2 form the `DevicePrivateKeys` structure.
    - This structure **MUST** be stored securely on the device, associated with the device's fingerprint.

4.  **Generate Public Key Bundle (`X3DHKeyBundle`)**:
    - Derive the public keys from the private keys generated in step 2.
    - **Sign the Signed Pre-key**: The public part of the signed pre-key must be signed using the Ed25519 identity key.
    - The `X3DHKeyBundle` contains:
        - `identity_key_ed25519` (public)
        - `identity_key_x25519` (public)
        - `signed_prekey` (public)
        - `prekey_signature` (the signature from the previous step)
        - `one_time_prekeys` (a list of public keys)

5.  **Generate Device Fingerprint**:
    - Take the public Ed25519 identity key bytes.
    - Hash them using BLAKE3.
    - Take the first 8 bytes of the hash and encode them into an alphanumeric string (A-Z, 0-9). This is the `Device-Code` header value.

6.  **Register with the Server**:
    - Construct a `PublicKeyInfo` JSON object:
      ```json
      {
        "account_hash": "string",
        "device_fingerprint": "string",
        "x3dh_bundle": { /* X3DHKeyBundle object */ }
      }
      ```
    - `account_hash`: BLAKE3 hash of the `AccountMasterKey`, encoded as a hex string.
    - `device_fingerprint`: The fingerprint generated in step 5.
    - `x3dh_bundle`: The public bundle from step 4, with all binary data Base64 encoded.
    - Send this object via `POST /keys` to the server.

### 3.2. Linking a New Device

This flow is for adding a second or subsequent device to an existing account.

1.  **Export Account Master Key**:
    - On an existing, authenticated device, the user must initiate a "link device" action.
    - This action should display the 32-byte `AccountMasterKey` as a QR code or a Base64 string.

2.  **Import Account Master Key**:
    - On the new device, the user scans the QR code or pastes the string to import the `AccountMasterKey`.
    - The new device **MUST NOT** generate a new master key.

3.  **Follow First Device Setup**:
    - From this point, the new device follows steps 2-6 from the "First Device Setup" section. It generates its own unique set of device keys but uses the *imported* `AccountMasterKey` to calculate the `account_hash`.

## 4. API Endpoints

**Base URL**: The service can be self-hosted. The default is `http://127.0.0.1:8820`.

**Required Headers**:
- `Device-Code`: The 8-character device fingerprint. This is required for almost all endpoints.
- `User-Agent`: Should be set to a non-browser-like string to receive raw data instead of HTML. E.g., `BinClient/1.0`.

---

### `POST /`

Creates a paste from form data. This is mainly for browser interaction and is **not recommended for clients**. Clients should use `PUT /`.

---

### `PUT /`

Creates a simple, unencrypted, public paste.

- **Method**: `PUT`
- **Headers**:
    - `Content-Type`: `text/plain`
- **Body**: The raw text content of the paste.
- **Success Response (200 OK)**:
    - **Body**: The full URL to the newly created paste (e.g., `https://bin.gy/pasteid`).

---

### `GET /{paste_id}`

Retrieves a paste.

- **Method**: `GET`
- **Headers**:
    - `Device-Code`: **Required** if the paste is encrypted.
- **Success Response (200 OK)**:
    - **Body**: If the paste is public or successfully decrypted, the body contains the raw text content.
    - **If the paste is encrypted**, the server returns a JSON object of type `EncryptedPaste`. The client must then perform decryption.
      ```json
      {
        "content": "Base64-encoded encrypted data",
        "x3dh_initial_messages": [
          ["device_fingerprint_1", { /* X3DHInitialMessage object */ }],
          ["device_fingerprint_2", { /* X3DHInitialMessage object */ }]
        ],
        "is_x3dh_encrypted": true
      }
      ```

---

### `POST /pastes/new`

Creates a private, end-to-end encrypted paste. This is the primary endpoint for creating shared pastes.

- **Method**: `POST`
- **Headers**:
    - `Content-Type`: `application/json`
    - `Device-Code`: The fingerprint of the sending device.
- **Body**: A JSON object of type `EncryptedPastePost`.
  ```json
  {
    "content": "Base64-encoded encrypted data",
    "x3dh_initial_messages": [
      ["recipient_device_fingerprint_1", { /* X3DHInitialMessage object */ }],
      ["recipient_device_fingerprint_2", { /* X3DHInitialMessage object */ }]
    ]
  }
  ```
- **Success Response (200 OK)**:
    - **Body**: The full URL to the newly created paste.

---

### `POST /keys`

Registers a device's public keys with the server. This is used during device setup.

- **Method**: `POST`
- **Headers**:
    - `Content-Type`: `application/json`
- **Body**: A `PublicKeyInfo` JSON object (see section 3.1, step 6).
- **Success Response (200 OK)**:
    - **Body**: A confirmation JSON: `{"status": "ok"}`.

---

### `GET /keys/{account_hash}`

Retrieves the public key bundles for all devices associated with an account.

- **Method**: `GET`
- **Headers**:
    - `Device-Code`: The fingerprint of the requesting device.
- **URL Parameters**:
    - `account_hash`: The hex-encoded BLAKE3 hash of the `AccountMasterKey`.
- **Success Response (200 OK)**:
    - **Body**: A JSON array of `PublicKeyInfo` objects.

## 5. E2EE Workflow: Step-by-Step

### 5.1. Encrypting and Sending a Paste

1.  **Fetch Recipient Keys**:
    - Calculate the `account_hash` from the `AccountMasterKey`.
    - Call `GET /keys/{account_hash}` to get the `X3DHKeyBundle` for all devices in the account (including the sender's own device).

2.  **Generate Content Encryption Key (CEK)**:
    - Generate a new, random 32-byte key. This key will be used to encrypt the paste content itself.

3.  **Encrypt Paste Content**:
    - Encrypt the raw paste text using the CEK with the ChaCha20-Poly1305 AEAD cipher. This produces the `encrypted_content`.

4.  **Perform X3DH for Each Recipient**:
    - For each recipient device (including the sender's own device) from the list fetched in step 1:
        - **Initiate an X3DH session**: Use the sender's private identity keys and the recipient's public `X3DHKeyBundle` to establish a shared secret. This is the `X3DHSession::initiate()` function in the reference implementation.
        - This process generates a `shared_secret` and an `X3DHInitialMessage`. The initial message contains the sender's ephemeral key and the encrypted sender identity, which the recipient needs to derive the same shared secret.
        - **Encrypt the CEK**: Use the `shared_secret` to encrypt the CEK (from step 2) for this specific recipient.
        - The result of this is a per-recipient `encrypted_key_data` blob.

5.  **Construct the Final Payload**:
    - The final `content` payload sent to the server is a single binary blob constructed as follows:
      `[nonce (12 bytes)] [num_devices (4 bytes, u32_le)] [device_1_key_blob] [device_2_key_blob] ... [encrypted_content]`
      - `nonce`: The nonce used to encrypt the paste content in step 3.
      - `num_devices`: The total number of devices the paste is encrypted for.
      - `device_n_key_blob`: A variable-length blob for each device: `[key_data_size (4 bytes, u32_le)] [encrypted_key_data]`.
      - `encrypted_content`: The output from step 3.

6.  **Send to Server**:
    - Base64 encode the final payload from step 5.
    - Create the `EncryptedPastePost` JSON object. The `x3dh_initial_messages` field is an array of `[fingerprint, X3DHInitialMessage]` tuples, one for each recipient.
    - `POST` this JSON to `/pastes/new`.

### 5.2. Receiving and Decrypting a Paste

1.  **Fetch Encrypted Paste**:
    - A client can be notified of a new paste via a push notification (if implemented) or by polling.
    - Call `GET /{paste_id}`. The server will return the `EncryptedPaste` JSON object.

2.  **Find Device-Specific Data**:
    - From the `x3dh_initial_messages` array, find the entry corresponding to the current device's fingerprint. This provides the `X3DHInitialMessage` needed for this device.

3.  **Re-establish X3DH Session**:
    - Use the current device's private keys and the received `X3DHInitialMessage` to derive the same `shared_secret` that the sender generated. This is the `X3DHSession::accept()` function in the reference implementation.

4.  **Decrypt the Content Encryption Key (CEK)**:
    - Decode the Base64 `content` from the server response.
    - Parse the binary blob to find the `encrypted_key_data` for the current device (this requires knowing the device's index in the list, which should be consistent with the order from the `GET /keys` call).
    - Use the `shared_secret` from step 3 to decrypt the `encrypted_key_data`. This reveals the original CEK.

5.  **Decrypt the Paste Content**:
    - Parse the binary blob to extract the main `encrypted_content` and its `nonce`.
    - Use the decrypted CEK and the nonce to decrypt the `encrypted_content` using ChaCha20-Poly1305.
    - The result is the original plaintext of the paste.

## 6. Data Structures (JSON & Binary)

### `X3DHKeyBundle` (JSON, values are Base64 encoded)

```json
{
  "identity_key_ed25519": "string",
  "identity_key_x25519": "string",
  "signed_prekey": "string",
  "prekey_signature": "string",
  "one_time_prekeys": ["string", "string", ...]
}
```

### `X3DHInitialMessage` (JSON, values are Base64 encoded)

```json
{
  "sender_identity_key_x25519": "string",
  "ephemeral_key": "string",
  "used_one_time_prekey": "string" | null,
  "nonce": "string",
  "ciphertext": "string"
}
```

### `PublicKeyInfo` (JSON)

```json
{
  "account_hash": "string",
  "device_fingerprint": "string",
  "x3dh_bundle": { /* X3DHKeyBundle object */ }
}
```

### `EncryptedPastePost` (JSON, for `POST /pastes/new`)

```json
{
  "content": "Base64-encoded final payload",
  "x3dh_initial_messages": [
    ["fingerprint1", { /* X3DHInitialMessage object */ }],
    ["fingerprint2", { /* X3DHInitialMessage object */ }]
  ]
}
```

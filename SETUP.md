# ReceiptScanner — Setup & Integration Guide

## Project Overview

A production-ready iOS receipt scanning app built with:
- **Swift / SwiftUI / MVVM**
- **iOS 16+** · async/await throughout
- **Pluggable AI pipeline** (OpenAI Vision, Gemini Vision, Apple OCR + LLM)
- **Google Sheets + Drive** integration via OAuth2 + PKCE

---

## Directory Structure

```
ReceiptScanner/
├── ReceiptScanner.xcodeproj/
└── ReceiptScanner/
    ├── App/
    │   ├── ReceiptScannerApp.swift     # @main entry point
    │   └── RootView.swift              # TabView root navigation
    ├── Config/
    │   ├── AppConfig.swift             # Loads Config.plist → strongly-typed config
    │   ├── AppSettings.swift           # UserDefaults-backed runtime settings
    │   └── Config.plist.template       # Copy → Config.plist, fill in your keys
    ├── Keychain/
    │   └── KeychainService.swift       # Type-safe Keychain CRUD wrapper
    ├── Models/
    │   ├── Receipt.swift               # Domain model + validation + AIReceiptResponse
    │   └── AppError.swift              # Unified error type with user-facing messages
    ├── Services/
    │   ├── AI/
    │   │   ├── AIService.swift         # Protocol + factory + shared prompt templates
    │   │   ├── OpenAIVisionService.swift  # Mode A: OpenAI gpt-4o vision
    │   │   ├── GeminiVisionService.swift  # Mode B: Gemini 1.5 Flash vision
    │   │   ├── OCRService.swift           # Apple Vision OCR + perspective correction
    │   │   └── OCRPlusLLMService.swift    # Mode C: OCR → OpenAI or Gemini text
    │   └── Google/
    │       ├── GoogleAuthService.swift    # OAuth2 PKCE flow + token refresh
    │       ├── GoogleDriveService.swift   # Multipart image upload
    │       └── GoogleSheetsService.swift  # Append rows + header bootstrap
    ├── Camera/
    │   ├── CameraManager.swift         # AVCaptureSession lifecycle + photo capture
    │   └── CameraPreviewView.swift     # UIViewRepresentable preview
    ├── ViewModels/
    │   └── CameraViewModel.swift       # Pipeline coordinator (capture→AI→submit)
    ├── Views/
    │   ├── Camera/
    │   │   ├── CameraView.swift        # Viewfinder UI, controls, tap-to-focus
    │   │   └── MainFlowView.swift      # Stage-driven flow router
    │   ├── Receipt/
    │   │   ├── ReceiptEditView.swift   # Editable form for AI-extracted data
    │   │   └── HistoryView.swift       # Searchable receipt history
    │   ├── Analytics/
    │   │   └── AnalyticsView.swift     # Monthly charts, top merchants
    │   └── Shared/
    │       ├── LoadingOverlay.swift    # Loading, success, error overlays
    │       └── SettingsView.swift      # API keys, provider switch, Google auth
    ├── Offline/
    │   └── OfflineQueueManager.swift   # JSON queue in Documents/
    └── Utils/
        ├── CategoryClassifier.swift    # Keyword-based category tagging
        ├── DuplicateDetector.swift     # dHash perceptual image dedup
        └── AnalyticsStore.swift        # Local analytics persistence
```

---

## Step 1: Create the Xcode Project

1. Open Xcode → **File → New → Project → iOS → App**
2. Product Name: `ReceiptScanner`
3. Interface: **SwiftUI**
4. Language: **Swift**
5. Lifecycle: **SwiftUI App**
6. Minimum Deployment: **iOS 16.0**
7. Save to the root folder (same level as `ReceiptScanner/` directory)

---

## Step 2: Add Swift Files

Drag all `.swift` files from each subfolder into the Xcode project navigator, ensuring:
- All files belong to the `ReceiptScanner` target
- "Copy items if needed" is **unchecked** (files are already in the project folder)

---

## Step 3: Add Frameworks

In **Project → Target → General → Frameworks, Libraries, and Embedded Content**, add:

| Framework | Purpose |
|-----------|---------|
| `AVFoundation.framework` | Camera capture |
| `Vision.framework` | On-device OCR + rectangle detection |
| `AuthenticationServices.framework` | OAuth2 web session |
| `Security.framework` | Keychain APIs |
| `Network.framework` | Connectivity monitoring |
| `Charts.framework` | Native iOS 16+ charts (included in SDK) |

CryptoKit is included automatically with Swift standard libraries.

---

## Step 4: Configure Info.plist

Add these keys to `Info.plist`:

```xml
<!-- Camera permission -->
<key>NSCameraUsageDescription</key>
<string>Used to capture receipt images for expense tracking.</string>

<!-- OAuth2 redirect URI scheme (must match your Google Cloud Console redirect URI) -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.yourcompany.receiptscanner</string>
        </array>
        <key>CFBundleURLName</key>
        <string>Google OAuth Callback</string>
    </dict>
</array>
```

---

## Step 5: Configure Config.plist

1. Copy `Config.plist.template` → `Config.plist`
2. Add `Config.plist` to your `.gitignore`
3. Fill in values (see sections below for how to get each value)

```
AIProvider           = "openai"           (or "gemini")
ProcessingMode       = "vision"           (or "ocr_plus_llm")
GoogleClientID       = YOUR_CLIENT_ID.apps.googleusercontent.com
GoogleRedirectURI    = com.yourcompany.receiptscanner:/oauth2callback
GoogleDriveFolderID  = YOUR_FOLDER_ID
GoogleSpreadsheetID  = YOUR_SHEET_ID
```

---

## Step 6: OpenAI API Key

1. Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. **Do NOT put it in Config.plist** — enter it in the app's Settings tab
4. The app stores it in Keychain under `com.receiptscanner.openai.apikey`

**Required model**: `gpt-4o` (vision-capable). Ensure your account has access.

**Estimated cost**: ~$0.01–$0.03 per receipt (vision mode) or ~$0.001 (OCR + text mode)

---

## Step 7: Gemini API Key

1. Go to [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. Create a new API key for your project
3. Enter it in the app's Settings tab
4. The app stores it in Keychain under `com.receiptscanner.gemini.apikey`

**Required model**: `gemini-1.5-flash` (multimodal). Free tier available.

---

## Step 8: Google Cloud Console Setup

### 8a. Create a Project

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a new project: `receipt-scanner`

### 8b. Enable APIs

In **APIs & Services → Library**, enable:
- `Google Drive API`
- `Google Sheets API`

### 8c. Configure OAuth Consent Screen

1. **APIs & Services → OAuth consent screen**
2. User Type: **External**
3. App name: `ReceiptScanner`
4. Add your email as a test user
5. Scopes: add `drive.file` and `spreadsheets`

### 8d. Create OAuth 2.0 Client ID

1. **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
2. Application type: **iOS**
3. Bundle ID: `com.yourcompany.receiptscanner`
4. Copy the **Client ID** → paste into `Config.plist` as `GoogleClientID`

### 8e. Register Redirect URI

The iOS OAuth flow uses a custom scheme redirect. Your redirect URI is:

```
com.yourcompany.receiptscanner:/oauth2callback
```

Set this in:
- `Config.plist` → `GoogleRedirectURI`
- `Info.plist` → `CFBundleURLSchemes` (scheme only: `com.yourcompany.receiptscanner`)

---

## Step 9: Google Drive Folder

1. Open [drive.google.com](https://drive.google.com)
2. Create a folder: `ReceiptScanner`
3. Open the folder — copy the ID from the URL:
   `https://drive.google.com/drive/folders/`**`THIS_IS_YOUR_FOLDER_ID`**
4. Paste into `Config.plist` → `GoogleDriveFolderID`

---

## Step 10: Google Spreadsheet

1. Open [sheets.google.com](https://sheets.google.com) → create a new sheet named `Receipts`
2. Copy the spreadsheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/`**`THIS_IS_YOUR_SHEET_ID`**`/edit`
3. Paste into `Config.plist` → `GoogleSpreadsheetID`

The app will auto-create the header row on first submission:

| Timestamp | Merchant | Date | Total | Currency | Category | Items Count | Image Link | Receipt ID |

---

## Step 11: Build and Run

1. Select your device (physical device required for camera)
2. Trust the developer certificate: **Settings → General → VPN & Device Management**
3. Build: ⌘R
4. On first launch, go to **Settings tab**:
   - Enter your OpenAI or Gemini API key
   - Tap **Sign in with Google**
5. Return to **Scan tab** and capture your first receipt

---

## AI Processing Modes

### Mode A: OpenAI Vision (`openai` + `vision`)
- Sends JPEG directly to `gpt-4o` via Chat Completions API
- Most accurate for complex receipts
- ~$0.01–0.03 per call

### Mode B: Gemini Vision (`gemini` + `vision`)
- Sends JPEG to `gemini-1.5-flash` via Generative Language API
- Free tier: 15 requests/minute, 1500/day
- Comparable accuracy to GPT-4o for receipts

### Mode C: OCR + LLM (`openai` or `gemini` + `ocr_plus_llm`)
- Apple Vision Framework extracts text on-device (free, private)
- Text sent to OpenAI/Gemini for JSON structuring
- ~10× cheaper than vision mode
- Best for standard printed receipts; may struggle with handwriting

### Switching Modes

Runtime: **Settings tab → AI Provider + Processing Mode**

Config: Edit `Config.plist`:
```xml
<key>AIProvider</key>    <string>gemini</string>
<key>ProcessingMode</key><string>ocr_plus_llm</string>
```

---

## JSON Schema Contract

All AI providers return exactly this structure:

```json
{
  "merchant": "Fairprice Finest",
  "date": "2025-03-20",
  "total": 45.80,
  "currency": "SGD",
  "items": [
    { "name": "Organic Milk 1L", "quantity": 2, "price": 4.50 },
    { "name": "Bread Loaf",       "quantity": 1, "price": 3.80 }
  ]
}
```

Enforced by:
1. Strict system prompt in `ReceiptPrompts.systemPrompt`
2. `AIReceiptResponse` Decodable struct in `Receipt.swift`
3. `parseReceiptJSON()` in `AIService.swift` strips markdown fences

---

## Offline Mode

When the device is offline:
1. Receipt is serialized and saved to `Documents/offline_queue.json`
2. Max 100 receipts in queue
3. On next launch (or network restore), `OfflineQueueManager.flushIfConnected()` is called
4. The app posts `offlineQueueReadyToFlush` notification for ViewModels to handle

---

## Security Notes

| What | Where stored | Why safe |
|------|-------------|----------|
| OpenAI API key | Keychain (`kSecClassGenericPassword`) | Encrypted by Secure Enclave |
| Gemini API key | Keychain | Same |
| Google access token | Keychain | Short-lived (1h), refreshed automatically |
| Google refresh token | Keychain | Long-lived, never leaves device |
| Config values | `Config.plist` (excluded from git) | Not compiled into binary |

**Never commit `Config.plist`** — it contains your Google Client ID. Add to `.gitignore`:
```
ReceiptScanner/Config/Config.plist
```

---

## Example API Requests

### OpenAI Vision Request
```json
POST https://api.openai.com/v1/chat/completions
Authorization: Bearer sk-...
{
  "model": "gpt-4o",
  "max_tokens": 1024,
  "messages": [
    {"role": "system", "content": "<system prompt>"},
    {"role": "user", "content": [
      {"type": "text", "text": "Extract all receipt data..."},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,...", "detail": "high"}}
    ]}
  ]
}
```

### Gemini Vision Request
```json
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=API_KEY
{
  "contents": [{"role": "user", "parts": [
    {"text": "<system prompt>"},
    {"text": "Extract receipt data..."},
    {"inline_data": {"mime_type": "image/jpeg", "data": "<base64>"}}
  ]}],
  "generationConfig": {"temperature": 0, "responseMimeType": "application/json"}
}
```

### Google Sheets Append
```json
POST https://sheets.googleapis.com/v4/spreadsheets/{id}/values/Receipts!A:I:append
     ?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS
Authorization: Bearer <access_token>
{
  "majorDimension": "ROWS",
  "values": [["2025-03-20T14:30:00Z","Fairprice","2025-03-20",45.80,"SGD","Shopping",3,"https://drive.google.com/...","uuid"]]
}
```

---

## Bonus Features Summary

| Feature | Implementation |
|---------|---------------|
| Offline queue | `OfflineQueueManager` — JSON in Documents, max 100 receipts |
| AI category | `CategoryClassifier` — keyword rules + extensible to LLM |
| Duplicate detection | `DuplicateDetector` — metadata match + perceptual dHash |
| Monthly analytics | `AnalyticsStore` + `AnalyticsView` with native Charts |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Config.plist not found" | Copy `Config.plist.template` → `Config.plist` |
| "OpenAI API key not configured" | Settings tab → enter key → Save |
| Google sign-in opens but returns error | Check `CFBundleURLSchemes` matches `GoogleRedirectURI` |
| OCR returns empty | Ensure adequate lighting; try Vision mode instead |
| Sheets write fails 403 | Re-sign into Google; check API enabled in Cloud Console |
| "gpt-4o not available" | Verify your OpenAI account has GPT-4o access |

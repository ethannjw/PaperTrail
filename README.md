# ReceiptScanner

iOS app that scans paper receipts, extracts structured data using AI, and syncs to Google Sheets + Drive.

## Architecture

```
ReceiptScannerApp (entry point)
  └── RootView (TabView)
        ├── Scan Tab
        │     ├── CameraView (custom AVFoundation viewfinder)
        │     ├── DocumentScannerView (VisionKit alternative)
        │     ├── ImageProcessor (CoreImage enhancement pipeline)
        │     ├── OCRService (Apple Vision on-device OCR)
        │     ├── AIService (OpenAI / Gemini / Claude / Mock)
        │     ├── ReceiptEditView (editable extraction results)
        │     └── PDFGenerator (archival PDF creation)
        ├── History Tab (searchable receipt list + detail)
        ├── Analytics Tab (charts, category breakdown)
        └── Settings Tab (provider config, API keys, Google auth)

Services:
  ├── AI/            — AIService protocol + 5 implementations
  ├── Google/        — OAuth2 PKCE, Drive upload, Sheets append
  ├── ImageProcessing/ — CoreImage filter pipeline
  ├── PDFGenerator/  — UIGraphicsPDFRenderer-based PDF creation
  └── Sync/          — OfflineQueueManager + NetworkMonitor
```

**Pattern**: MVVM with service layer. `CameraViewModel` orchestrates the full pipeline. Dependencies are injected via constructors. Environment objects for app-wide singletons.

## AI Provider Abstraction

All providers implement the `AIService` protocol:

```swift
protocol AIService {
    func extractReceipt(from image: UIImage) async throws -> AIReceiptResponse
}
```

**Providers:**
| Provider | Class | Mode |
|----------|-------|------|
| OpenAI (gpt-4o) | `OpenAIVisionService` | Vision |
| Gemini (1.5-flash) | `GeminiVisionService` | Vision |
| Claude (sonnet-4) | `ClaudeVisionService` | Vision |
| OCR + LLM | `OCRPlusLLMService` | Hybrid (on-device OCR → any LLM) |
| Mock | `MockAIService` | Returns sample data, no API needed |

Switch providers at runtime in Settings. The `AIServiceFactory` returns the correct implementation.

## Extraction Schema

AI providers return JSON matching this schema:

```json
{
  "merchant": "Store Name",
  "date": "2026-03-21",
  "total": 47.83,
  "currency": "USD",
  "tax_amount": 3.52,
  "purpose": "Weekly grocery shopping",
  "suggested_filename": "2026-03-21_Store-Name_47.83_USD",
  "confidence_notes": "High confidence — clear print",
  "items": [
    {"name": "Item", "quantity": 1, "price": 5.99}
  ]
}
```

## Google Sheets Row Mapping

| Column | Field |
|--------|-------|
| A | Timestamp (ISO 8601) |
| B | Merchant |
| C | Date (YYYY-MM-DD) |
| D | Total |
| E | Currency |
| F | Tax |
| G | Category |
| H | Purpose |
| I | Items Count |
| J | Image Link (Drive URL) |
| K | Suggested Filename |
| L | Receipt ID (UUID) |

## Setup

### 1. Create Xcode Project

1. Open Xcode → New Project → iOS App
2. Product Name: `ReceiptScanner`
3. Interface: SwiftUI, Language: Swift
4. Delete the auto-generated ContentView.swift
5. Drag all `.swift` files from `ReceiptScanner/` into the project target
6. Add frameworks: `AVFoundation`, `Vision`, `VisionKit`, `AuthenticationServices`, `Charts`

### 2. Configure Config.plist

```bash
cp ReceiptScanner/Config/Config.plist.template ReceiptScanner/Config/Config.plist
```

Edit `Config.plist` with your credentials. The `mock` provider works without any API keys.

### 3. Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project and enable **Google Drive API** + **Google Sheets API**
3. Create OAuth 2.0 credentials (iOS app type)
4. Set the redirect URI to match your `GoogleRedirectURI` in Config.plist
5. Copy the Client ID to Config.plist
6. Create a Google Sheet and copy the spreadsheet ID from the URL
7. Create a Drive folder for receipts and copy the folder ID

### 4. Info.plist

Add these keys in Xcode:

```xml
<key>NSCameraUsageDescription</key>
<string>ReceiptScanner needs camera access to scan receipts.</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.yourcompany.receiptscanner</string>
    </array>
  </dict>
</array>
```

### 5. API Keys

Enter API keys in-app: **Settings > API Keys**. Keys are stored in iOS Keychain.

### 6. Run in Mock Mode

Set `AIProvider` to `mock` in Config.plist. The app returns realistic sample data without any API calls — useful for development and UI testing.

## Image Processing Pipeline

The `ImageProcessor` applies these CoreImage filters in order:

1. **Shadow removal** — `CIHighlightShadowAdjust` brightens shadows
2. **Contrast boost** — `CIColorControls` at 1.3× contrast
3. **Brightness** — slight +0.05 brightness lift
4. **Grayscale** — desaturation for "scanned" look
5. **Sharpening** — `CISharpenLuminance` for text edges
6. **Unsharp mask** — `CIUnsharpMask` for fine detail

An adaptive threshold mode is also available for very faded receipts.

## Scanning Options

1. **Custom Camera** — Full AVFoundation viewfinder with edge detection overlay, tap-to-focus, flash/torch controls, manual capture
2. **VisionKit Scanner** — Apple's built-in `VNDocumentCameraViewController` with auto-capture, edge detection, multi-page support, perspective correction. Tap the document icon in the top-right corner.

## Sync Behavior

| Status | Meaning |
|--------|---------|
| `pending` | Saved locally, not yet uploaded |
| `uploading` | Upload in progress |
| `synced` | Successfully uploaded to Drive + Sheets |
| `failed` | Upload failed — queued for retry |

Failed uploads are saved to an offline queue (max 100 receipts). The queue flushes automatically when connectivity is restored.

## Security

- API keys stored in iOS Keychain (`kSecAttrAccessibleWhenUnlocked`)
- Google OAuth tokens stored in Keychain with auto-refresh
- PKCE (Proof Key for Code Exchange) for OAuth flow
- Config.plist excluded from source control
- Minimal OAuth scopes: `drive.file` + `spreadsheets`
- No secrets in source code

## Future Enhancements

- **Multi-page receipts** — VisionKit already supports multi-page; extend pipeline to stitch pages
- **Expense policy tagging** — Flag receipts that exceed budget thresholds or policy rules
- **Duplicate detection improvements** — Use perceptual hashing (dHash already implemented) + fuzzy merchant matching
- **Email forwarding ingestion** — Watch a dedicated email inbox for forwarded digital receipts
- **Offline queueing improvements** — Background URLSession for uploads, exponential backoff retry
- **Export formats** — CSV export, integration with accounting software (QuickBooks, Xero)
- **Multi-currency support** — Real-time exchange rate conversion
- **Receipt templates** — Learn receipt layouts for faster extraction on repeat vendors
- **Watch/Widget** — Quick-capture from Apple Watch or home screen widget

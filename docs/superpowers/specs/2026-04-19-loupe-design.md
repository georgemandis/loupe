# Loupe — Cross-Platform Vision CLI & Library

## Overview

Loupe is a cross-platform CLI tool and C ABI library written in Zig that wraps native OS vision APIs. It provides face detection (with blur/redact image output), OCR text extraction, and barcode/QR code scanning. Same architectural pattern as whereami (geolocation) and copycat (clipboard): Zig library with platform-specific backends, CLI wrapper, C ABI for FFI consumers.

**Platforms:** macOS first (Vision framework). Windows later (Windows.Media APIs). Linux skipped for v1 (no native vision API).

## CLI Interface

```
loupe faces <image>                        # detect faces, print bounding boxes
loupe faces <image> -o <output> --blur     # detect and Gaussian blur faces
loupe faces <image> -o <output> --redact   # detect and black-box faces
loupe ocr <image>                          # extract text from image
loupe barcode <image>                      # detect all barcodes (QR, EAN, Code 128, etc.)
loupe qr <image>                           # alias: barcodes filtered to QR codes only

Global flags:
  --json       Structured JSON output (all commands)
  --help, -h   Show help
```

### Output Formats

**Human (default):**

```
$ loupe faces photo.jpg
Found 3 faces:
  Face 1: (0.12, 0.34) 0.25x0.30 [confidence: 0.98]
  Face 2: (0.55, 0.20) 0.20x0.28 [confidence: 0.95]
  Face 3: (0.70, 0.60) 0.18x0.25 [confidence: 0.87]

$ loupe ocr screenshot.png
Hello world, this is the extracted text
from the image, preserving line breaks.

$ loupe barcode label.jpg
QR: https://example.com
EAN-13: 5901234123457
```

**JSON (`--json`):**

```json
{"faces":[{"x":0.12,"y":0.34,"width":0.25,"height":0.30,"confidence":0.98}]}
{"text":"Hello world...","regions":[{"text":"Hello","x":0.1,"y":0.2,"width":0.3,"height":0.1}]}
{"barcodes":[{"payload":"https://example.com","symbology":"qr","x":0.5,"y":0.3,"width":0.2,"height":0.2}]}
```

### Rules

- `--blur` and `--redact` require `-o <output>`. Error if omitted — no in-place mutation.
- Output image format inferred from `-o` file extension (`.jpg` → JPEG, `.png` → PNG). Default to PNG if ambiguous.
- Exit code `1` for runtime errors, `2` for usage errors.

## Architecture

### File Structure

```
src/
  main.zig          # CLI entry point, subcommand dispatch, output formatting
  vision.zig        # core module — unified API, platform dispatch
  c_api.zig         # C ABI exports (opaque handles, out-pointers)
  objc.zig          # macOS ObjC runtime helpers (reused pattern from copycat/whereami)
  platform/
    macos.zig       # Vision framework backend
    windows.zig     # stub for v1, Windows.Media APIs later
build.zig
```

### Core Module API (`vision.zig`)

```
Types:
  ImageHandle       — opaque, platform-owned image reference
  BoundingBox       — { x, y, width, height: f64 } normalized 0.0–1.0, top-left origin
  FaceResult        — { box: BoundingBox, confidence: f64 }
  OcrResult         — { text: []const u8, box: BoundingBox }
  BarcodeResult     — { payload: []const u8, symbology: Symbology, box: BoundingBox }
  Symbology         — enum { qr, ean13, ean8, upca, code128, code39, ... }
  BlurMode          — enum { blur, redact }

Operations:
  loadImage(allocator, path) -> ImageHandle | error
  detectFaces(allocator, handle) -> []FaceResult | error
  recognizeText(allocator, handle) -> []OcrResult | error
  scanBarcodes(allocator, handle) -> []BarcodeResult | error
  blurFaces(handle, faces, mode: BlurMode) -> ImageHandle | error
  saveImage(handle, path) -> void | error
  freeImage(handle) -> void
  freeResults(allocator, results) -> void
```

### Bounding Box Convention

All coordinates are normalized (0.0–1.0), top-left origin. The macOS platform layer flips from Vision framework's bottom-left origin to top-left before returning results.

### macOS Backend (`platform/macos.zig`)

| Operation | API |
|-----------|-----|
| loadImage | `NSImage` → `CGImage` via `CGImageSourceCreateImageAtIndex` |
| detectFaces | `VNDetectFaceRectanglesRequest` + `VNImageRequestHandler` |
| recognizeText | `VNRecognizeTextRequest` |
| scanBarcodes | `VNDetectBarcodesRequest` |
| blurFaces (blur) | `CIFilter` Gaussian blur on face regions via Core Image |
| blurFaces (redact) | `CGContextFillRect` black rectangles via Core Graphics |
| saveImage | `CGImageDestination` (JPEG/PNG based on path extension) |

All macOS API calls go through `objc_msgSend` — same pattern as whereami/copycat.

### Windows Backend (future)

| Operation | Planned API |
|-----------|-------------|
| detectFaces | `Windows.Media.FaceAnalysis.FaceDetector` |
| recognizeText | `Windows.Media.Ocr.OcrEngine` |
| scanBarcodes | `Windows.Media.BarcodeDetector` |
| Image I/O | Windows Imaging Component (WIC) |

Stubbed in v1 — returns `error.UnsupportedPlatform`.

### C ABI Layer (`c_api.zig`)

Same pattern as copycat:
- Opaque `LoupeImage` handle
- Out-pointer variants for results (`loupe_detect_faces(handle, out_faces, out_count)`)
- Caller-freed memory with `loupe_free_*` functions
- Error codes returned as integers

### Error Handling

Structured errors from vision module:
- `error.ImageLoadFailed` — file not found, corrupt, or unsupported format
- `error.UnsupportedFormat` — output format not supported
- `error.DetectionFailed` — vision API returned an error
- `error.PermissionDenied` — OS denied access (unlikely for file-based but possible)
- `error.UnsupportedPlatform` — feature not available on current OS

CLI formats errors on stderr (human) or stdout (JSON mode as `{"error":"..."}`).

## Data Flow

**Detection only** (`loupe faces photo.jpg`):
```
load image → run detection → format results → stdout
```

**Image output** (`loupe faces photo.jpg -o blurred.jpg --blur`):
```
load image → run detection → apply blur/redact → save output image
           ↘ format results → stdout (still prints what was found)
```

Detection results are always printed, even when producing output images.

## v1 Scope

**In:**
- Face detection with bounding boxes and confidence scores
- Face blur (Gaussian) and redact (black box) with `-o` output
- OCR text extraction
- Barcode/QR code scanning (all symbologies Vision framework supports)
- `loupe qr` alias (filters to QR symbology)
- `--json` structured output on all commands
- C ABI layer with opaque handles
- macOS backend (Vision framework)
- Windows backend stubbed
- Author attribution in `--help`

**Out:**
- Linux support
- stdin/stdout image streaming
- In-place image mutation
- Video/camera input
- Face recognition (identity matching — detection only)
- Custom model loading
- Batch processing (multiple images)

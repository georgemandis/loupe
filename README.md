# loupe

Computer vision CLI & library — detect faces, read text, and scan barcodes using native OS APIs.

Built in Zig, wrapping macOS Vision framework (and eventually Windows Vision APIs). Produces a standalone CLI binary and a C-compatible shared library for FFI integration.

## Install from source

Requires [Zig 0.14+](https://ziglang.org/download/).

```bash
git clone https://github.com/georgemandis/loupe.git
cd loupe
zig build
```

Binary: `zig-out/bin/loupe`
Library: `zig-out/lib/libloupe.dylib` / `libloupe.a`

## Usage

### Face detection

```bash
loupe faces photo.jpg
loupe faces photo.jpg --json
loupe faces photo.jpg -o blurred.jpg --blur
loupe faces photo.jpg -o redacted.png --redact
```

### OCR (text recognition)

```bash
loupe ocr screenshot.png
loupe ocr screenshot.png --json
```

### Barcode & QR code scanning

```bash
loupe barcode image.png
loupe barcode image.png --json
loupe qr image.png           # QR codes only
```

## C ABI

loupe exports a C-compatible API for use from any language with FFI support (Bun, Rust, Python, etc.). See `src/c_api.zig` for the full API surface.

```c
void* handle = loupe_load_image("photo.jpg");

LoupeFaceResult* faces;
uint32_t count;
loupe_detect_faces(handle, &faces, &count);

loupe_free(faces);
loupe_free_image(handle);
```

## Platform support

| Platform | Status |
|----------|--------|
| macOS    | Supported (Vision framework) |
| Windows  | Planned (Windows Vision APIs) |
| Linux    | Not applicable (no native vision API) |

## License

MIT — see [LICENSE](LICENSE).

Created by [George Mandis](https://george.mand.is)

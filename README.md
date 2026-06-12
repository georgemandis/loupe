# loupe

Computer vision CLI & library powered by native OS APIs.

Built in [Zig](https://ziglang.org), wrapping macOS Vision framework and Windows WinRT APIs. Produces a standalone CLI binary and a C-compatible shared library for FFI integration.

## Install

### Homebrew (macOS)

```bash
brew install georgemandis/tap/loupe
```

### Scoop (Windows)

```powershell
scoop bucket add georgemandis https://github.com/georgemandis/scoop-bucket
scoop install loupe
```

### From source

Requires [Zig 0.16+](https://ziglang.org/download/).

```bash
git clone https://github.com/georgemandis/loupe.git
cd loupe
zig build
```

Binary: `zig-out/bin/loupe`
Library: `zig-out/lib/libloupe.dylib` / `zig-out/bin/loupe.dll`

## Usage

### Face detection

```bash
loupe faces photo.jpg                         # detect faces
loupe faces -o face.png photo.jpg             # extract each face to a file
loupe faces --blur -o blurred.jpg photo.jpg   # blur faces
loupe faces --redact -o redacted.png photo.jpg # black-box faces
```

### OCR (text recognition)

```bash
loupe ocr screenshot.png
loupe ocr --json screenshot.png
```

### Barcode & QR code scanning

```bash
loupe barcode image.png
loupe qr image.png          # QR codes only
```

### ArUco marker detection

Detect ArUco fiducial markers (all standard OpenCV dictionaries, auto-detected).

```bash
loupe aruco photo.jpg
loupe aruco --dict 4X4_50 photo.jpg   # restrict to one dictionary
loupe aruco --json photo.jpg
```

Candidate squares are found natively by the Vision framework's rectangle
detector and decoded in pure Zig — no OpenCV dependency. Trade-off: very
small markers (under ~1% of image area) or extreme viewing angles may be
missed compared to OpenCV's detector.

### Image classification

Classify image content using 1,300+ scene and object labels.

```bash
loupe classify photo.jpg
loupe classify --json photo.jpg
```

### Facial landmarks

Detect detailed facial feature points (eyes, nose, mouth, eyebrows, jawline).

```bash
loupe landmarks photo.jpg
loupe landmarks --json photo.jpg
```

### Body & hand pose

Detect skeletal joint positions for humans and hands.

```bash
loupe body photo.jpg
loupe hands photo.jpg
```

### Animal detection

```bash
loupe animals photo.jpg
```

### More commands

```bash
loupe rectangles photo.jpg     # detect rectangular shapes
loupe horizon photo.jpg        # measure image tilt
loupe saliency photo.jpg       # find visually salient regions
loupe saliency --objects img.jpg # objectness-based saliency
loupe score photo.jpg          # aesthetic quality score (macOS 15+)
loupe segment photo.jpg        # person segmentation mask
loupe segment -o mask.png photo.jpg  # save mask as grayscale PNG
```

All commands support `--json` for machine-readable output.

## Platform support

|  | macOS | Windows |
|--|-------|---------|
| Face detection | Yes | Yes |
| OCR | Yes | Yes |
| Barcode/QR | Yes | - |
| ArUco markers | Yes | - |
| Face extraction (`-o`) | Yes | - |
| Blur/redact | Yes | - |
| Classification | Yes | - |
| Facial landmarks | Yes | - |
| Body pose | Yes | - |
| Hand pose | Yes | - |
| Animal detection | Yes | - |
| Rectangles | Yes | - |
| Horizon | Yes | - |
| Saliency | Yes | - |
| Aesthetic score | Yes (15+) | - |
| Person segmentation | Yes | - |

The macOS build uses the Vision framework. The Windows build uses WinRT (face detection and OCR). Commands not available on your platform are hidden from `--help`.

## Shell completions

```bash
# Fish
loupe completions fish | source
# Persist: loupe completions fish > ~/.config/fish/completions/loupe.fish

# Bash
eval "$(loupe completions bash)"

# Zsh
loupe completions zsh | source /dev/stdin
```

Installed automatically via Homebrew.

## C ABI

loupe exports a C-compatible API for use from any language with FFI support. See `src/c_api.zig` for the full API surface.

```c
void* handle = loupe_load_image("photo.jpg");

LoupeFaceResult* faces;
uint32_t count;
loupe_detect_faces(handle, &faces, &count);

loupe_free(faces);
loupe_free_image(handle);
```

## License

MIT — see [LICENSE](LICENSE).

Created by [George Mandis](https://george.mand.is)

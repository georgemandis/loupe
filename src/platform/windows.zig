// Windows WinRT backend — COM boilerplate + image loading via BitmapDecoder
// IIDs are placeholders (zeros) except IID_IAsyncInfo; fill from Windows SDK headers on the VM.

const std = @import("std");
const Allocator = std.mem.Allocator;
const vision = @import("../vision.zig");

// ---------------------------------------------------------------------------
// WinRT / COM base types
// ---------------------------------------------------------------------------

const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const HRESULT = i32;
const HSTRING = ?*anyopaque;

const S_OK: HRESULT = 0;
const RO_INIT_MULTITHREADED: u32 = 1;

const AsyncStatus = enum(i32) {
    Started = 0,
    Completed = 1,
    Canceled = 2,
    Error = 3,
};

// BitmapBounds — pixel coordinates, top-left origin (NOT normalized like macOS)
const BitmapBounds = extern struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const ImageHandle = *anyopaque;

// ---------------------------------------------------------------------------
// IIDs — placeholders (zeros) unless noted
// ---------------------------------------------------------------------------

const IID_IAsyncInfo = GUID{
    .data1 = 0x00000036,
    .data2 = 0x0000,
    .data3 = 0x0000,
    .data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

// TODO: Fill in from SDK headers during implementation
const IID_IStorageFileStatics = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IStorageFile = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IBitmapDecoderStatics = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IBitmapDecoder = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IBitmapFrame = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IBitmapFrameWithSoftwareBitmap = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_ISoftwareBitmap = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

const IID_IFaceDetectorStatics = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IFaceDetector = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IDetectedFace = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

const IID_IOcrEngineStatics = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IOcrEngine = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IOcrResult = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IOcrLine = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

// Parameterized type IIDs (IAsyncOperation<T>, IVectorView<T>)
// These are SHA1 hashes — look for __FIAsyncOperation_1_xxx in the headers
const IID_IAsyncOp_StorageFile = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_IRandomAccessStream = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_BitmapDecoder = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_SoftwareBitmap = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_FaceDetector = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_OcrResult = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_VectorView_DetectedFace = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IAsyncOp_BitmapFrame = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IVectorView_DetectedFace = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
const IID_IVectorView_OcrLine = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

// ---------------------------------------------------------------------------
// COM vtable structs
// ---------------------------------------------------------------------------

const IInspectableVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
};

const IAsyncInfoVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_Id: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_Status: *const fn (*anyopaque, *AsyncStatus) callconv(.c) HRESULT,
    get_ErrorCode: *const fn (*anyopaque, *HRESULT) callconv(.c) HRESULT,
    Cancel: *const fn (*anyopaque) callconv(.c) HRESULT,
    Close: *const fn (*anyopaque) callconv(.c) HRESULT,
};

// Generic IAsyncOperation vtable — GetResults returns *anyopaque
const IAsyncOperationVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    put_Completed: *const fn (*anyopaque, ?*anyopaque) callconv(.c) HRESULT,
    get_Completed: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetResults: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IVectorView<T> — generic read-only collection
const IVectorViewVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    GetAt: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
    get_Size: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    IndexOf: *const fn (*anyopaque, *anyopaque, *u32, *bool) callconv(.c) HRESULT,
    GetMany: *const fn (*anyopaque, u32, u32, *?*anyopaque, *u32) callconv(.c) HRESULT,
};

// IStorageFileStatics — GetFileFromPathAsync
const IStorageFileStaticsVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    GetFileFromPathAsync: *const fn (*anyopaque, HSTRING, *?*anyopaque) callconv(.c) HRESULT,
    GetFileFromApplicationUriAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CreateStreamedFileAsync: *const fn (*anyopaque, HSTRING, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    ReplaceWithStreamedFileAsync: *const fn (*anyopaque, *anyopaque, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CreateStreamedFileFromUriAsync: *const fn (*anyopaque, HSTRING, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    ReplaceWithStreamedFileFromUriAsync: *const fn (*anyopaque, *anyopaque, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IStorageFile — OpenAsync (needed to get IRandomAccessStream)
// IStorageFile does NOT inherit IStorageItem in COM vtable — they are separate interfaces.
// Verify method order from SDK header: windows.storage.h IStorageFile
const IStorageFileVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IStorageFile methods — verify order from SDK header
    get_FileType: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    get_ContentType: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    OpenAsync: *const fn (*anyopaque, i32, *?*anyopaque) callconv(.c) HRESULT,
    OpenTransactedWriteAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CopyOverloadDefaultNameAndOptions: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CopyOverloadDefaultOptions: *const fn (*anyopaque, *anyopaque, HSTRING, *?*anyopaque) callconv(.c) HRESULT,
    CopyOverload: *const fn (*anyopaque, *anyopaque, HSTRING, i32, *?*anyopaque) callconv(.c) HRESULT,
    CopyAndReplaceAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    MoveOverloadDefaultNameAndOptions: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    MoveOverloadDefaultOptions: *const fn (*anyopaque, *anyopaque, HSTRING, *?*anyopaque) callconv(.c) HRESULT,
    MoveOverload: *const fn (*anyopaque, *anyopaque, HSTRING, i32, *?*anyopaque) callconv(.c) HRESULT,
};

// IBitmapDecoderStatics — CreateAsync(stream)
const IBitmapDecoderStaticsVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_BmpDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    get_JpegDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    get_PngDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    get_TiffDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    get_GifDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    get_JpegXRDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    get_IcoDecoderId: *const fn (*anyopaque, *GUID) callconv(.c) HRESULT,
    CreateAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CreateWithIdAsync: *const fn (*anyopaque, GUID, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IBitmapDecoder — GetSoftwareBitmapAsync
const IBitmapDecoderVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IBitmapDecoder methods — verify order from SDK header
    get_BitmapContainerProperties: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_DecoderInformation: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_FrameCount: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    GetPreviewAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetFrameAsync: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
};

// IBitmapFrame — get_PixelWidth, get_PixelHeight (BitmapDecoder inherits from this)
const IBitmapFrameVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    GetThumbnailAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_BitmapProperties: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_BitmapPixelFormat: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_BitmapAlphaMode: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_DpiX: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_DpiY: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_PixelWidth: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_PixelHeight: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_OrientedPixelWidth: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_OrientedPixelHeight: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    GetPixelDataAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetPixelDataTransformedAsync: *const fn (*anyopaque, i32, i32, f64, i32, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IBitmapFrameWithSoftwareBitmap — GetSoftwareBitmapAsync
const IBitmapFrameWithSoftwareBitmapVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    GetSoftwareBitmapAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetSoftwareBitmapConvertedAsync: *const fn (*anyopaque, i32, i32, *?*anyopaque) callconv(.c) HRESULT,
    GetSoftwareBitmapTransformedAsync: *const fn (*anyopaque, i32, i32, *anyopaque, i32, *?*anyopaque) callconv(.c) HRESULT,
};

// IFaceDetectorStatics — CreateAsync
const IFaceDetectorStaticsVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    CreateAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetSupportedBitmapPixelFormats: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    IsBitmapPixelFormatSupported: *const fn (*anyopaque, i32, *bool) callconv(.c) HRESULT,
};

// IFaceDetector — DetectFacesAsync
const IFaceDetectorVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    DetectFacesAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    DetectFacesWithSearchAreaAsync: *const fn (*anyopaque, *anyopaque, BitmapBounds, *?*anyopaque) callconv(.c) HRESULT,
};

// IDetectedFace — get_FaceBox
const IDetectedFaceVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_FaceBox: *const fn (*anyopaque, *BitmapBounds) callconv(.c) HRESULT,
};

// IOcrEngineStatics — TryCreateFromUserProfileLanguages
const IOcrEngineStaticsVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    MaxImageDimension: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    AvailableRecognizerLanguages: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    IsLanguageSupported: *const fn (*anyopaque, *anyopaque, *bool) callconv(.c) HRESULT,
    TryCreateFromLanguage: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    TryCreateFromUserProfileLanguages: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IOcrEngine — RecognizeAsync
const IOcrEngineVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    RecognizeAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    RecognizerLanguage: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IOcrResult — get_Lines, get_Text
const IOcrResultVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_Lines: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Text: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    get_TextAngle: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IOcrLine — get_Words, get_Text
const IOcrLineVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    get_Words: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Text: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
};

// ---------------------------------------------------------------------------
// COM helpers (same pattern as whereami)
// ---------------------------------------------------------------------------

fn vtable_(comptime VtblType: type, obj: *anyopaque) *const VtblType {
    const ptr: *const *const VtblType = @ptrCast(@alignCast(obj));
    return ptr.*;
}

fn comRelease(obj: *anyopaque) void {
    const vt = vtable_(IInspectableVtbl, obj);
    _ = vt.Release(obj);
}

fn queryInterface(obj: *anyopaque, iid: *const GUID) ?*anyopaque {
    const vt = vtable_(IInspectableVtbl, obj);
    var result: ?*anyopaque = null;
    const hr = vt.QueryInterface(obj, iid, &result);
    if (hr == S_OK) return result;
    return null;
}

// ---------------------------------------------------------------------------
// WinRT extern functions
// ---------------------------------------------------------------------------

extern "api-ms-win-core-winrt-l1-1-0" fn RoInitialize(init_type: u32) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoUninitialize() callconv(.c) void;
extern "api-ms-win-core-winrt-l1-1-0" fn RoActivateInstance(
    class_id: HSTRING,
    instance: *?*anyopaque,
) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoGetActivationFactory(
    class_id: HSTRING,
    iid: *const GUID,
    factory: *?*anyopaque,
) callconv(.c) HRESULT;

extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsCreateString(
    source: [*]const u16,
    length: u32,
    string: *HSTRING,
) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsDeleteString(
    string: HSTRING,
) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsGetStringRawBuffer(
    string: HSTRING,
    length: ?*u32,
) callconv(.c) ?[*]const u16;

// ---------------------------------------------------------------------------
// WinRT class name strings (UTF-16LE)
// ---------------------------------------------------------------------------

const STORAGE_FILE_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Storage.StorageFile");
const BITMAP_DECODER_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Graphics.Imaging.BitmapDecoder");
const FACE_DETECTOR_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Media.FaceAnalysis.FaceDetector");
const OCR_ENGINE_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Media.Ocr.OcrEngine");

// ---------------------------------------------------------------------------
// Async polling helper (same pattern as whereami)
// ---------------------------------------------------------------------------

fn waitForAsync(async_obj: *anyopaque, timeout_ms: u32) vision.VisionError!AsyncStatus {
    const info = queryInterface(async_obj, &IID_IAsyncInfo) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(info);

    const info_vt = vtable_(IAsyncInfoVtbl, info);
    const timeout_ns: i128 = @as(i128, timeout_ms) * std.time.ns_per_ms;
    const start: i128 = std.time.nanoTimestamp();

    while (true) {
        var status: AsyncStatus = .Started;
        if (info_vt.get_Status(info, &status) != S_OK)
            return vision.VisionError.DetectionFailed;
        if (status != .Started) return status;

        const now: i128 = std.time.nanoTimestamp();
        if (now - start >= timeout_ns) return vision.VisionError.DetectionFailed;

        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}

/// Get async result as *anyopaque. Caller must comRelease.
fn getAsyncResult(async_obj: *anyopaque, iid: *const GUID) vision.VisionError!*anyopaque {
    const op = queryInterface(async_obj, iid) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(op);

    const op_vt = vtable_(IAsyncOperationVtbl, op);
    var result_ptr: ?*anyopaque = null;
    if (op_vt.GetResults(op, &result_ptr) != S_OK) return vision.VisionError.DetectionFailed;
    return result_ptr orelse vision.VisionError.DetectionFailed;
}

/// Convert a UTF-8 path to an HSTRING. Caller must WindowsDeleteString.
fn hstringFromPath(path: []const u8) vision.VisionError!HSTRING {
    var buf: [4096]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, path) catch return vision.VisionError.ImageLoadFailed;
    var hs: HSTRING = null;
    if (WindowsCreateString(&buf, @intCast(len), &hs) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    return hs orelse vision.VisionError.ImageLoadFailed;
}

// ---------------------------------------------------------------------------
// ImageData — internal state stored behind the opaque ImageHandle
// ---------------------------------------------------------------------------

const ImageData = struct {
    bitmap: *anyopaque, // ISoftwareBitmap
    decoder: *anyopaque, // IBitmapDecoder (for PixelWidth/PixelHeight)
    width: u32,
    height: u32,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    // RoInitialize is safe to call multiple times — returns S_OK first time,
    // S_FALSE (1) if already initialized. Do NOT RoUninitialize here since
    // detectFaces/recognizeText also need WinRT on this thread.
    const hr_init = RoInitialize(RO_INIT_MULTITHREADED);
    if (hr_init != S_OK and hr_init != @as(HRESULT, 1))
        return vision.VisionError.ImageLoadFailed;

    // 1. Convert path to HSTRING
    const path_hs = try hstringFromPath(path);
    defer _ = WindowsDeleteString(path_hs);

    // 2. Get StorageFile factory
    var sf_class_hs: HSTRING = null;
    if (WindowsCreateString(STORAGE_FILE_CLASS, STORAGE_FILE_CLASS.len, &sf_class_hs) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    defer _ = WindowsDeleteString(sf_class_hs);

    var factory_ptr: ?*anyopaque = null;
    if (RoGetActivationFactory(sf_class_hs, &IID_IStorageFileStatics, &factory_ptr) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    const factory = factory_ptr.?;
    defer comRelease(factory);

    // 3. GetFileFromPathAsync
    const sf_vt = vtable_(IStorageFileStaticsVtbl, factory);
    var file_async_ptr: ?*anyopaque = null;
    if (sf_vt.GetFileFromPathAsync(factory, path_hs, &file_async_ptr) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    const file_async = file_async_ptr.?;
    defer comRelease(file_async);

    const file_status = try waitForAsync(file_async, 10000);
    if (file_status != .Completed) return vision.VisionError.ImageLoadFailed;

    const storage_file = try getAsyncResult(file_async, &IID_IAsyncOp_StorageFile);
    defer comRelease(storage_file);

    // 4. OpenAsync(FileAccessMode.Read = 0) → IRandomAccessStream
    // QI for IStorageFile interface (NOT IStorageFileStatics — that's the factory)
    const sf_iface = queryInterface(storage_file, &IID_IStorageFile) orelse
        return vision.VisionError.ImageLoadFailed;
    defer comRelease(sf_iface);

    const sf_file_vt = vtable_(IStorageFileVtbl, sf_iface);
    var stream_async_ptr: ?*anyopaque = null;
    if (sf_file_vt.OpenAsync(sf_iface, 0, &stream_async_ptr) != S_OK) // 0 = Read
        return vision.VisionError.ImageLoadFailed;
    const stream_async = stream_async_ptr.?;
    defer comRelease(stream_async);

    const stream_status = try waitForAsync(stream_async, 10000);
    if (stream_status != .Completed) return vision.VisionError.ImageLoadFailed;

    const stream = try getAsyncResult(stream_async, &IID_IAsyncOp_IRandomAccessStream);
    defer comRelease(stream);

    // 5. BitmapDecoder.CreateAsync(stream)
    var bd_class_hs: HSTRING = null;
    if (WindowsCreateString(BITMAP_DECODER_CLASS, BITMAP_DECODER_CLASS.len, &bd_class_hs) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    defer _ = WindowsDeleteString(bd_class_hs);

    var bd_factory_ptr: ?*anyopaque = null;
    if (RoGetActivationFactory(bd_class_hs, &IID_IBitmapDecoderStatics, &bd_factory_ptr) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    const bd_factory = bd_factory_ptr.?;
    defer comRelease(bd_factory);

    const bd_statics_vt = vtable_(IBitmapDecoderStaticsVtbl, bd_factory);
    var decoder_async_ptr: ?*anyopaque = null;
    if (bd_statics_vt.CreateAsync(bd_factory, stream, &decoder_async_ptr) != S_OK)
        return vision.VisionError.ImageLoadFailed;
    const decoder_async = decoder_async_ptr.?;
    defer comRelease(decoder_async);

    const decoder_status = try waitForAsync(decoder_async, 10000);
    if (decoder_status != .Completed) return vision.VisionError.ImageLoadFailed;

    const decoder = try getAsyncResult(decoder_async, &IID_IAsyncOp_BitmapDecoder);
    // Don't release decoder — we keep it in ImageData

    // 6. Get image dimensions from IBitmapFrame (BitmapDecoder implements IBitmapFrame)
    // Must QI for IBitmapFrame — direct vtable cast is COM UB
    const frame_iface = queryInterface(decoder, &IID_IBitmapFrame) orelse {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };
    defer comRelease(frame_iface);

    const frame_vt = vtable_(IBitmapFrameVtbl, frame_iface);
    var pixel_width: u32 = 0;
    var pixel_height: u32 = 0;
    if (frame_vt.get_PixelWidth(frame_iface, &pixel_width) != S_OK) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }
    if (frame_vt.get_PixelHeight(frame_iface, &pixel_height) != S_OK) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }

    // 7. GetSoftwareBitmapAsync via IBitmapFrameWithSoftwareBitmap
    const frame_swb = queryInterface(decoder, &IID_IBitmapFrameWithSoftwareBitmap) orelse {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };
    defer comRelease(frame_swb);

    const swb_vt = vtable_(IBitmapFrameWithSoftwareBitmapVtbl, frame_swb);
    var bitmap_async_ptr: ?*anyopaque = null;
    if (swb_vt.GetSoftwareBitmapAsync(frame_swb, &bitmap_async_ptr) != S_OK) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }
    const bitmap_async = bitmap_async_ptr.?;
    defer comRelease(bitmap_async);

    const bitmap_status = waitForAsync(bitmap_async, 10000) catch {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };
    if (bitmap_status != .Completed) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }

    const software_bitmap = getAsyncResult(bitmap_async, &IID_IAsyncOp_SoftwareBitmap) catch {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };
    // Don't release software_bitmap — we keep it in ImageData

    // 8. Pack into ImageData
    const page_alloc = std.heap.page_allocator;
    const image_data = page_alloc.create(ImageData) catch {
        comRelease(software_bitmap);
        comRelease(decoder);
        return vision.VisionError.OutOfMemory;
    };
    image_data.* = .{
        .bitmap = software_bitmap,
        .decoder = decoder,
        .width = pixel_width,
        .height = pixel_height,
    };
    return @ptrCast(image_data);
}

pub fn freeImage(image: ImageHandle) void {
    const data: *ImageData = @ptrCast(@alignCast(image));
    comRelease(data.bitmap);
    comRelease(data.decoder);
    std.heap.page_allocator.destroy(data);
}

pub fn saveImage(image: ImageHandle, path: []const u8) vision.VisionError!void {
    _ = image;
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

// ---------------------------------------------------------------------------
// Stubs for Tasks 2-4 (to be replaced)
// ---------------------------------------------------------------------------

pub fn detectFaces(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.FaceResult {
    const data: *ImageData = @ptrCast(@alignCast(image));
    const width_f: f64 = @floatFromInt(data.width);
    const height_f: f64 = @floatFromInt(data.height);

    // Ensure WinRT is initialized (safe to call multiple times, returns S_FALSE if already init'd)
    const hr_init = RoInitialize(RO_INIT_MULTITHREADED);
    if (hr_init != S_OK and hr_init != @as(HRESULT, 1))
        return vision.VisionError.DetectionFailed;

    // 1. Get FaceDetector factory
    var fd_class_hs: HSTRING = null;
    if (WindowsCreateString(FACE_DETECTOR_CLASS, FACE_DETECTOR_CLASS.len, &fd_class_hs) != S_OK)
        return vision.VisionError.DetectionFailed;
    defer _ = WindowsDeleteString(fd_class_hs);

    var fd_factory_ptr: ?*anyopaque = null;
    if (RoGetActivationFactory(fd_class_hs, &IID_IFaceDetectorStatics, &fd_factory_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const fd_factory = fd_factory_ptr.?;
    defer comRelease(fd_factory);

    // 2. CreateAsync → FaceDetector
    const fd_statics_vt = vtable_(IFaceDetectorStaticsVtbl, fd_factory);
    var create_async_ptr: ?*anyopaque = null;
    if (fd_statics_vt.CreateAsync(fd_factory, &create_async_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const create_async = create_async_ptr.?;
    defer comRelease(create_async);

    const create_status = try waitForAsync(create_async, 10000);
    if (create_status != .Completed) return vision.VisionError.DetectionFailed;

    const detector = try getAsyncResult(create_async, &IID_IAsyncOp_FaceDetector);
    defer comRelease(detector);

    // 3. QI for IFaceDetector
    const fd_iface = queryInterface(detector, &IID_IFaceDetector) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(fd_iface);

    // 4. DetectFacesAsync(bitmap)
    // NOTE: May need to convert bitmap to Gray8 first. Check IsBitmapPixelFormatSupported.
    const fd_vt = vtable_(IFaceDetectorVtbl, fd_iface);
    var detect_async_ptr: ?*anyopaque = null;
    if (fd_vt.DetectFacesAsync(fd_iface, data.bitmap, &detect_async_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const detect_async = detect_async_ptr.?;
    defer comRelease(detect_async);

    const detect_status = try waitForAsync(detect_async, 30000);
    if (detect_status != .Completed) return vision.VisionError.DetectionFailed;

    // 5. Get IVectorView<DetectedFace>
    // DetectFacesAsync returns IAsyncOperation<IVectorView<DetectedFace>>
    const faces_vector = try getAsyncResult(detect_async, &IID_IAsyncOp_VectorView_DetectedFace);
    defer comRelease(faces_vector);

    const vec_iface = queryInterface(faces_vector, &IID_IVectorView_DetectedFace) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(vec_iface);

    const vec_vt = vtable_(IVectorViewVtbl, vec_iface);
    var count: u32 = 0;
    if (vec_vt.get_Size(vec_iface, &count) != S_OK)
        return vision.VisionError.DetectionFailed;

    if (count == 0) {
        return allocator.alloc(vision.FaceResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    // 6. Iterate and normalize coordinates
    const faces = allocator.alloc(vision.FaceResult, count) catch return vision.VisionError.OutOfMemory;
    var actual_count: usize = 0;

    for (0..count) |i| {
        var face_ptr: ?*anyopaque = null;
        if (vec_vt.GetAt(vec_iface, @intCast(i), &face_ptr) != S_OK) continue;
        const face_obj = face_ptr.?;
        defer comRelease(face_obj);

        const face_iface = queryInterface(face_obj, &IID_IDetectedFace) orelse continue;
        defer comRelease(face_iface);

        const face_vt = vtable_(IDetectedFaceVtbl, face_iface);
        var bounds: BitmapBounds = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        if (face_vt.get_FaceBox(face_iface, &bounds) != S_OK) continue;

        faces[actual_count] = .{
            .box = .{
                .x = @as(f64, @floatFromInt(bounds.x)) / width_f,
                .y = @as(f64, @floatFromInt(bounds.y)) / height_f,
                .width = @as(f64, @floatFromInt(bounds.width)) / width_f,
                .height = @as(f64, @floatFromInt(bounds.height)) / height_f,
            },
            .confidence = 1.0, // Windows FaceDetector doesn't report confidence
        };
        actual_count += 1;
    }

    // Shrink if some entries were skipped
    if (actual_count < count) {
        return allocator.realloc(faces, actual_count) catch return vision.VisionError.OutOfMemory;
    }
    return faces;
}

pub fn recognizeText(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.OcrResult {
    const data: *ImageData = @ptrCast(@alignCast(image));

    // Ensure WinRT is initialized
    const hr_init = RoInitialize(RO_INIT_MULTITHREADED);
    if (hr_init != S_OK and hr_init != @as(HRESULT, 1))
        return vision.VisionError.DetectionFailed;

    // 1. Create OcrEngine from user profile languages
    var ocr_class_hs: HSTRING = null;
    if (WindowsCreateString(OCR_ENGINE_CLASS, OCR_ENGINE_CLASS.len, &ocr_class_hs) != S_OK)
        return vision.VisionError.DetectionFailed;
    defer _ = WindowsDeleteString(ocr_class_hs);

    var ocr_factory_ptr: ?*anyopaque = null;
    if (RoGetActivationFactory(ocr_class_hs, &IID_IOcrEngineStatics, &ocr_factory_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const ocr_factory = ocr_factory_ptr.?;
    defer comRelease(ocr_factory);

    const ocr_statics_vt = vtable_(IOcrEngineStaticsVtbl, ocr_factory);
    var engine_ptr: ?*anyopaque = null;
    if (ocr_statics_vt.TryCreateFromUserProfileLanguages(ocr_factory, &engine_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const engine = engine_ptr orelse return vision.VisionError.DetectionFailed;
    defer comRelease(engine);

    // 2. QI for IOcrEngine
    const engine_iface = queryInterface(engine, &IID_IOcrEngine) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(engine_iface);

    // 3. RecognizeAsync(bitmap)
    const engine_vt = vtable_(IOcrEngineVtbl, engine_iface);
    var recognize_async_ptr: ?*anyopaque = null;
    if (engine_vt.RecognizeAsync(engine_iface, data.bitmap, &recognize_async_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const recognize_async = recognize_async_ptr.?;
    defer comRelease(recognize_async);

    const recognize_status = try waitForAsync(recognize_async, 30000);
    if (recognize_status != .Completed) return vision.VisionError.DetectionFailed;

    // 4. Get OcrResult
    const ocr_result = try getAsyncResult(recognize_async, &IID_IAsyncOp_OcrResult);
    defer comRelease(ocr_result);

    const result_iface = queryInterface(ocr_result, &IID_IOcrResult) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(result_iface);

    // 5. Get lines
    const result_vt = vtable_(IOcrResultVtbl, result_iface);
    var lines_ptr: ?*anyopaque = null;
    if (result_vt.get_Lines(result_iface, &lines_ptr) != S_OK)
        return vision.VisionError.DetectionFailed;
    const lines = lines_ptr orelse return vision.VisionError.DetectionFailed;
    defer comRelease(lines);

    const lines_iface = queryInterface(lines, &IID_IVectorView_OcrLine) orelse
        return vision.VisionError.DetectionFailed;
    defer comRelease(lines_iface);

    const lines_vt = vtable_(IVectorViewVtbl, lines_iface);
    var line_count: u32 = 0;
    if (lines_vt.get_Size(lines_iface, &line_count) != S_OK)
        return vision.VisionError.DetectionFailed;

    if (line_count == 0) {
        return allocator.alloc(vision.OcrResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    // 6. Iterate lines and extract text
    const ocr_results = allocator.alloc(vision.OcrResult, line_count) catch
        return vision.VisionError.OutOfMemory;
    var actual_count: usize = 0;

    for (0..line_count) |i| {
        var line_ptr: ?*anyopaque = null;
        if (lines_vt.GetAt(lines_iface, @intCast(i), &line_ptr) != S_OK) continue;
        const line_obj = line_ptr.?;
        defer comRelease(line_obj);

        const line_iface = queryInterface(line_obj, &IID_IOcrLine) orelse continue;
        defer comRelease(line_iface);

        const line_vt = vtable_(IOcrLineVtbl, line_iface);
        var text_hs: HSTRING = null;
        if (line_vt.get_Text(line_iface, &text_hs) != S_OK) continue;
        defer _ = WindowsDeleteString(text_hs);

        // Convert HSTRING to UTF-8
        var text_len: u32 = 0;
        const raw_buf = WindowsGetStringRawBuffer(text_hs, &text_len) orelse continue;
        const utf16_slice = raw_buf[0..text_len];

        const utf8 = std.unicode.utf16LeToUtf8Alloc(allocator, utf16_slice) catch {
            for (0..actual_count) |j| allocator.free(ocr_results[j].text);
            allocator.free(ocr_results);
            return vision.VisionError.OutOfMemory;
        };

        ocr_results[actual_count] = .{
            .text = utf8,
            .box = .{ .x = 0, .y = 0, .width = 0, .height = 0 }, // No per-line bbox in v1
            .confidence = 1.0, // Windows OCR doesn't report per-line confidence
        };
        actual_count += 1;
    }

    // Shrink if needed
    if (actual_count < line_count) {
        return allocator.realloc(ocr_results, actual_count) catch return vision.VisionError.OutOfMemory;
    }
    return ocr_results;
}

pub fn scanBarcodes(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.BarcodeResult {
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn blurFaces(allocator: Allocator, image: ImageHandle, faces: []const vision.FaceResult, mode: vision.BlurMode) vision.VisionError!ImageHandle {
    _ = allocator;
    _ = image;
    _ = faces;
    _ = mode;
    return vision.VisionError.UnsupportedPlatform;
}

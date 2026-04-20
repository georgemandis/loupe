// Windows WinRT backend — COM boilerplate + image loading via BitmapDecoder
// IIDs are placeholders (zeros) except IID_IAsyncInfo; fill from Windows SDK headers on the VM.

const std = @import("std");
const Allocator = std.mem.Allocator;
const vision = @import("../vision.zig");

// ---------------------------------------------------------------------------
// WinRT / COM base types
// ---------------------------------------------------------------------------

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

pub const HRESULT = i32;
pub const HSTRING = *anyopaque;
pub const S_OK: HRESULT = 0;
pub const RO_INIT_MULTITHREADED: u32 = 1;

pub const AsyncStatus = enum(u32) {
    Started = 0,
    Completed = 1,
    Canceled = 2,
    Error = 3,
};

pub const BitmapBounds = extern struct {
    X: u32,
    Y: u32,
    Width: u32,
    Height: u32,
};

pub const ImageHandle = *anyopaque;

// ---------------------------------------------------------------------------
// IIDs — placeholders (zeros) unless noted
// ---------------------------------------------------------------------------

pub const IID_IAsyncInfo = GUID{
    .Data1 = 0x00000036,
    .Data2 = 0x0000,
    .Data3 = 0x0000,
    .Data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

pub const IID_IStorageFileStatics = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IStorageFile = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IBitmapDecoderStatics = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IBitmapDecoder = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IBitmapFrameWithSoftwareBitmap = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_ISoftwareBitmap = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

pub const IID_IFaceDetectorStatics = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IFaceDetector = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IDetectedFace = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

pub const IID_IOcrEngineStatics = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IOcrEngine = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IOcrResult = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IOcrLine = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

// Parameterized IAsyncOperation / IVectorView IIDs
pub const IID_IAsyncOp_StorageFile = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_IRandomAccessStream = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_BitmapDecoder = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_SoftwareBitmap = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_FaceDetector = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_OcrResult = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_VectorView_DetectedFace = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IAsyncOp_BitmapFrame = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IVectorView_DetectedFace = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };
pub const IID_IVectorView_OcrLine = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = .{ 0, 0, 0, 0, 0, 0, 0, 0 } };

// ---------------------------------------------------------------------------
// COM vtable structs
// ---------------------------------------------------------------------------

// IUnknown (3) + IInspectable (3) base methods
pub const IInspectableVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
};

pub const IAsyncInfoVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IAsyncInfo
    get_Id: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_Status: *const fn (*anyopaque, *AsyncStatus) callconv(.c) HRESULT,
    get_ErrorCode: *const fn (*anyopaque, *HRESULT) callconv(.c) HRESULT,
    Cancel: *const fn (*anyopaque) callconv(.c) HRESULT,
    Close: *const fn (*anyopaque) callconv(.c) HRESULT,
};

pub const IAsyncOperationVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IAsyncOperation<T>
    put_Completed: *const fn (*anyopaque, *anyopaque) callconv(.c) HRESULT,
    get_Completed: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetResults: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IVectorViewVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IVectorView<T>
    GetAt: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
    get_Size: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    IndexOf: *const fn (*anyopaque, *anyopaque, *u32, *bool) callconv(.c) HRESULT,
    GetMany: *const fn (*anyopaque, u32, u32, *?*anyopaque, *u32) callconv(.c) HRESULT,
};

pub const IStorageFileStaticsVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IStorageFileStatics
    GetFileFromPathAsync: *const fn (*anyopaque, HSTRING, *?*anyopaque) callconv(.c) HRESULT,
    GetFileFromApplicationUriAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CreateStreamedFileAsync: *const fn (*anyopaque, HSTRING, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    ReplaceWithStreamedFileAsync: *const fn (*anyopaque, *anyopaque, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CreateStreamedFileFromUriAsync: *const fn (*anyopaque, HSTRING, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    ReplaceWithStreamedFileFromUriAsync: *const fn (*anyopaque, *anyopaque, *anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IStorageFileVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IStorageFile
    get_FileType: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    get_ContentType: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    OpenAsync: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
    OpenTransactedWriteAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CopyOverloadDefaultNameAndOptions: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    CopyOverloadDefaultOptions: *const fn (*anyopaque, *anyopaque, HSTRING, *?*anyopaque) callconv(.c) HRESULT,
    CopyOverload: *const fn (*anyopaque, *anyopaque, HSTRING, u32, *?*anyopaque) callconv(.c) HRESULT,
    CopyAndReplaceAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    MoveOverloadDefaultNameAndOptions: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    MoveOverloadDefaultOptions: *const fn (*anyopaque, *anyopaque, HSTRING, *?*anyopaque) callconv(.c) HRESULT,
    MoveOverload: *const fn (*anyopaque, *anyopaque, HSTRING, u32, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IBitmapDecoderStaticsVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IBitmapDecoderStatics
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

pub const IBitmapDecoderVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IBitmapDecoder
    get_BitmapContainerProperties: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_DecoderInformation: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_FrameCount: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    GetPreviewAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetFrameAsync: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IBitmapFrameVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IBitmapFrame
    GetThumbnailAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_BitmapProperties: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_BitmapPixelFormat: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_BitmapAlphaMode: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_DpiX: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_DpiY: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_PixelWidth: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_PixelHeight: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_OrientedPixelWidth: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_OrientedPixelHeight: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    GetPixelDataAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetPixelDataTransformedAsync: *const fn (*anyopaque, u32, u32, f64, u32, BitmapBounds, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IBitmapFrameWithSoftwareBitmapVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IBitmapFrameWithSoftwareBitmap
    GetSoftwareBitmapAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetSoftwareBitmapConvertedAsync: *const fn (*anyopaque, u32, u32, *?*anyopaque) callconv(.c) HRESULT,
    GetSoftwareBitmapTransformedAsync: *const fn (*anyopaque, u32, u32, u32, u32, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IFaceDetectorStaticsVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IFaceDetectorStatics
    CreateAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetSupportedBitmapPixelFormats: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    IsBitmapPixelFormatSupported: *const fn (*anyopaque, u32, *bool) callconv(.c) HRESULT,
};

pub const IFaceDetectorVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IFaceDetector
    DetectFacesAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    DetectFacesWithSearchAreaAsync: *const fn (*anyopaque, *anyopaque, BitmapBounds, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IDetectedFaceVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IDetectedFace
    get_FaceBox: *const fn (*anyopaque, *BitmapBounds) callconv(.c) HRESULT,
};

pub const IOcrEngineStaticsVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IOcrEngineStatics
    MaxImageDimension: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    AvailableRecognizerLanguages: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    IsLanguageSupported: *const fn (*anyopaque, *anyopaque, *bool) callconv(.c) HRESULT,
    TryCreateFromLanguage: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    TryCreateFromUserProfileLanguages: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IOcrEngineVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IOcrEngine
    RecognizeAsync: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    RecognizerLanguage: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IOcrResultVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IOcrResult
    get_Lines: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Text: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    get_TextAngle: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

pub const IOcrLineVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    // IOcrLine
    get_Words: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Text: *const fn (*anyopaque, *?HSTRING) callconv(.c) HRESULT,
};

// ---------------------------------------------------------------------------
// COM helpers
// ---------------------------------------------------------------------------

/// Get vtable pointer from a COM object pointer.
pub fn vtable_(comptime VtblType: type, obj: *anyopaque) *const VtblType {
    const ptr: *const *const VtblType = @ptrCast(@alignCast(obj));
    return ptr.*;
}

/// Release a COM object.
pub fn comRelease(obj: *anyopaque) void {
    const vtbl = vtable_(IInspectableVtbl, obj);
    _ = vtbl.Release(obj);
}

/// QueryInterface helper — returns the requested interface or null.
pub fn queryInterface(obj: *anyopaque, iid: *const GUID) ?*anyopaque {
    const vtbl = vtable_(IInspectableVtbl, obj);
    var result: ?*anyopaque = null;
    const hr = vtbl.QueryInterface(obj, iid, &result);
    if (hr != S_OK) return null;
    return result;
}

// ---------------------------------------------------------------------------
// WinRT extern functions
// ---------------------------------------------------------------------------

extern "api-ms-win-core-winrt-l1-1-0" fn RoInitialize(initType: u32) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoUninitialize() callconv(.c) void;
extern "api-ms-win-core-winrt-l1-1-0" fn RoActivateInstance(activatableClassId: HSTRING, instance: *?*anyopaque) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoGetActivationFactory(activatableClassId: HSTRING, iid: *const GUID, factory: *?*anyopaque) callconv(.c) HRESULT;

extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsCreateString(sourceString: [*]const u16, length: u32, string: *?HSTRING) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsDeleteString(string: HSTRING) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsGetStringRawBuffer(string: HSTRING, length: *u32) callconv(.c) [*]const u16;

// ---------------------------------------------------------------------------
// WinRT class name strings (UTF-16LE)
// ---------------------------------------------------------------------------

const STORAGE_FILE_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Storage.StorageFile");
const BITMAP_DECODER_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Graphics.Imaging.BitmapDecoder");
const FACE_DETECTOR_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Media.FaceAnalysis.FaceDetector");
const OCR_ENGINE_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("Windows.Media.Ocr.OcrEngine");

// ---------------------------------------------------------------------------
// Async helpers
// ---------------------------------------------------------------------------

const ASYNC_TIMEOUT_MS: u64 = 30_000;
const ASYNC_POLL_MS: u64 = 50;

/// Polls IAsyncInfo.get_Status() until Completed/Error/Canceled or timeout.
fn waitForAsync(async_obj: *anyopaque) vision.VisionError!void {
    const async_info = queryInterface(async_obj, &IID_IAsyncInfo) orelse return vision.VisionError.ImageLoadFailed;
    defer comRelease(async_info);

    const vtbl = vtable_(IAsyncInfoVtbl, async_info);
    var elapsed: u64 = 0;

    while (elapsed < ASYNC_TIMEOUT_MS) {
        var status: AsyncStatus = .Started;
        const hr = vtbl.get_Status(async_info, &status);
        if (hr != S_OK) return vision.VisionError.ImageLoadFailed;

        switch (status) {
            .Completed => return,
            .Error, .Canceled => return vision.VisionError.ImageLoadFailed,
            .Started => {
                std.time.sleep(ASYNC_POLL_MS * std.time.ns_per_ms);
                elapsed += ASYNC_POLL_MS;
            },
        }
    }
    return vision.VisionError.ImageLoadFailed;
}

/// QI async_obj for IAsyncOperation with given IID, then call GetResults.
fn getAsyncResult(async_obj: *anyopaque, iid: *const GUID) vision.VisionError!*anyopaque {
    const op = queryInterface(async_obj, iid) orelse return vision.VisionError.ImageLoadFailed;
    defer comRelease(op);

    const vtbl = vtable_(IAsyncOperationVtbl, op);
    var result: ?*anyopaque = null;
    const hr = vtbl.GetResults(op, &result);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    return result orelse vision.VisionError.ImageLoadFailed;
}

/// Convert a UTF-8 path to an HSTRING.
fn hstringFromPath(path: []const u8) vision.VisionError!HSTRING {
    var buf: [4096]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, path) catch return vision.VisionError.ImageLoadFailed;
    var hs: ?HSTRING = null;
    const hr = WindowsCreateString(&buf, @intCast(len), &hs);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    return hs orelse vision.VisionError.ImageLoadFailed;
}

// ---------------------------------------------------------------------------
// ImageData — internal state stored behind the opaque ImageHandle
// ---------------------------------------------------------------------------

const ImageData = struct {
    bitmap: *anyopaque,
    decoder: *anyopaque,
    width: u32,
    height: u32,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    // Initialize WinRT (do NOT defer RoUninitialize — other functions need it)
    const init_hr = RoInitialize(RO_INIT_MULTITHREADED);
    if (init_hr != S_OK and init_hr != 1) return vision.VisionError.ImageLoadFailed;

    // --- Get StorageFile from path ---
    const path_hs = try hstringFromPath(path);
    defer _ = WindowsDeleteString(path_hs);

    // Activate StorageFile statics
    var class_hs: ?HSTRING = null;
    var hr = WindowsCreateString(STORAGE_FILE_CLASS, @intCast(STORAGE_FILE_CLASS.len), &class_hs);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer _ = WindowsDeleteString(class_hs.?);

    var storage_statics: ?*anyopaque = null;
    hr = RoGetActivationFactory(class_hs.?, &IID_IStorageFileStatics, &storage_statics);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer comRelease(storage_statics.?);

    // GetFileFromPathAsync
    const statics_vtbl = vtable_(IStorageFileStaticsVtbl, storage_statics.?);
    var async_file: ?*anyopaque = null;
    hr = statics_vtbl.GetFileFromPathAsync(storage_statics.?, path_hs, &async_file);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer comRelease(async_file.?);

    try waitForAsync(async_file.?);
    const file_inspectable = try getAsyncResult(async_file.?, &IID_IAsyncOp_StorageFile);
    defer comRelease(file_inspectable);

    // QI for IStorageFile
    const storage_file = queryInterface(file_inspectable, &IID_IStorageFile) orelse return vision.VisionError.ImageLoadFailed;
    defer comRelease(storage_file);

    // --- Open stream ---
    const file_vtbl = vtable_(IStorageFileVtbl, storage_file);
    var async_stream: ?*anyopaque = null;
    hr = file_vtbl.OpenAsync(storage_file, 0, &async_stream); // 0 = Read
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer comRelease(async_stream.?);

    try waitForAsync(async_stream.?);
    const stream = try getAsyncResult(async_stream.?, &IID_IAsyncOp_IRandomAccessStream);
    defer comRelease(stream);

    // --- Create BitmapDecoder ---
    var decoder_class_hs: ?HSTRING = null;
    hr = WindowsCreateString(BITMAP_DECODER_CLASS, @intCast(BITMAP_DECODER_CLASS.len), &decoder_class_hs);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer _ = WindowsDeleteString(decoder_class_hs.?);

    var decoder_statics: ?*anyopaque = null;
    hr = RoGetActivationFactory(decoder_class_hs.?, &IID_IBitmapDecoderStatics, &decoder_statics);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer comRelease(decoder_statics.?);

    const dec_statics_vtbl = vtable_(IBitmapDecoderStaticsVtbl, decoder_statics.?);
    var async_decoder: ?*anyopaque = null;
    hr = dec_statics_vtbl.CreateAsync(decoder_statics.?, stream, &async_decoder);
    if (hr != S_OK) return vision.VisionError.ImageLoadFailed;
    defer comRelease(async_decoder.?);

    try waitForAsync(async_decoder.?);
    const decoder = try getAsyncResult(async_decoder.?, &IID_IAsyncOp_BitmapDecoder);
    // decoder is kept alive in ImageData — do NOT defer release here

    // --- Get dimensions from IBitmapFrame (BitmapDecoder implements it) ---
    const frame_vtbl = vtable_(IBitmapFrameVtbl, decoder);
    var pixel_width: u32 = 0;
    var pixel_height: u32 = 0;
    hr = frame_vtbl.get_PixelWidth(decoder, &pixel_width);
    if (hr != S_OK) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }
    hr = frame_vtbl.get_PixelHeight(decoder, &pixel_height);
    if (hr != S_OK) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }

    // --- Get SoftwareBitmap ---
    const sw_frame = queryInterface(decoder, &IID_IBitmapFrameWithSoftwareBitmap) orelse {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };
    defer comRelease(sw_frame);

    const sw_vtbl = vtable_(IBitmapFrameWithSoftwareBitmapVtbl, sw_frame);
    var async_bitmap: ?*anyopaque = null;
    hr = sw_vtbl.GetSoftwareBitmapAsync(sw_frame, &async_bitmap);
    if (hr != S_OK) {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    }
    defer comRelease(async_bitmap.?);

    waitForAsync(async_bitmap.?) catch {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };
    const bitmap = getAsyncResult(async_bitmap.?, &IID_IAsyncOp_SoftwareBitmap) catch {
        comRelease(decoder);
        return vision.VisionError.ImageLoadFailed;
    };

    // --- Pack into ImageData ---
    const allocator = std.heap.page_allocator;
    const data = allocator.create(ImageData) catch {
        comRelease(bitmap);
        comRelease(decoder);
        return vision.VisionError.OutOfMemory;
    };
    data.* = .{
        .bitmap = bitmap,
        .decoder = decoder,
        .width = pixel_width,
        .height = pixel_height,
    };

    return @ptrCast(data);
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
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn recognizeText(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.OcrResult {
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
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

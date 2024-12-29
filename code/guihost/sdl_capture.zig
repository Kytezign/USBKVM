const std = @import("std");
const s = @cImport({
    @cInclude("SDL3/SDL.h");
});

var window: ?*s.SDL_Window = null;
var renderer: ?*s.SDL_Renderer = null;
var video: ?*s.SDL_Camera = null;
var texture: ?*s.SDL_Texture = null;
var sdl_icon: ?*s.SDL_Surface = null;

const VIDEO_NAME = "USB3 Video";

var icon_pxls = @embedFile("icon.bin");

pub fn init() c_uint {
    _ = s.SDL_SetAppMetadata("USB KVM Host", "1.0", "USB KVM Host");
    s.SDL_Log("LOG TEST!!!");

    if (!s.SDL_Init(s.SDL_INIT_VIDEO | s.SDL_INIT_CAMERA)) {
        s.SDL_Log("Failed to init %s", s.SDL_GetError());
        return 1;
    }
    if (!s.SDL_CreateWindowAndRenderer("Usb KVM", 1280, 720, s.SDL_WINDOW_RESIZABLE, &window, &renderer)) {
        s.SDL_Log("Failed to create window %s", s.SDL_GetError());
        return 1;
    }
    // Wayland doesn't seem to accept the icon so not sure if this works: https://wiki.libsdl.org/SDL3/README/wayland
    const v: ?*anyopaque = @constCast(icon_pxls);
    sdl_icon = s.SDL_CreateSurfaceFrom(32, 32, s.SDL_PIXELFORMAT_RGBA8888, v, 128);
    if (sdl_icon) |_| {} else {
        s.SDL_Log("Failed create icon surface %s", s.SDL_GetError());
    }
    if (!s.SDL_SetWindowIcon(window, sdl_icon)) {
        s.SDL_Log("Failed to set window icon %s", s.SDL_GetError());
    }
    _ = s.SDL_SetWindowRelativeMouseMode(window, true);
    if (!s.SDL_SetWindowKeyboardGrab(window, true)) {
        s.SDL_Log("Failed to grab keyboard %s", s.SDL_GetError());
    }
    _ = s.SDL_HideCursor();

    var devcount: c_int = 0;
    const devices_c = s.SDL_GetCameras(&devcount);
    if (devices_c == null) {
        s.SDL_Log("Couldn't enumerate camera devices: %s", s.SDL_GetError());
        return 1;
    } else if (devcount == 0) {
        s.SDL_Log("Couldn't find any cameras!");
        return 1;
    }
    const devices = devices_c[0..@intCast(devcount)];

    var video_id: s.SDL_CameraID = undefined;
    for (devices) |dev| {
        const str_c = s.SDL_GetCameraName(dev);
        s.SDL_Log("Device name %s", str_c);
        const str = str_c[0..VIDEO_NAME.len];
        if (std.mem.startsWith(u8, str, VIDEO_NAME)) {
            video_id = dev;
            break;
        }
    } else {
        s.SDL_Log("Couldn't find the right camera (USB3 Video)!");
        return 1;
    }
    // TODO: choose correct format options i.e. fast as possible and big as possible (or most optimal for the HW/ screen size)
    // For now we just choose what default (null)
    video = s.SDL_OpenCamera(video_id, null);
    // remember devices points to this so we keep it till exit TODO: there must be a better pattern for this?
    defer s.SDL_free(devices_c);
    if (video == null) {
        s.SDL_Log("Failed to Open HDMI Capture Device: %s", s.SDL_GetError());
        return 1;
    }
    return 0;
}

/// I guess cleanup what we can.
/// I'm not sure if this is actually enough but my intention is currently to keep things alive
/// for the full lifetime of the program so it doesn't really matter.
pub fn deinit() void {
    s.SDL_CloseCamera(video);
    s.SDL_DestroyTexture(texture);
}

pub fn renderNextFrame() void {
    // TODO assuming success in a lot of places I think... (need to review what the bool returns indicate)
    var timestamp_ns: u64 = undefined;
    const frame_opt: ?*s.SDL_Surface = s.SDL_AcquireCameraFrame(video, &timestamp_ns);
    if (frame_opt) |frame| {
        if (texture == null) {
            // init texture here after capturing the first frame from the capture card
            // this allows us to use actual size for texture creation... revisit?
            _ = s.SDL_SetRenderLogicalPresentation(renderer, frame.w, frame.h, s.SDL_LOGICAL_PRESENTATION_LETTERBOX);
            texture = s.SDL_CreateTexture(renderer, frame.format, s.SDL_TEXTUREACCESS_STREAMING, frame.w, frame.h);
        }
        // if texture
        _ = s.SDL_UpdateTexture(texture, null, frame.pixels, frame.pitch);
        s.SDL_ReleaseCameraFrame(video, frame);
        // done if?
    }
    _ = s.SDL_SetRenderDrawColor(renderer, 0x99, 0x99, 0x99, 255);
    _ = s.SDL_RenderClear(renderer);
    if (texture != null) {
        _ = s.SDL_RenderTexture(renderer, texture, null, null);
    }
    _ = s.SDL_RenderPresent(renderer);
}

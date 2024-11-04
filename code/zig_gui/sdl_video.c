// #include <stdio.h>
#include "build/include/SDL3/SDL.h"
// https://github.com/libsdl-org/SDL/blob/main/examples/camera/01-read-and-draw/read-and-draw.c

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Camera *camera = NULL;
static SDL_Texture *texture = NULL;
Uint64 timestampNS = 0;
SDL_Event event;  
int img_width=0;
int img_height=0;



bool startswith(const char *pre, const char *str)
{
    return strncmp(pre, str, strlen(pre)) == 0;
}

SDL_AppResult init(){

    SDL_CameraID *devices = NULL;
    int devcount = 0;

    SDL_SetAppMetadata("Example Camera Read and Draw", "1.0", "com.example.camera-read-and-draw");

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_CAMERA)) {
        SDL_Log("Couldn't initialize SDL: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    // SDL_WINDOW_BORDERLESS ???
    if (!SDL_CreateWindowAndRenderer("Usb KVM", 640, 480, SDL_WINDOW_RESIZABLE, &window, &renderer)) {
        SDL_Log("Couldn't create window/renderer: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    devices = SDL_GetCameras(&devcount);
    if (devices == NULL) {
        SDL_Log("Couldn't enumerate camera devices: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    } else if (devcount == 0) {
        SDL_Log("Couldn't find any camera devices! Please connect a camera and try again.");
        return SDL_APP_FAILURE;
    }
    SDL_CameraID device_id = 0;
    for (int i = 0; i < devcount; i++) {
        const char *str = SDL_GetCameraName(devices[i]);
        SDL_Log("Device name %s", str);
        if (startswith("USB3 Video", str)){
            device_id = devices[i];
            break;
            }
    }
    if (device_id == 0){
        SDL_Log("Could not find Camera: USB3 Video");
        return SDL_APP_FAILURE;
    }
    // TODO: Choose format options Fast as possible, big as possible etc. 

    camera = SDL_OpenCamera(device_id, NULL);  // Just take whatever format it wants for now. 
    SDL_free(devices);
    if (camera == NULL) {
        SDL_Log("Couldn't open camera: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    return SDL_APP_CONTINUE;
}

void deinit(){
    SDL_CloseCamera(camera);
    SDL_DestroyTexture(texture);
    // Everything else should be cleaned up on it's own??
}

void renderframe(){
        SDL_Surface *frame = SDL_AcquireCameraFrame(camera, &timestampNS);
        if (frame != NULL) {
            /* resize logical size based on image size */
            if (!texture) {
                // SDL_SetWindowSize(window, frame->w, frame->h);  /* Resize the window to match */
                SDL_SetRenderLogicalPresentation(renderer, frame->w, frame->h,SDL_LOGICAL_PRESENTATION_LETTERBOX);
                img_width = frame->w;
                img_height = frame->h;
                texture = SDL_CreateTexture(renderer, frame->format, SDL_TEXTUREACCESS_STREAMING, frame->w, frame->h);
            }

            if (texture) {
                SDL_UpdateTexture(texture, NULL, frame->pixels, frame->pitch);
            }

            SDL_ReleaseCameraFrame(camera, frame);
        }

        SDL_SetRenderDrawColor(renderer, 0x99, 0x99, 0x99, 255);
        SDL_RenderClear(renderer);
        if (texture) {  /* draw the latest camera frame, if available. */
            SDL_RenderTexture(renderer, texture, NULL, NULL);
        }
        SDL_RenderPresent(renderer);
}

bool pollEvent(){
        bool ret = SDL_PollEvent(&event);
        SDL_ConvertEventToRenderCoordinates(renderer, &event);
        return ret;
        // if (event.type == SDL_EVENT_QUIT) {
        //     return SDL_APP_SUCCESS;  /* end the program, reporting success to the OS. */
        // } else if (event.type == SDL_EVENT_CAMERA_DEVICE_APPROVED) {
        //     SDL_Log("Camera use approved by user!");
        // } else if (event.type == SDL_EVENT_CAMERA_DEVICE_DENIED) {
        //     SDL_Log("Camera use denied by user!");
        //     return SDL_APP_FAILURE;
        // }

}
import sdl2
import sdl2.ext
import cv2
import numpy as np
import kbrd
import mousectl
import serial_control
import cv_stream
import time


def run(keyboard:kbrd.KEYBORDCTRL, mouse:mousectl.ABSMOUSE, video):
    sdl2.ext.init()

    window = sdl2.ext.Window("USB KVM", size=(video.width, video.height), flags=sdl2.SDL_WINDOW_RESIZABLE)
    window.show()
    sdl2.ext.renderer.set_texture_scale_quality('best')
    renderflags = sdl2.SDL_RENDERER_ACCELERATED
    renderer = sdl2.ext.Renderer(window, logical_size= (video.width, video.height), flags=renderflags)
    surf = sdl2.SDL_CreateRGBSurface(0, video.width, video.height, 32,0,0,0,0)
    pxl_array = sdl2.ext.pixels3d(surf.contents, transpose=False)

    running = True
    while running:

        video.write_to_array(pxl_array)
        tx = sdl2.ext.Texture(renderer,surf)
        renderer.clear()
        renderer.copy(tx , dstrect=(0, 0))
        renderer.present()


        events = sdl2.ext.get_events()
        for event in events:
            event: sdl2.events.SDL_Event
            match event.type:
                case sdl2.SDL_QUIT:
                    running = False
                    break
                case sdl2.SDL_KEYDOWN:
                    keyboard.send_key_press(event.key.keysym.scancode)
                case sdl2.SDL_KEYUP:
                    keyboard.send_key_release(event.key.keysym.scancode)
                case sdl2.SDL_MOUSEMOTION:
                    x = int(event.motion.x/video.width*32767)
                    y = int(event.motion.y/video.height*32767)
                    mouse.send_mouse_move(x, y)
                case sdl2.SDL_MOUSEBUTTONDOWN:
                    btns = sdl2.ext.mouse.mouse_button_state()
                    rawbtns = btns.left | btns.right <<1 | btns.middle <<2 | btns.x1 << 3 | btns.x2 <<4
                    mouse.send_mouse_buttons(rawbtns)
                case sdl2.SDL_MOUSEBUTTONUP:
                    btns = sdl2.ext.mouse.mouse_button_state()
                    rawbtns = btns.left | btns.right <<1 | btns.middle <<2 | btns.x1 << 3 | btns.x2 <<4
                    mouse.send_mouse_buttons(rawbtns)
                case sdl2.SDL_MOUSEWHEEL:
                    x = event.wheel.x
                    y = event.wheel.y
                    mouse.send_mouse_wheel(x, y)

    # Now that we're done with the SDL2 library, we shut it down nicely using
    # the `sdl2.ext.quit` function.
    sdl2.ext.quit()
    return 0

def just_video(video):

    sdl2.ext.init()

    window = sdl2.ext.Window("USB KVM", size=(video.width, video.height), flags=sdl2.SDL_WINDOW_RESIZABLE)
    window.show()
    sdl2.ext.renderer.set_texture_scale_quality('best')
    renderflags = sdl2.SDL_RENDERER_ACCELERATED
    renderer = sdl2.ext.Renderer(window, logical_size= (video.width, video.height), flags=renderflags)
    surf = sdl2.SDL_CreateRGBSurface(0, video.width, video.height, 32,0,0,0,0)
    pxl_array = sdl2.ext.pixels3d(surf.contents, transpose=False)

    running = True
    while running:

        video.write_to_array(pxl_array)
        tx = sdl2.ext.Texture(renderer,surf)
        renderer.clear()
        renderer.copy(tx , dstrect=(0, 0))
        renderer.present()

        events = sdl2.ext.get_events()
        for event in events:
            if event.type == sdl2.SDL_QUIT:
                running = False
                break

    # Now that we're done with the SDL2 library, we shut it down nicely using
    # the `sdl2.ext.quit` function.
    sdl2.ext.quit()
    return 0


if __name__ == "__main__":
    import cProfile
    video = cv_stream.VideoStream()
    cProfile.run('just_video(video)',sort='cumulative')
    # ctrl = serial_control.try_connect()
    # keyboard = kbrd.KEYBORDCTRL(ctrl)
    # mouse = mousectl.ABSMOUSE(ctrl)
    # video = cv_stream.VideoStream()
    # sys.exit(run(keyboard, mouse, video))

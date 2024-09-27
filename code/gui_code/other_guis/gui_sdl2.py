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
    # Initialize the video system - this implicitly initializes some
    # necessary parts within the SDL2 DLL used by the video module.
    #
    # You SHOULD call this before using any video related methods or
    # classes.
    sdl2.ext.init()

    # Create a new window (like your browser window or editor window,
    # etc.) and give it a meaningful title and size. We definitely need
    # this, if we want to present something to the user.
    window = sdl2.ext.Window("Guest Display", size=(video.width, video.height))

    # By default, every Window is hidden, not shown on the screen right
    # after creation. Thus we need to tell it to be shown now.
    window.show()

    windowSurf = sdl2.SDL_GetWindowSurface(window.window)
    windowArray = sdl2.ext.pixels3d(windowSurf.contents, transpose=False)

    # Create a simple event loop. This fetches the SDL2 event queue and checks
    # for any quit events. Once a quit event is received, the loop will end
    # and we'll send the signal to quit the program.
    running = True
    hid_polling_interval = 0
    wait_period = 0
    while running:
        video.write_to_array(windowArray)
        window.refresh()

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

    window = sdl2.ext.Window("Guest Display", size=(1920, 1080), flags=sdl2.SDL_WINDOW_RESIZABLE)

    window.show()


    running = True
    while running:
        windowSurf = sdl2.SDL_GetWindowSurface(window.window)
        windowArray = sdl2.ext.pixels3d(windowSurf.contents, transpose=False)
        video.write_to_array(windowArray)
        window.refresh()

        events = sdl2.ext.get_events()
        for event in events:
            event: sdl2.events.SDL_Event
            match event.type:
                case sdl2.SDL_QUIT:
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

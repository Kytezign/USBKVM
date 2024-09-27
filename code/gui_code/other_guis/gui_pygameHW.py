import pygame
import pygame.camera
from pygame._sdl2 import Window, Texture, Image, Renderer, get_drivers, messagebox
import kbrd
import mousectl
import serial_control
import numpy as np

try:
    import linux_cam
except ImportError:
    print("TODO: suport other platforms")
    raise

def get_config():
    if linux_cam:
        return linux_cam.get_config()
    raise NotImplementedError("OOps")

def clear_config():
    if linux_cam:
        linux_cam.clear_config()




def run(keyboard:kbrd.KEYBORDCTRL, mouse:mousectl.ABSMOUSE):
    pygame.init()
    # clock = pygame.time.Clock()
    pygame.camera.init()
    config_dict = get_config()
    video_source = config_dict["Device"]
    if "Size" in config_dict:
        cam_resolution = config_dict["Size"]
    if "Format" in config_dict:
        cam_format = config_dict["Format"]
    pygame.display.init()
    # gameDisplay = pygame.display.set_mode(cam_resolution,pygame.RESIZABLE)
    win = Window("asdf", resizable=True)    
    ren = Renderer(win)
    tx = Texture(ren, cam_resolution, streaming=True)
    # ren.present()
    surf = pygame.Surface(cam_resolution)

    cam = pygame.camera.Camera(video_source, cam_resolution,cam_format)
    cam.start()
    while True:
        if cam.query_image():
            ren.clear()
            cam.get_image(surf)
            tx.update(surf)
            ren.present()


        for event in pygame.event.get() :
            match event.type:
                case pygame.QUIT :
                    cam.stop()
                    pygame.quit()
                    exit()
                case pygame.KEYDOWN:
                    keyboard.send_key_press(event.scancode)
                case pygame.KEYUP:
                    keyboard.send_key_release(event.scancode)
                case pygame.MOUSEMOTION:
                    # w, h = tx.get_size()
                    # x = int(event.pos[0]/w*32767)
                    # y = int(event.pos[1]/h*32767)
                    # mouse.send_mouse_move(x, y)
                    ...
                case pygame.MOUSEBUTTONDOWN:
                    left,  middle, right, x1, x2 = pygame.mouse.get_pressed(5)
                    rawbtns = left | right <<1 | middle <<2 | x1 << 3 | x2 <<4
                    mouse.send_mouse_buttons(rawbtns)
                case pygame.MOUSEBUTTONUP:
                    left,  middle, right, x1, x2 = pygame.mouse.get_pressed(5)
                    rawbtns = left | right <<1 | middle <<2 | x1 << 3 | x2 <<4
                    mouse.send_mouse_buttons(rawbtns)
                case pygame.MOUSEWHEEL:
                    x = event.x
                    y = event.y*10
                    mouse.send_mouse_wheel(x, y)


# Refrence https://github.com/pygame/pygame/blob/main/examples/video.py
# https://stackoverflow.com/questions/76649546/how-do-i-optimize-scaling-images-in-pygame
def video_only():
    pygame.init()
    # clock = pygame.time.Clock()
    pygame.camera.init()
    config_dict = get_config()
    video_source = config_dict["Device"]
    if "Size" in config_dict:
        cam_resolution = config_dict["Size"]
    if "Format" in config_dict:
        cam_format = config_dict["Format"]

    cam = pygame.camera.Camera(video_source, cam_resolution)#,cam_format)
    cam.start()
    cam_resolution = cam.get_size()

    pygame.display.init()
    # gameDisplay = pygame.display.set_mode(cam_resolution,pygame.RESIZABLE)
    win = Window("USB KVM", resizable=True)    
    ren = Renderer(win)
    ren.logical_size = cam_resolution
    tx = Texture(ren, cam_resolution, streaming=True, scale_quality=2)
    # ren.present()
    surf = pygame.Surface(cam_resolution)

    while True:
        if cam.query_image():
            cam.get_image(surf)
            tx = Texture.from_surface(ren, surf)
            tx.update(surf)
            ren.clear()
            # tx.draw(dstrect=(0,0,cam_resolution[0], cam_resolution[1]))
            ren.blit(tx)
            ren.present()


            for event in pygame.event.get() :
                match event.type:
                    case pygame.QUIT :
                        cam.stop()
                        pygame.quit()
                        exit()

        # clock.tick(60)
        # win.title = str(f"FPS: {clock.get_fps()}")

if __name__=="__main__":
    import cProfile
    cProfile.run('video_only()',sort='cumulative')

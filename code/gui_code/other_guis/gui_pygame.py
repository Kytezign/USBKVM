import pygame
import pygame.camera
import kbrd
import mousectl
import serial_control
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


    pygame.camera.init()
    config_dict = get_config()
    video_source = config_dict["Device"]
    if "Size" in config_dict:
        cam_resolution = config_dict["Size"]
    if "Format" in config_dict:
        cam_format = config_dict["Format"]

    gameDisplay = pygame.display.set_mode(cam_resolution,pygame.RESIZABLE| pygame.SCALED)


    cam = pygame.camera.Camera(video_source, cam_resolution,cam_format)
    cam.start()
    while True:
        if cam.query_image():
            cam.get_image(gameDisplay)
            pygame.display.update()

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
                    w, h = gameDisplay.get_size()
                    x = int(event.pos[0]/w*32767)
                    y = int(event.pos[1]/h*32767)
                    mouse.send_mouse_move(x, y)
                case pygame.MOUSEBUTTONDOWN:
                    left,  middle, right, x1, x2 = pygame.mouse.get_pressed(5)
                    rawbtns = left | right <<1 | middle <<2 | x1 << 3 | x2 <<4
                    mouse.send_mouse_buttons(rawbtns)
                case pygame.MOUSEBUTTONUP:
                    left,  middle, right, x1, x2 = pygame.mouse.get_pressed(5)
                    rawbtns = left | right <<1 | middle <<2 | x1 << 3 | x2 <<4
                    mouse.send_mouse_buttons(rawbtns)
                case pygame.MOUSEWHEEL:
                    print(event.x, event.y)
                    x = event.x
                    y = event.y*10
                    mouse.send_mouse_wheel(x, y)


def just_video():
    pygame.init()


    pygame.camera.init()
    config_dict = get_config()
    video_source = config_dict["Device"]
    if "Size" in config_dict:
        cam_resolution = config_dict["Size"]
    if "Format" in config_dict:
        cam_format = config_dict["Format"]

    gameDisplay = pygame.display.set_mode(cam_resolution,pygame.RESIZABLE| pygame.SCALED)


    cam = pygame.camera.Camera(video_source, cam_resolution,cam_format)
    cam.start()
    count = 0
    while True:
        if cam.query_image():
            cam.get_image(gameDisplay)
            pygame.display.update()
            count += 1
        if count > 200:
            cam.stop()
            pygame.quit()
            exit()


        for event in pygame.event.get() :
            match event.type:
                case pygame.QUIT :
                    cam.stop()
                    pygame.quit()
                    exit()


if __name__ =="__main__":
    import cProfile
    cProfile.run('just_video()',sort='cumulative')

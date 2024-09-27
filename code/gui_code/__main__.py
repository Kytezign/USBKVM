import gui_sdl2_renderer as gui
import serial_control
import kbrd
import mousectl
import cv_stream
import sys, time





if __name__ == "__main__":
    ctrl = serial_control.try_connect()
    keyboard = kbrd.KEYBORDCTRL(ctrl)
    mouse = mousectl.ABSMOUSE(ctrl)
    video = cv_stream.VideoStream()
    sys.exit(gui.run(keyboard, mouse, video))

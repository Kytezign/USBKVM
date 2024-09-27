CMDABSMOUSE = 4

ABSX = 0
ABSY = 1
ABSBUTTON = 2
ABSWHEEL = 3


class ABSMOUSE:
    def __init__(self, ctrl):
        self._ctrl = ctrl

    def send_mouse_move(self, x, y):
        # print("mouse", x,y)
        self._ctrl.send_command(CMDABSMOUSE,ABSX, x)
        self._ctrl.send_command(CMDABSMOUSE,ABSY, y)

    def send_mouse_buttons(self, buttons):
        self._ctrl.send_command(CMDABSMOUSE, ABSBUTTON, buttons) # pass the mask through?

    def send_mouse_wheel(self, x, y):
        self._ctrl.send_command(CMDABSMOUSE, ABSWHEEL, (x <<8) | (y & 0xFF))
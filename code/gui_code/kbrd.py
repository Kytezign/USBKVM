
KBRDCMD = 3 # TODO: make this more related to the c code's thing?




class KEYBORDCTRL:
    """Supports maintaining and sending keyboard controls"""
    def __init__(self, ctrl):
        self._ctrl = ctrl
        self._modifiers = 0
        self._pressed_keys = [0,0,0,0,0,0]
        self.clear_keys()

    def _get_empty_key_spot(self):
        return self._pressed_keys.index(0)
    
    def _check_modifier(self, key_code):
        ...

    def clear_keys(self):
        self._ctrl.send_command(KBRDCMD,0,0) # modifers
        self._pressed_keys = [0,0,0,0,0,0]
        for i,v in enumerate(self._pressed_keys):
            self._ctrl.send_command(KBRDCMD,2+i,0)


    def send_key_press(self, key_code):
        if key_code in self._pressed_keys:
            return  # already pressed, do nothing
        if self._check_modifier(key_code):
            ... # For now just use the modifier key_codes?
        else:
            index = self._get_empty_key_spot()
            self._ctrl.send_command(KBRDCMD,2+index,key_code)

            self._pressed_keys[index] = key_code

    def send_key_release(self, key_code):
        if key_code not in self._pressed_keys:
            return # TODO: error handling?
        index = self._pressed_keys.index(key_code)
        self._ctrl.send_command(KBRDCMD,2+index, 0)
        self._pressed_keys[index] = 0



    
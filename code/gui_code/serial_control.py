import serial
import serial.tools.list_ports
from serial.serialutil import SerialException
import shutil
import os, sys
import time
import threading


def debugger_is_active() -> bool:
    """Return if the debugger is currently active"""
    return hasattr(sys, 'gettrace') and sys.gettrace() is not None


def find_serial():
    ports = serial.tools.list_ports.comports()
    # Find RP2040 VIDPID (or whatever we decide to search for) 
    for portinfo in ports:
        # if portinfo.vid:
        #     print(hex(portinfo.vid), hex(portinfo.pid))
        if portinfo.vid == 0xcafe and portinfo.pid == 0x4003:
            return portinfo
    raise RuntimeError("Serial Port Not Found")
    
def try_connect(attempts=10):
    print("Searching for CDC Device")
    for i in range(attempts):
        try:
            portinfo = find_serial()
        except (RuntimeError, SerialException):
            if i > 4:
                print(f"Failed to find serial port.  Retrying ({i+1}) in {i/2} seconds...")
            time.sleep(i/3)
        else:
            break
    else:
        ports = serial.tools.list_ports.comports()
        print("\nAvalible Ports:")
        for portinfo in ports:
            if portinfo.vid:
                print(portinfo.description, hex(portinfo.vid), hex(portinfo.pid))
        raise RuntimeError("Could not find CDC Device!")
    ser = serial.Serial(portinfo.device)
    serctrl = SERCONTROL(ser)
    serctrl.send_command(0,0,0)
    serctrl.send_command(0,0,0)
    serctrl.send_command(0,0,0)
    return serctrl

class SERCONTROL:
    def __init__(self, ser):
        self.ser = ser
        self.stdo_th = threading.Thread(target=self._read_buffer, daemon=True)
        self.stdo_th.start()

    def _read_buffer(self):
        while True:
            try:
                v = self.read_buff()
                if v:
                    print(v.decode(),end="")
                time.sleep(.01) 
            except OSError:
                print("Lost Connection To Device!")
                break


    def send_command(self, cmd, meta, data):
        raw = bytes([cmd, meta, (data >> 8) & 0xFF, data & 0xFF] )
        self.ser.write(raw)

    def read_buff(self):
        return self.ser.read_all()


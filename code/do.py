import psutil
import shutil
import os
import time
import enum
import serial
import serial.tools.list_ports
from serial import SerialException
import threading
import sys
import tempfile




enumstr ="""
enum
{{
  DISK_BLOCK_NUM  = {}, // 8KB is the smallest size that windows allow to mount
  DISK_BLOCK_SIZE = {}
}};
#define CFG_EXAMPLE_MSC_READONLY


const uint8_t msc_disk[DISK_BLOCK_NUM*DISK_BLOCK_SIZE] =
{{
"""

# most exceptions are from the build steps
# I think there is a better way but for now...
sys.tracebacklimit = 2



guest_uf2_file = os.path.join(os.path.dirname(__file__), "zig-out" ,"µguest", "uguest.uf2")
host_uf2_file = os.path.join(os.path.dirname(__file__), "zig-out" ,"µhost", "uhost.uf2")
gui_file = os.path.join(os.path.dirname(__file__), "zig-out", "bin", "usbkvm_sdl3")
gui_readme = os.path.join(os.path.dirname(__file__), "µhost", "README.txt")
img_c_file = os.path.join(os.path.dirname(__file__), "zig-out" ,"µhost", "folder.c")
os.chdir(os.path.dirname(__file__))


def prep_icon():
    import numpy as np
    from PIL import Image
    img = Image.open("guihost/icon.png")
    imgraw = np.asarray(img)
    imgraw.astype('uint8').tofile("guihost/icon.bin")

def prep_dir_image():
    with tempfile.TemporaryDirectory() as img_dir:
        img_loc = os.path.join(img_dir, "temp.img")
        with tempfile.TemporaryDirectory() as tmpdirname:
            shutil.copy(gui_file, tmpdirname)
            shutil.copy(gui_readme, tmpdirname)
            tot_blocks, block_size = dir_to_img(img_loc, tmpdirname)
            os.makedirs(os.path.dirname(img_c_file), exist_ok=True)
            convert_to_c(img_loc, img_c_file, tot_blocks, block_size)

# Requires Mtools and mkfs.fat 
def dir_to_img(img_path, root_dir):
    # 260kB apprx.
    sector_size = 1024
    sector_count = 256
    cmd(f'mkfs.fat -F 12 -n USBKVM -S {sector_size} -C "{img_path}" {sector_count}')
    for r, dirs, files in os.walk(root_dir):
        for file_name in files:
            rel_dir_path = os.path.relpath(r, root_dir)
            rel_dir_path = "" if rel_dir_path == "." else rel_dir_path
            full_path = os.path.join(r, file_name)
            cmd(f'mcopy -i {img_path} -s "{full_path}" ::{rel_dir_path}')
    return sector_count, sector_size


def convert_to_c(in_file, out_file, num_blocks, block_size):

    with open(out_file, "w") as of:
        of.write(enumstr.format(num_blocks, block_size))

        with open(in_file, "rb") as f:
            for i, v in enumerate(f.read()):
                if i%16==0:
                    of.write(chr(0x0d)) # newline
                of.write(f"{hex(v)}, ")
            of.write(chr(0x0d)+"};")


def load_ucode_msc(host=True, retry_attempts=10):
    # find the drive
    for i in range(retry_attempts):
        for p in psutil.disk_partitions():
            if "RPI-RP2" in p.mountpoint:
                rp2040_drive_path = p.mountpoint
                break
        else:
            if i > 4:
                print(f"Failed to find mount point.  Retrying ({i+1}) in {i/2} seconds...")
            time.sleep(i/3)
            continue
        break
    else:
        raise RuntimeError(f"Could not find Mount Point after {retry_attempts} attempts")

    # write the code
    uf2_file_path = host_uf2_file if host else guest_uf2_file
    print("loading", uf2_file_path, "to", rp2040_drive_path)
    shutil.copy(uf2_file_path, rp2040_drive_path)
    time.sleep(2)

def cmd(cmd):
    r = os.system(cmd)
    if r!=0:
        raise RuntimeError(f"Failed Command (return {r}): {cmd}\n\n")

def build(only_gui=False):
    # Regenerate every time just in case there's a change (and it's fast)
    # ZIG Build first so the right version of library is included 
    cmd("zig build --release=small gui")
    prep_dir_image()
    if not only_gui:
        cmd("zig build --release=small")

def find_serial():
    ports = serial.tools.list_ports.comports()
    # Find RP2040 VIDPID (or whatever we decide to search for) 
    for portinfo in ports:
        if portinfo.vid:
            print(hex(portinfo.vid), hex(portinfo.pid))
        if portinfo.vid == 0x5730 and portinfo.pid == 0x4003:
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
        print("\nAvailable Ports:")
        for portinfo in ports:
            if portinfo.vid:
                print(portinfo.description, hex(portinfo.vid), hex(portinfo.pid))
        raise RuntimeError("Could not find CDC Device!")
    ser = SERCONTROL(serial.Serial(portinfo.device))
    ser.write_cmd(0,0)
    ser.write_cmd(0,0)
    ser.write_cmd(0,0)
    ser.write_cmd(0,0)
    return ser


class Cmds(enum.IntEnum):
    echo4 = 0x1,
    echo16 = 0x81,
    KeyBoardUpdate = 0x82,
    echo32 = 0xC1,
    panic = 0xC2,
    rebootloader = 0xC3,   
    MouseUpdate = 0xC5,
    MousePosUpdate = 0xC6
  



class SERCONTROL:
    def __init__(self, ser):
        self.ser = ser
        self.stop_logging = False
        self.stdo_th = threading.Thread(target=self._read_buffer, daemon=True)
        self.stdo_th.start()
        self.write(bytes([0]*5))
        self.msg_buffer = []

    def __del__(self):
        self.stop_logging = True
        print("waiting thread...")
        self.stdo_th.join()
        print("Thread Closed")

    def stop_thread(self):
        self.stop_logging = True

    def _read_buffer(self):
        print("Starting Read Thread")
        while True:
            if self.stop_logging:
                break
            try:
                v = self.ser.read_all()
                if v:
                    self.msg_buffer.extend([x for x in v.decode()])
                    # print('\033[96m'+ v.decode()+ '\033[0m',end="")
                    if self.msg_buffer[-1] == "\n":
                        msg = "".join(self.msg_buffer)
                        if msg.startswith("Guest: "):
                            print('\033[92m'+  msg.replace("Guest: ", "") + '\033[0m',end="")
                        else:
                            print('\033[94m'+ msg + '\033[0m',end="")
                        self.msg_buffer.clear()
            except OSError:
                print("Bad Serial read")
                break
            time.sleep(.1) 

    def write_cmd(self, cmd, data):
        # 4 bytes data
        # print(cmd, hex(data))
        if (cmd & 0b1100_0000) == 0b1100_0000:
            assert data <= 0xFFFF_FFFF, f"Data too big:{hex(cmd)}: {hex(data)}"
            data_b = data.to_bytes(4, 'little')
            self.write(bytes([cmd])+data_b)
        # Two bytes data
        elif cmd & 0b1000_0000: 
            assert data <= 0xFFFF, f"Data too big:{hex(cmd)}: {hex(data)}"
            data_b = data.to_bytes(2, 'little')
            self.write(bytes([cmd])+data_b)
        else:
            assert data <= 0xF, f"Data too big:{hex(cmd)}: {hex(data)}"
            self.write(bytes([cmd<<4 | data]))

    def write(self, data_b):
        self.ser.write(data_b)

def host_reset_to_boot(ser=None):
    if ser is None:
        try:
            ser = try_connect(1)
        except:
            return
    ser.write_cmd(Cmds.rebootloader, 0xAAAA_AAAA) # To boot loader...
    ser.stop_thread()
    time.sleep(1)
    # del ser


# from internet
def twos_comp(val, bits):
    """compute the 2's complement of int value val"""
    val = val & ((1 << bits) - 1)
    return val                         # return positive value as is

def guest_reset_to_boot(ser=None):
    if ser is None:
        ser = try_connect()
    ser.write_cmd(Cmds.rebootloader, 0x5555_5555) # To boot loader...
    ser.stop_thread()
    time.sleep(1)
    # del ser

def pack_mouse_cmd(is_abs, buttons, x, y, vert, hori):
    data = is_abs
    data |= buttons << 8
    data |= twos_comp(vert, 8) << 16
    data |= twos_comp(hori, 8) << 24

    pos_data = twos_comp(x, 16)
    pos_data |= twos_comp(y, 16) << 16

    return data, pos_data

def launch_gui():
    print()
    print()
    print()
    print("Starting GUI...")
    cmd(gui_file)
    print()
    print()


def test(ser=None):
    print()
    print()
    print("Starting Tests:")
    if ser is None:
        ser = try_connect()
    print("Echo test")
    ser.write_cmd(0, 0)
    ser.write_cmd(0, 0)
    ser.write_cmd(0, 0)
    ser.write_cmd(Cmds.echo4, 0xA)
    ser.write_cmd(Cmds.echo16, 0xABCD)
    ser.write_cmd(Cmds.echo32, 0xABCD_EF01)

    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x04) # should be A key
    # time.sleep(20e-3)
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x00) # should be A key
    # time.sleep(1)
    
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x04) # should be A key
    # time.sleep(20e-3)
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x00) # should be A key
    
    # time.sleep(1)
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x04) # should be A key
    # time.sleep(20e-3)
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x00) # should be A key
    
    # time.sleep(1)
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x04) # should be A key
    # time.sleep(20e-3)
    # ser.write_cmd(Cmds.KeyBoardUpdate, (0x0 << 8 )| 0x00) # should be A key
    while True:
        ser.write_cmd(Cmds.MouseUpdate, pack_mouse_cmd(0, 0, 5, 5, 0, 0)[0])
        ser.write_cmd(Cmds.MousePosUpdate, pack_mouse_cmd(0, 0, 100, -100, 0, 0)[1])
        time.sleep(1)

    print("Done With Test Flow...")
    input()



if __name__ == "__main__":
    # prep_icon()
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", help="Force reload", action="store_true")
    parser.add_argument("--guest", help="Force reload", action="store_true")
    parser.add_argument("--load", help="Force reload", action="store_true")
    parser.add_argument("--gui", help="Force reload", action="store_true")
    args = parser.parse_args()
    cmd("clear")
    if args.host or args.guest or args.load or args.gui:
        build(args.gui)
    if args.host or args.load:
        print("*********************************")
        print("Loading Host...")
        print("*********************************")
        host_reset_to_boot()
        load_ucode_msc()
    if args.guest or args.load:
        print("*********************************")
        print("Loading Guest...")
        print("*********************************")
        guest_reset_to_boot()
        load_ucode_msc(False)
    # loading guest assume we don't want to launch the gui
    if not (args.guest or args.load):
        launch_gui()
    # test()



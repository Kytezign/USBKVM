import fat12
import zipapp
import tempfile
import os
import sys
sys.path.append("../gui_code")
import serial_control
import psutil
import shutil
import time

# TODO: Document dependandies of this build/deploy system...

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

def convert_to_c(in_file, out_file, num_blocks, block_size):

    with open(out_file, "w") as of:
        of.write(enumstr.format(num_blocks, block_size))

        with open(in_file, "rb") as f:
            for i, v in enumerate(f.read()):
                if i%16==0:
                    of.write(chr(0x0d)) # newline
                of.write(f"{hex(v)}, ")
            of.write(chr(0x0d)+"};")
       
def filter(name):
    for n in ["__pycache__", ".vscode","README","requirements", "launch_gui.sh", "usbkvm_sdl3", "other_guis"]:
        if n in str(name):
            return False
    return True

def dir_to_img(img_path, root_dir):
    # 500kB I think.
    sector_size = 1024
    sector_count = 512
    os.system(f'mkfs.fat -F 12 -n USBKVM -S {sector_size} -C "{img_path}" {sector_count}')
    for r, dirs, files in os.walk(root_dir):
        for file_name in files:
            rel_dir_path = os.path.relpath(r, root_dir)
            rel_dir_path = "" if rel_dir_path == "." else rel_dir_path
            full_path = os.path.join(r, file_name)
            os.system(f'mcopy -i {img_path} -s "{full_path}" ::{rel_dir_path}')
    return sector_count, sector_size

def prep_dir_image():
    in_folder = r"../gui_code"
    zig_bin_folder = r"../zig_gui/build/zig-out/bin"
    out_file = "folder_bin.c"
    with tempfile.TemporaryDirectory() as img_dir:
        img_loc = os.path.join(img_dir, "temp.img")

        with tempfile.TemporaryDirectory() as tmpdirname:
            zipapp_loc = os.path.join(tmpdirname, "run_usb_kvm.pyz")
            shutil.copy(os.path.join(in_folder, "README.txt"), tmpdirname)
            shutil.copy(os.path.join(in_folder, "requirements.txt"), tmpdirname)
            shutil.copy(os.path.join(in_folder, "launch_gui.sh"), tmpdirname)
            shutil.copy(os.path.join(zig_bin_folder, "usbkvm_sdl3"), tmpdirname)
            zipapp.create_archive(in_folder, zipapp_loc, compressed=True, filter=filter)
            tot_blocks, block_size = dir_to_img(img_loc, tmpdirname)
            convert_to_c(img_loc, out_file, tot_blocks, block_size)

def build_project():
    os.system("cmake --build build --config Debug --target all")


# Loading functions
def force_reset():
    ctrl = serial_control.try_connect(4)
    CMDUSBBOOT = 5
    ctrl.send_command(CMDUSBBOOT,0,0)
    time.sleep(2) # Give time for last message?


ucode_name = "hid_forward"
top_dir = os.path.dirname(os.path.dirname(__file__))
uf2_file_path = os.path.join(top_dir, "ucode", "build", ucode_name+".uf2")

def load_ucode_msc():
    # find the drive
    for p in psutil.disk_partitions():
        if "RPI-RP2" in p.mountpoint:
            rp2040_drive_path = p.mountpoint
            break
    else:
        raise RuntimeError("Could Not Find Device Mount Point.  Is it connected?")
    # write the code
    print("loading", uf2_file_path, "to", rp2040_drive_path)
    shutil.copy(uf2_file_path, rp2040_drive_path)

def load_pico_tool():
    # TODO: intelligent waiting
    time.sleep(5)
    os.system(f"picotool load {uf2_file_path}")
    os.system(f"picotool reboot")

def deploy_bootmode():
    print("ATTEMPTING TO RESET")
    try:
        force_reset()
    except:
        print("Failed reset attempt")
        print()
        print()
    load_pico_tool()

def deploy_swd():
    os.system(f'openocd -f interface/cmsis-dap.cfg -f rp2040_c0.cfg -c "program build/{ucode_name}.elf verify reset exit"')


def build_zig():
    cwd = os.getcwd()
    try:
        os.chdir(r"../zig_gui")
        os.system(f'zig build -Doptimize=ReleaseSmall -p ./build/zig-out')
    finally:
        os.chdir(cwd)

# openocd -f interface/cmsis-dap.cfg -f rp2040_c0.cfg -c "program build/hid_forward.elf verify reset exit"
# cmake --build build --config Debug --target all -j 18
if __name__=="__main__":
    build_zig()
    prep_dir_image()
    build_project()
    deploy_bootmode()


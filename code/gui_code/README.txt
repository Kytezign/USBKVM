
# Running Linux

## Executable - SDL3
- usbkvm_sdl3 *should* run on a linux system with SDL3 installed (not very broad testing yet)
    - If that works it is the best option.  Alternitively python is avalible as a fallback.
    - Here is a one liner that will copy the file make it executable and run it:
        `temp_dir=$(mktemp -d); cp usbkvm_sdl3 "$temp_dir"; chmod +x "$temp_dir/usbkvm_sdl3"; "$temp_dir/usbkvm_sdl3"`

## Python - See requirements.txt
- Intall python requirements though the normal methods (pip install)
- Ensure a usb capture card is connected.
- Ensure Host and Device USB are connected. 
- Run python run_usb_kvm.pyz


# Running Windows
- Windows should be pretty close for both methods but it's not been tested yet so don't want to release anything. 


# Usage
If everything works - it's still really early in the project -
keyboard and mouse events should be passed through to the guest machine 
while displaying video on the host.  The mouse is an absolute position mouse which might not work in all cases
Sound can be piped manually at the OS level for now.

# For more infomation
Here is the github
https://github.com/Kytezign/USBKVM

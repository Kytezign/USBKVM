
# Running Linux

## Executable - SDL3
- usbkvm_sdl3 *should* run on a linux system with SDL3 installed (not very broad testing yet)
- Here is a one liner that will copy the file make it executable and run it:
    `temp_dir=$(mktemp -d); cp usbkvm_sdl3 "$temp_dir"; chmod +x "$temp_dir/usbkvm_sdl3"; "$temp_dir/usbkvm_sdl3"`


# Running Windows
- It might work but its not tested

# Usage
If everything works - it's still really early in the project -
- keyboard and mouse events should be passed through to the guest machine 
- While displaying video on the host, the mouse is captured so you'll have to work around that one way or another
- the insert key will paste from the host clipboard text converted to HID keystrokes. 
- Sound can be piped manually at the OS level for now.

# For more infomation
Here is the github
https://github.com/Kytezign/USBKVM

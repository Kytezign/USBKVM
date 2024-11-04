#!/bin/bash

temp_dir=$(mktemp -d)
cp usbkvm_sdl3 "$temp_dir"
chmod +x "$temp_dir/usbkvm_sdl3"
"$temp_dir/usbkvm_sdl3"
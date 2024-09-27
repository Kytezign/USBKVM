
import subprocess
import platform
import pathlib
import os
import configparser
import tkinter
from tkinter import ttk


class OPTypes:
    Device = "Device"
    DeviceDesc = "DeviceDesc"
    Format = "Format"
    Size = "Size"
    FPS = "FPS"
    EOO = "EOO"


if not platform.system().startswith("Linux"):
    raise ImportError("Not a Linux Platform")


""""{"key":{"name":"n", "options":[{},...], "Prop0": "p"}"""

class Options:
    def __init__(self, op_type, desc, value, options_list=[], **props):
        self.op_type = op_type
        self.desc = desc
        self.value = value
        self._options = options_list
        for k, v in props.items():
            setattr(self, k, v)

    def append(self, option):
        if self._options is None:
            raise RuntimeError("No Suboptions Enabled")
        self._options.append(option)

    def __iter__(self):
        return self._options.__iter__()
    
    def __getitem__(self, index):
        return self._options[index]
    
    def __len__(self):
        return len(self._options)
    
    def __repr__(self) -> str:
        if self.value == self.desc:
            return str(self.value)
        else:
            return f"{self.value}: {self.desc}"




def find_cams_v4l2_ctl():
    # Get devices
    result = subprocess.run(["v4l2-ctl", "--list-devices"], stdout=subprocess.PIPE)
    devices = []
    for line in result.stdout.decode().splitlines():
        line: str
        ws_count = len(line) - len(line.strip())
        line = line.strip()
        if line.endswith(":"):
            desc = line[:-1]
        elif line.startswith("/"):
            devices.append((line, desc))

    devices_options = Options(OPTypes.Device, "All Devices", "", [])
    # get supported resoutions etc.
    for dev, desc in devices:
        result = subprocess.run(["v4l2-ctl","-d", f"{dev}" ,"--list-formats-ext"], stdout=subprocess.PIPE)
        this_device = Options(OPTypes.Format,desc,dev,[])
        for line in result.stdout.decode().splitlines():
            line: str
            ws_count = len(line) - len(line.strip())
            line = line.strip()
            if line.strip().startswith("["):
                num = int(line[1:line.find("]")])
                lttrs = line[line.find("'")+1:line.find("'")+5]
                this_device.append(Options(OPTypes.Size, lttrs,lttrs,[]))
                curr_format = lttrs
            elif line.startswith("Size"):
                size_str = line[line.rfind(" ")+1:] # should be the last thing in the line
                this_device[-1].append(Options(OPTypes.FPS, size_str, size_str, []))
                curr_size = size_str
            elif line.startswith("Interval"):
                fps = line[line.rfind("(")+1:line.rfind(" ")]
                this_device[-1][-1].append(Options(OPTypes.EOO, fps, fps,[]))
        if len(this_device):
            devices_options.append(this_device)
    
    return devices_options

CONFIGHEADER = "LastDevice"
config_folder = os.path.join(pathlib.Path.home(), ".config", "usb_kvm")
config_file = os.path.join(config_folder, "defaults.config")


def get_config():
    """
    Return a dict of configuration parameters:
    DeviceDesc: Text description of the device based on v4l2's return'd values
    Device: ValidPath
    Format: 4 letter format
    Size: (width, height)
    FPS: Float    
    """
    os.makedirs(config_folder, exist_ok=True)
    config = configparser.ConfigParser()
    config.read(config_file)
    devices = find_cams_v4l2_ctl()
    if config.has_section(CONFIGHEADER):
        config_values = config[CONFIGHEADER]

        # check to see if the same devicee is still avalible base on description then path then the spesific settings
        desc_fits = []
        for d in devices:
            d : Options
            if d.desc == config_values["DeviceDesc"]:
                desc_fits.append(d)
        for best_device in desc_fits:
            if best_device.value == config_values[OPTypes.Device]:
                break
    else:
        best_device = None
        config.add_section(CONFIGHEADER)
        config_values = config[CONFIGHEADER]
        print("Previous config could not be found")
        a = App(devices)
        a.run()
        config_dict = a.selections
        config_values.update(config_dict)
        config_values["DeviceDesc"] = [d.desc for d in devices if d.value==config_dict[OPTypes.Device]][-1]
        config_values.update(config_dict)
        with open(config_file, "w") as f:
            config.write(f)


    config_dict = {}
    config_dict[OPTypes.Device] = config_values[OPTypes.Device]
    config_dict["DeviceDesc"] = config_values["DeviceDesc"]
    config_dict[OPTypes.Format] = config_values[OPTypes.Format]
    config_dict[OPTypes.Size] = tuple( [int(a) for a in config_values[OPTypes.Size].split("x")])
    config_dict[OPTypes.FPS] = float(config_values[OPTypes.FPS])

    return config_dict

def clear_config():
    try:
        os.remove(config_file)
    except:
        pass
        

class App:
    def __init__(self, devices):
        self.devices = devices
        self.root = tkinter.Tk()
        frm = ttk.Frame(self.root, padding=10)
        frm.grid()
        self.frm = frm
        self.option_menus = {}
        self.selections = {}
        ttk.Button(self.frm, text="Submit", command=self.root.destroy).pack() #button to close the window

        self.update_options(self.devices)


    def update_options(self, options:Options):
        if options.op_type == "EOO":
            self.capture_sel() # TODO: find a better spot for this?
            return
        if options.op_type in self.option_menus:
            self.option_menus[options.op_type][0].destroy()
            # del(self.option_menus[options.op_type][1]) TODO: memory leak of that variable?
            del(self.option_menus[options.op_type])
        try:
            var = tkinter.StringVar(self.root, options[0])
        except IndexError:
            raise RuntimeError(f"Could not find any xxx")
        menu = ttk.OptionMenu(self.frm, var, options[0], *options, command=self.update_options)
        menu.pack()
        self.option_menus[options.op_type] = (menu, var)
        for opt in options:
            self.update_options(opt)

    def run(self):
        self.root.mainloop()

    def capture_sel(self):
        for op_type, v in self.option_menus.items():
            if op_type == OPTypes.Device:
                # Ug
                this_device_option = [d for d in self.devices if d.__repr__() == v[1].get()][-1] # should only be one
                self.selections[op_type] = this_device_option.value
                self.selections["DeviceDesc"] = this_device_option.desc
            else:
                self.selections[op_type] = v[1].get()


if __name__ == "__main__":
    # os.environ["DISPLAY"]= ":0"
    print(get_config())
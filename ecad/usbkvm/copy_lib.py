import os
import shutil
import zipfile
import tempfile
import sys
import glob


"""
Usage: put this file in the desired local library root directory

When run it will find the most recent zip file in the Downloads folder and extract the things we want.
The 3d model will go into a folder ./3dcad  (must already exist)

The other two (symbols & footprints) will go into a temporary folder: ./temp_kicad_lib

Once they are copied, in kicad import the symbol and footprint from the temp folder into the local project libraries (using symobl editor and footprint editor)

Link the footprint to the 3d model and make sure it's right. 


"""


this_dir = os.path.dirname(__file__)

dir_3d = os.path.join(this_dir, "3dcad")

if __name__ == "__main__":

    list_of_files = glob.glob(os.path.expanduser("~")+'/Downloads/*.zip') # * means all if need specific format then *.csv
    latest_file = max(list_of_files, key=os.path.getctime)
    in_zip = latest_file
    print("found file", in_zip)
    out_dir = os.path.join(this_dir,"temp_kicad_lib")
    try:
        shutil.rmtree(out_dir)
    except FileNotFoundError:
        pass
    os.makedirs(out_dir)
    with tempfile.TemporaryDirectory() as temp_dir:
        with zipfile.ZipFile(in_zip, 'r') as zip_ref:
            zip_ref.extractall(temp_dir)
        for root, dirs, files in os.walk(temp_dir):
            if root.endswith("3D"):
                for file in files:
                    if file.endswith(".stp"):
                        print("3d Found", file)
                        shutil.copy(os.path.join(root, file), out_dir)
                        shutil.copy(os.path.join(root, file), dir_3d)
            if "kicad" in root.lower():
                for file in files: 
                    if file.endswith(".lib") or file.endswith("kicad_sym"):
                        print("symbol Found", file)
                        shutil.copy(os.path.join(root, file), out_dir)
                    if file.endswith(".kicad_mod"):
                        print("footprint found", file)
                        shutil.copy(os.path.join(root, file), out_dir)


            # print(root, dirs, files)
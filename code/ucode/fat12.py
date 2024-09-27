import os
import datetime
from math import ceil

"""Minimal implementation of FAT12 to be able to write a C array that represents a disk..."""

class FixedByteArray(bytearray):
    def __init__(self, *args, **kwargs):
        self.__len = len(args[0])
        super().__init__(*args, *kwargs)
    def __setitem__(self, key, value):
        super().__setitem__(key, value)
        if self.__len != len(self):
            raise RuntimeError(f"Length of array has changed!  From {self.__len} to {len(self)}")

class FixedList(list):
    def __init__(self, *args, **kwargs):
        self.__len = len(args[0])
        super().__init__(*args, *kwargs)
    def __setitem__(self, key, value):
        super().__setitem__(key, value)
        if self.__len != len(self):
            raise RuntimeError(f"Length of array has changed!  From {self.__len} to {len(self)}")


class FAT12:
    MAX_ROOT_ENTRIES = 16
    RESERVED_SECTORS = 1
    NUM_FATS = 1
    SECTORS_IN_FAT = 1
    def __init__(self, name, block_number, block_size=512):
        assert self.NUM_FATS == 1, "Only one FAT supported."
        assert len(name) == 12, "Wrong name length"
        self._data = FixedList([FixedByteArray([0 for _ in range(block_size)]) for _ in range(block_number)])
        # self._data = np.zeros((block_number, block_size),np.ubyte)
        self.block_size = block_size
        self.block_number = block_number
        self._init_boot_sector()
        tmp = self.NUM_FATS*self.SECTORS_IN_FAT*self.block_size/3
        self.fat_entries = FixedList([0 for i in range(int(tmp))])
        self.fat_entries[0:2] = 0xFF8, 0xFFF # Apparently this must be the first two entries?

        # TODO: root directory initial entry.
        self.directories = {"":[1+1*self.SECTORS_IN_FAT]} # dict of directories with the format: {full_path:sector_index, ...}
        self._init_root_dir(name)

    def _init_root_dir(self, name):
        dt = datetime.datetime.now()
        long_names, entry = self._create_dir_entry(name, 0x08, dt, 0, 0)
        self.add_dir_entry("", entry,long_names)


    def _init_boot_sector(self):
        # Write first block...
        b0 = self._data[0]
        assert len(b0) == self.block_size, f"{self.block_size} not same as {len(b0)}"
        # ignore or JMP/ OEM data
        # b0[0:11] = 0xEB, 0x3C, 0x90, 0x4D, 0x53, 0x44, 0x4F, 0x53, 0x35, 0x2E, 0x30
        b0[0:11] = 0xEB, 0x3C, 0x90, 0x66, 0x61, 0x74, 0x31, 0x32, 0x2E, 0x70, 0x79,
        # Bytes per cluster =512 (DISK_BLOCK_SIZE)
        b0[11:13] = self.block_size.to_bytes(2, "little")
        # sectors per cluster = 1
        b0[13:14] = 0x01,
        # number of reserved sectors = 1
        b0[14:16] = int(self.RESERVED_SECTORS).to_bytes(2, "little")
        #  Number of FATs =1
        b0[16:17] = self.NUM_FATS,
        # max number of root directory entries =16 
        b0[17:19] = int(self.MAX_ROOT_ENTRIES).to_bytes(2, "little")
        # total sectors count  = 16 (DISK_BLOCK_NUM)
        b0[19:21] = int(self.block_number).to_bytes(2, "little")
        #  ignore (Set to 0xF8?)
        b0[21:22] =0xF8,
        # sectors per FAT = 1
        b0[22:24] = int(self.SECTORS_IN_FAT).to_bytes(2, "little")
        # sectors per track = 1
        b0[24:26] = int(1).to_bytes(2, "little")
        #  Number of Heads = 1
        b0[26:28] = int(1).to_bytes(2, "little")
        #  ignore
        b0[28:32] = 0x00, 0x00, 0x00, 0x00
        #  Total sector count (0 for Fab12)
        b0[32:36] = 0x00, 0x00, 0x00, 0x00
        #  ignore\
        b0[36:38] = 0x80, 0x00
        #  exteneded boot signature
        b0[38:39] = 0x29,
        #  Volume ID
        b0[39:43] = 0x34, 0x12, 0x00, 0x00,
        # Volume label
        b0[43:54] = b'TinyUSB MSC'
        # File system type (FAT12   )
        b0[54:61] = b"FAT12  "
        # Magic FAT code at the end???
        b0[510:512] = 0x55, 0xAA
        # print([hex(x) for x in b0[0:64]])
        assert len(b0) == self.block_size, f"{self.block_size} not same as {len(b0)}"

    def _update_fat(self):
        """Update table based on current fat entries list"""
        carry_nib = None
        assert self.SECTORS_IN_FAT == self.NUM_FATS == 1, "TODO"
        fat = self._data[1]  # not sure if this is always true or not? 
        fat[:] = [0 for _ in range(self.block_size)] # clear first
        byte_index = 0
        
        for  e in self.fat_entries:
            assert e <= 0xFFF, "More than 12 bits. Invalid FAT entry"
            assert e != 1, "Invalid FAT entry... probabably a bug somewhere"
            # Two FAT12 entries are stored into three bytes; if these bytes are uv,wx,yz then the entries are xuv and yzw. 
            # odd bytes are shared
            # split up
            if carry_nib is None:
                v = e & 0xFF
                carry_nib = e >> 8
                fat[byte_index] = v
                byte_index +=1 # TODO probably can do some math with enumerate to keep track of this...
            else:
                v = (e & 0xF) << 4 | carry_nib 
                v1 = e >> 4
                fat[byte_index:byte_index+2] = v, v1
                byte_index +=2 # TODO probably can do some math with enumerate to keep track of this...
                carry_nib = None

        if carry_nib is not None:
            fat[byte_index] = carry_nib

    def _add_new_directory(self, dir_path, max_entries=16):
        assert dir_path not in self.directories, "Path already in dir"
        sub_dir_path, name = os.path.split(dir_path) 
        index = self._next_fat(True)
        lne, entry = self._create_dir_entry(name, 0b1_0000, datetime.datetime.now(),index,max_entries*32)
        total_blocks = ceil(max_entries*32/self.block_size)
        block_indexes = self._add_element(index, sub_dir_path, entry, lne, total_blocks)
        self.directories[dir_path] = block_indexes
        # Create entry for . and ..
        self.directories[sub_dir_path][0]
        lne, entry = self._create_dir_entry(".", 0b1_0000, datetime.datetime.now(),self.directories[sub_dir_path][0],max_entries*32)
        self.add_dir_entry(dir_path,entry,lne)
        lne, entry = self._create_dir_entry("..", 0b1_0000, datetime.datetime.now(),self.directories[dir_path][0],max_entries*32)
        self.add_dir_entry(dir_path,entry,lne)


   
    def add_dir_entry(self, dir_path, entry, long_name_entries=[]):
        # walk dir path to the correct loc
        if dir_path not in self.directories:
            # create new dir entry with the other path
            self._add_new_directory(dir_path) # may call recursively until done.

        # Find next free entry (starts with 0)
        dir_sector_indexes = self.directories[dir_path]
        for dir_block_index in dir_sector_indexes:
            dir_entries = self._data[dir_block_index]
            e_index = None
            for ei in range(self.block_size//32):
                if dir_entries[ei*32] == 0:
                    e_index = ei*32
                    break
            else:
                continue
            # Write entry
            for e in long_name_entries +[entry]:
                e_index_end = e_index+32
                assert e_index < self.block_size, "No support for block crossing names"
                dir_entries[e_index:e_index_end] = e
                e_index = e_index_end
            break

    def _next_fat(self, add_placeholder=False):
        nf = self.fat_entries.index(0)
        if add_placeholder:
            self.fat_entries[nf] = 1 # just temprary invalid value so the next call points to a new block
        return nf


    def add_file(self, in_file, img_dir):
        """Input full path of a file from the root dir of the image"""
        name = os.path.basename(in_file)
        dt = datetime.datetime.fromtimestamp(os.path.getmtime(in_file))
        s = os.stat(in_file)
        # create dir entry
        assert s.st_size < 0xFFFF_FFFF, "TODO: is this really the max"
        # Start cluster: sectors in the FAT + root sector = 2
        # Both dir entry and fat entries are logical starting at 2
        # Block index is physical starting at the fist sector after the root directory
        # offset is boot sector + FAT size + root dir size minus the first two fat entries
        index = self._next_fat(True)
        lne, entry = self._create_dir_entry(name, 0x20,dt, index, s.st_size)
        total_blocks = ceil(s.st_size/self.block_size)
        block_indexes = self._add_element(index, img_dir, entry, lne, total_blocks)
        # Write file to memory
        with open(in_file, "rb") as f:
            d = f.read()
        for i, d_sub in enumerate(self.chunks(d,self.block_size)):
            block_index = block_indexes[i]
            self._data[block_index][0:len(d_sub)] = d_sub


    def _add_element(self, start_index, dir_path, dir_entry, lne, total_blocks):
        phys_offset = 1 + self.SECTORS_IN_FAT + ceil(self.MAX_ROOT_ENTRIES/self.block_size) - 2
        self.add_dir_entry(dir_path,dir_entry,lne)
        # create FAT entry
        # handle multiple chunks
        block_indexes = []
        # get all blocks (in order for simplicity)
        index = start_index
        for i in range(total_blocks-1):
            # This math works on some assuptions... becareful
            self.fat_entries[index] = self._next_fat(True)
            block_indexes.append(phys_offset+index)
            index = self.fat_entries[index]
        self.fat_entries[index] = 0xFFF # last block 
        block_indexes.append(phys_offset+index)
        return block_indexes


    def write_img_file(self, out_path):
        self._update_fat()
        with open(out_path, 'wb') as f:
            for ba in self._data:
                f.write(ba)

    def get_raw_blocks(self):
        self._update_fat()
        return self._data
    
    @staticmethod
    def chunks(lst, n):
        """Yield successive n-sized chunks from lst."""
        for i in range(0, len(lst), n):
            yield lst[i:i + n]
    
    def _to_date_time(self, dt: datetime.datetime):
        year= dt.year-1980
        t = dt.hour << 11 | dt.minute << 5 | int(dt.second/2)
        d = year << 9 | dt.month <<5 | dt.day 
        return t, d

    def _create_dir_entry(self, name,attribute,dt, starting_cluster, size):
        entry = FixedByteArray(bytes(32))
        # TODO: long names we could return a separate, ignoreable entry. 
        lnes, r, ext = self._create_long_name_entries(name)
        entry[0:8] = r.ljust(8).encode()
        entry[8:11] = ext.ljust(3).encode()
        entry[11:12] = attribute,
        entry[13:14] = 0xC6, # Not sure what this is or if it helps
        t, d = self._to_date_time(dt)
        
        # entry[14:16] = t.to_bytes(2, "little")
        # entry[16:18] = d.to_bytes(2, "little")
        entry[22:24] = t.to_bytes(2, "little")
        entry[24:26] = d.to_bytes(2, "little")
        entry[26:28] = starting_cluster.to_bytes(2, "little")
        entry[28:32] = size.to_bytes(4, "little")
        return lnes, entry # none is a placeholder for VFAT long name entries. 
    
    def _get_lne_checksum(self, short_name):
        assert len(short_name) == 11
        checksum = 0
        for i in range(11):
            checksum = (((checksum&1)<<7)|((checksum&0xfe)>>1)) + ord(short_name[i])
            # checksum = (checksum >> 1) + ((checksum & 1) << 7)
            # checksum += ord(short_name[i])
        checksum &= 0xFF

        return checksum
    
    def _encode_16bit(self, string):
        a = bytearray()
        for c in string:
            if c == 0xFF:
                a.append(0xFF)
                a.append(0xFF)
            else:
                a.append(ord(c))
                a.append(0)

        return a
    
    def _create_long_name_entries(self, name:str):
        #  http://www.maverick-os.dk/FileSystemFormats/VFAT_LongFileNames.html
        r, ext = os.path.splitext(name)
        ext = ext.replace(".", "")
        ln_entries = []
        if len(r) < 9 and len(ext) < 4:
            ext = ext.replace(".", "")
            short_ext = ext
            short_name = r
        else:
            # Get short name
            short = r
            for replace in "+,;=[],":
                short = short.replace("_", replace)
            short = short.upper()
            short_name = short[:6] + "~1" # TODO: what about repeated short names....
            short_ext = ext[:3].ljust(3, " ")
            checksum = self._get_lne_checksum(short_name+short_ext)
            # break up into 13 characters (unicode 16bits)
            chunks = list(self.chunks(name, 13))
            for i, c in  enumerate(chunks):
                if len(c) < 13:
                    c = c + "\0"
                    c = c.ljust(13, chr(0xFF))
                lfn_entry = FixedByteArray(bytes(32))
                lfn_entry[0] = i+1
                if i == len(chunks) - 1:
                    lfn_entry[0] |=0x40 # last entry\
                lfn_entry[1:0xB] = self._encode_16bit(c[:5])
                lfn_entry[0xB] = 0x0F
                lfn_entry[0xC] = 0
                lfn_entry[0xD] = checksum
                lfn_entry[0xE:0x1A] = self._encode_16bit(c[5:11])
                lfn_entry[0x1A:0x1C] = 0,0
                lfn_entry[0x1C:0x20] = self._encode_16bit(c[11:])
                ln_entries.append(lfn_entry)
            ln_entries.reverse()

        return ln_entries, short_name, short_ext
    
def dir_to_img(drive_name, in_dir, out_file, skip=[]):
    assert len(drive_name) == 8
    block_size = 512
    total_size = 0
    file_list = []
    for root, dirs, files in os.walk(in_dir):
        for file_name in files:
            rel_dir_path = os.path.relpath(root, in_dir)
            rel_dir_path = "" if rel_dir_path == "." else rel_dir_path
            full_path = os.path.join(root, file_name)
            for s_file in skip:
                if s_file in full_path:
                    break
            else:
                file_list.append(( full_path, rel_dir_path))
                s = os.stat(full_path)
                # create dir entry
                total_size += ceil(s.st_size/block_size)*block_size*1.5 + 35 # Estimate total size..
    tot_blocks = ceil(total_size/block_size)
    name = drive_name + ".   "
    fs = FAT12(name,tot_blocks, block_size)
    for in_file, img_path in file_list:
        fs.add_file(in_file, img_path)
    fs.write_img_file(out_file)
    return tot_blocks, block_size


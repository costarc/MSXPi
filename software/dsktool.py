#!/usr/bin/python3
import sys
import os
import struct

SECTOR_SIZE = 512
TOTAL_SECTORS = 1440
FAT_SECTORS = 9
ROOT_DIR_ENTRIES = 112
ROOT_DIR_SECTORS = (ROOT_DIR_ENTRIES * 32) // SECTOR_SIZE
ROOT_DIR_OFFSET = SECTOR_SIZE * (1 + 2 * FAT_SECTORS)  # Boot + 2 FATs
DATA_START_SECTOR = 1 + 2 * FAT_SECTORS + ROOT_DIR_SECTORS

def show_usage():
    print("Parameters:")
    print("  format filename.dsk     create blank MSX-compatible disk image")
    print("  copy sourcefile diskimage.dsk:targetfile")
    print("  dir  diskimage.dsk      list files")
    sys.exit(1)

def create_blank_dsk(filename):
    with open(filename, "wb") as f:
        # Boot sector
        boot = bytearray(SECTOR_SIZE)
        boot[0:3] = b'\xEB\xFE\x90'  # JMP instruction
        boot[3:11] = b'MSX-DOS '     # OEM name
        boot[11:13] = struct.pack("<H", SECTOR_SIZE)  # Bytes per sector
        boot[13] = 1                 # Sectors per cluster
        boot[14:16] = struct.pack("<H", 1)  # Reserved sectors
        boot[16] = 2                 # Number of FATs
        boot[17:19] = struct.pack("<H", ROOT_DIR_ENTRIES)
        boot[19:21] = struct.pack("<H", TOTAL_SECTORS)
        boot[21] = 0xF0              # Media descriptor
        boot[22:24] = struct.pack("<H", FAT_SECTORS)
        boot[24:26] = struct.pack("<H", 18)  # Sectors per track
        boot[26:28] = struct.pack("<H", 2)   # Number of heads
        boot[510:512] = b'\x55\xAA'  # Boot signature
        f.write(boot)

        # FAT tables
        fat = bytearray(SECTOR_SIZE * FAT_SECTORS)
        fat[0:3] = b'\xF0\xFF\xFF'  # First three bytes of FAT12
        f.write(fat)
        f.write(fat)  # Second FAT

        # Root directory
        f.write(bytearray(SECTOR_SIZE * ROOT_DIR_SECTORS))

        # Data area
        data_sectors = TOTAL_SECTORS - (1 + 2 * FAT_SECTORS + ROOT_DIR_SECTORS)
        f.write(bytearray(SECTOR_SIZE * data_sectors))

    print(f"Formatted MSX-compatible disk image: {filename}")

def read_dir_entries(dskfile):
    with open(dskfile, "rb") as f:
        f.seek(ROOT_DIR_OFFSET)
        entries = []
        for _ in range(ROOT_DIR_ENTRIES):
            entry = f.read(32)
            if entry[0] == 0x00:
                break  # No more entries
            if entry[0] == 0xE5:
                continue  # Deleted entry
            name = entry[0:8].decode("ascii", errors="ignore").strip()
            ext = entry[8:11].decode("ascii", errors="ignore").strip()
            size = struct.unpack("<I", entry[28:32])[0]
            entries.append((name, ext, size))
        return entries

def inject_file(srcfile, dskfile, targetname):
    with open(srcfile, "rb") as f:
        data = f.read()

    name, ext = os.path.splitext(os.path.basename(targetname))
    name = name.upper().ljust(8)[:8]
    ext = ext[1:].upper().ljust(3)[:3]  # remove dot

    with open(dskfile, "r+b") as f:
        # Find empty directory slot
        f.seek(ROOT_DIR_OFFSET)
        for i in range(ROOT_DIR_ENTRIES):
            pos = f.tell()
            entry = f.read(32)
            if entry[0] == 0x00 or entry[0] == 0xE5:
                f.seek(pos)
                f.write(name.encode("ascii"))
                f.write(ext.encode("ascii"))
                f.write(b"\x00" * 17)  # reserved
                f.write(struct.pack("<H", DATA_START_SECTOR))  # starting cluster
                f.write(b"\x00" * 8)  # reserved
                f.write(struct.pack("<I", len(data)))  # file size
                break
        else:
            raise RuntimeError("No free directory entry found.")

        # Write file data
        f.seek(DATA_START_SECTOR * SECTOR_SIZE)
        f.write(data)

if len(sys.argv) < 2:
    show_usage()

try:
    cmd = sys.argv[1].lower()

    if cmd == "format":
        if len(sys.argv) < 3:
            raise ValueError("Missing filename for format command.")
        create_blank_dsk(sys.argv[2])

    elif cmd == "dir":

        if len(sys.argv) < 3:
            raise ValueError("Missing disk image path for 'dir' command.")
        entries = read_dir_entries(sys.argv[2])
        for name, ext, size in entries:
            print(f"{name}.{ext}  {size} bytes")

    elif cmd == "copy":
        if len(sys.argv) < 4:
            raise ValueError("Missing source or target for 'copy' command.")
        srcfile = sys.argv[2]
        raw_target = sys.argv[3]

        if ";" in raw_target:
            dskfile, fullpath = raw_target.split(";", 1)
            targetname = os.path.basename(fullpath)
        else:
            dskfile, sep, targetname = raw_target.partition(":")
            if not sep or not targetname:
                raise ValueError("Target must be in format diskimage.dsk:filename")

        print(f"Copying: {srcfile} to {dskfile}:{targetname}")
        inject_file(srcfile, dskfile, targetname)
        print("Done")

    else:
        raise ValueError(f"Unknown command: {cmd}")

except Exception as e:
    print(f"Error: {e}")
#!/usr/bin/env python3
import sys
import os
import struct

# These globals will be overridden from the boot sector BPB
SECTOR_SIZE = 512
TOTAL_SECTORS = 1440
SECTORS_PER_CLUSTER = 2
RESERVED_SECTORS = 1
NUM_FATS = 2
FAT_SECTORS = 3
ROOT_DIR_ENTRIES = 112
ROOT_DIR_SECTORS = (ROOT_DIR_ENTRIES * 32) // SECTOR_SIZE
MEDIA_DESCRIPTOR = 0xF0

FAT0_START_SECTOR = RESERVED_SECTORS
FAT1_START_SECTOR = FAT0_START_SECTOR + FAT_SECTORS
ROOT_START_SECTOR = FAT1_START_SECTOR + FAT_SECTORS
DATA_START_SECTOR = ROOT_START_SECTOR + ROOT_DIR_SECTORS
FIRST_DATA_CLUSTER = 2

# MSXDOS 1.8 - COMMAND.COM 1.2.1
BOOT_SECTOR = (
    b"\xEB\xFE\x90\x4D\x53\x58\x5F\x30\x34\x20\x20\x00\x02\x02\x01\x00"
    b"\x02\x70\x00\xA0\x05\xF9\x03\x00\x09\x00\x02\x00\x00\x00\xD0\xED"
    b"\x53\x70\xC0\x32\xCB\xC0\x36\x6D\x23\x36\xC0\x31\x1F\xF5\x11\xA6"
    b"\xC0\x0E\x0F\xCD\x7D\xF3\x3C\xC2\x51\xC0\x21\xCC\xC0\x11\xA7\xC0"
    b"\x01\x02\x00\xED\xB0\x11\xA6\xC0\x0E\x0F\xCD\x7D\xF3\x3C\xCA\x7A"
    b"\xC0\x11\x00\x01\x0E\x1A\xCD\x7D\xF3\x21\x01\x00\x22\xB4\xC0\x21"
    b"\x00\x3F\x11\xA6\xC0\x0E\x27\xCD\x7D\xF3\xC3\x00\x01\x58\xC0\xCD"
    b"\x00\x00\x79\xE6\xFE\xFE\x02\xC2\x81\xC0\x3A\xCB\xC0\xA7\xCA\x22"
    b"\x40\x11\x90\xC0\x0E\x09\xCD\x7D\xF3\x0E\x07\xCD\x7D\xF3\x18\x9B"
    b"\x45\x72\x72\x6F\x21\x20\x54\x65\x63\x6C\x65\x20\x41\x6C\x67\x6F"
    b"\x2E\x2E\x2E\x0D\x0A\x24\x00\x4D\x53\x58\x44\x4F\x53\x20\x20\x53"
    b"\x59\x53\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x44\x44\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
)


def show_usage():
    print("Parameters:")
    print("  format filename.dsk                 create blank MSX-DOS1-style disk image")
    print("  copy sourcefile image.dsk:NAME.EXT  copy file into image")
    print("  dir   image.dsk                     list files in image")
    sys.exit(1)


# ---------- Layout helpers ----------

def sector_offset(sector_number: int) -> int:
    return sector_number * SECTOR_SIZE


def cluster_to_first_sector(cluster: int) -> int:
    if cluster < FIRST_DATA_CLUSTER:
        raise ValueError(f"Invalid cluster number: {cluster}")
    return DATA_START_SECTOR + (cluster - FIRST_DATA_CLUSTER) * SECTORS_PER_CLUSTER


# ---------- FAT12 helpers ----------

def fat_size_bytes() -> int:
    return FAT_SECTORS * SECTOR_SIZE


def read_fat(f) -> bytearray:
    f.seek(sector_offset(FAT0_START_SECTOR))
    return bytearray(f.read(fat_size_bytes()))


def write_fat(f, fat: bytearray):
    if len(fat) != fat_size_bytes():
        raise RuntimeError("FAT size mismatch")
    # FAT0
    f.seek(sector_offset(FAT0_START_SECTOR))
    f.write(fat)
    # FAT1 mirror
    f.seek(sector_offset(FAT1_START_SECTOR))
    f.write(fat)


def fat12_get_entry(fat: bytearray, cluster: int) -> int:
    index = (cluster * 3) // 2
    if cluster & 1:
        # odd cluster: high 12 bits
        value = ((fat[index] >> 4) | (fat[index + 1] << 4)) & 0xFFF
    else:
        # even cluster: low 12 bits
        value = (fat[index] | ((fat[index + 1] & 0x0F) << 8)) & 0xFFF
    return value


def fat12_set_entry(fat: bytearray, cluster: int, value: int):
    value &= 0xFFF
    index = (cluster * 3) // 2
    if cluster & 1:
        # odd cluster: high 12 bits
        low = fat[index] & 0x0F
        fat[index] = low | ((value & 0x0F) << 4)
        fat[index + 1] = (value >> 4) & 0xFF
    else:
        # even cluster: low 12 bits
        fat[index] = value & 0xFF
        high = fat[index + 1] & 0xF0
        fat[index + 1] = high | ((value >> 8) & 0x0F)


def fat12_init() -> bytearray:
    fat = bytearray(fat_size_bytes())
    fat[0] = MEDIA_DESCRIPTOR
    fat[1] = 0xFF
    fat[2] = 0xFF
    return fat


def allocate_clusters(fat: bytearray, num_clusters: int):
    clusters = []
    data_sectors = TOTAL_SECTORS - DATA_START_SECTOR
    max_clusters = data_sectors // SECTORS_PER_CLUSTER + FIRST_DATA_CLUSTER

    c = FIRST_DATA_CLUSTER
    while c < max_clusters and len(clusters) < num_clusters:
        if fat12_get_entry(fat, c) == 0x000:
            clusters.append(c)
        c += 1

    if len(clusters) < num_clusters:
        raise RuntimeError("Disk full: not enough clusters")

    for i, cl in enumerate(clusters):
        if i == len(clusters) - 1:
            fat12_set_entry(fat, cl, 0xFFF)  # end of chain
        else:
            fat12_set_entry(fat, cl, clusters[i + 1])

    return clusters


# ---------- Directory helpers ----------

def root_dir_offset() -> int:
    return sector_offset(ROOT_START_SECTOR)


def read_dir_entries(dskfile):
    entries = []
    with open(dskfile, "rb") as f:
        # sync geometry from this image's boot sector
        boot = f.read(512)
        bpb = parse_bpb(boot)
        apply_bpb_to_globals(bpb)

        f.seek(root_dir_offset())
        for i in range(ROOT_DIR_ENTRIES):
            entry = f.read(32)
            if len(entry) < 32:
                break
            if entry[0] == 0x00:
                break
            if entry[0] == 0xE5:
                continue
            name = entry[0:8].decode("ascii", errors="ignore").strip()
            ext = entry[8:11].decode("ascii", errors="ignore").strip()
            size = struct.unpack("<I", entry[28:32])[0]
            entries.append((name, ext, size))
    return entries


def find_free_dir_entry(f) -> int:
    f.seek(root_dir_offset())
    for i in range(ROOT_DIR_ENTRIES):
        pos = f.tell()
        entry = f.read(32)
        if len(entry) < 32:
            raise RuntimeError("Root directory truncated")
        if entry[0] in (0x00, 0xE5):
            return pos
    raise RuntimeError("No free directory entries")


def find_existing_dir_entry(f, name: str, ext: str):
    """Returns (position, starting_cluster) for a live (non-deleted) entry
    matching name/ext (both already 8.3-padded/uppercased), or None if no
    such entry exists. Without this, injecting a file under a name already
    present on the disk just consumed a fresh directory slot and fresh
    clusters every time instead of replacing the old ones - leaving the old
    entry (and old, now-orphaned data) still on disk and still first in
    directory order, so DOS would keep running/reading the stale version
    forever no matter how many times a new one was injected afterward."""
    f.seek(root_dir_offset())
    for i in range(ROOT_DIR_ENTRIES):
        pos = f.tell()
        entry = f.read(32)
        if len(entry) < 32 or entry[0] == 0x00:
            break
        if entry[0] == 0xE5:
            continue
        entry_name = entry[0:8].decode("ascii", errors="ignore")
        entry_ext = entry[8:11].decode("ascii", errors="ignore")
        if entry_name == name and entry_ext == ext:
            start_cluster = struct.unpack_from("<H", entry, 26)[0]
            return pos, start_cluster
    return None


def free_cluster_chain(fat: bytearray, start_cluster: int):
    """Walks a FAT12 chain starting at start_cluster, marking every
    cluster in it free (0x000). start_cluster == 0 means an empty file
    (no clusters were ever allocated) - nothing to do."""
    cluster = start_cluster
    seen = set()
    while cluster >= FIRST_DATA_CLUSTER and cluster not in seen:
        seen.add(cluster)
        next_cluster = fat12_get_entry(fat, cluster)
        fat12_set_entry(fat, cluster, 0x000)
        if next_cluster >= 0xFF8:  # end of chain
            break
        cluster = next_cluster


# ---------- BPB parsing ----------

def parse_bpb(boot: bytes):
    if len(boot) != 512:
        raise RuntimeError("Boot sector must be 512 bytes")
    bytes_per_sector    = struct.unpack_from("<H", boot, 11)[0]
    sectors_per_cluster = boot[13]
    reserved_sectors    = struct.unpack_from("<H", boot, 14)[0]
    num_fats            = boot[16]
    root_entries        = struct.unpack_from("<H", boot, 17)[0]
    total_sectors       = struct.unpack_from("<H", boot, 19)[0]
    media               = boot[21]
    sectors_per_fat     = struct.unpack_from("<H", boot, 22)[0]
    sectors_per_track   = struct.unpack_from("<H", boot, 24)[0]
    num_heads           = struct.unpack_from("<H", boot, 26)[0]

    return {
        "bytes_per_sector": bytes_per_sector,
        "sectors_per_cluster": sectors_per_cluster,
        "reserved_sectors": reserved_sectors,
        "num_fats": num_fats,
        "root_entries": root_entries,
        "total_sectors": total_sectors,
        "media": media,
        "sectors_per_fat": sectors_per_fat,
        "sectors_per_track": sectors_per_track,
        "num_heads": num_heads,
    }


def apply_bpb_to_globals(bpb: dict):
    global SECTOR_SIZE, SECTORS_PER_CLUSTER, RESERVED_SECTORS
    global NUM_FATS, ROOT_DIR_ENTRIES, TOTAL_SECTORS
    global FAT_SECTORS, ROOT_DIR_SECTORS, MEDIA_DESCRIPTOR
    global FAT0_START_SECTOR, FAT1_START_SECTOR
    global ROOT_START_SECTOR, DATA_START_SECTOR

    SECTOR_SIZE         = bpb["bytes_per_sector"]
    SECTORS_PER_CLUSTER = bpb["sectors_per_cluster"]
    RESERVED_SECTORS    = bpb["reserved_sectors"]
    NUM_FATS            = bpb["num_fats"]
    ROOT_DIR_ENTRIES    = bpb["root_entries"]
    TOTAL_SECTORS       = bpb["total_sectors"]
    MEDIA_DESCRIPTOR    = bpb["media"]
    FAT_SECTORS         = bpb["sectors_per_fat"]
    ROOT_DIR_SECTORS    = (ROOT_DIR_ENTRIES * 32) // SECTOR_SIZE

    FAT0_START_SECTOR = RESERVED_SECTORS
    FAT1_START_SECTOR = FAT0_START_SECTOR + FAT_SECTORS
    ROOT_START_SECTOR = FAT1_START_SECTOR + FAT_SECTORS
    DATA_START_SECTOR = ROOT_START_SECTOR + ROOT_DIR_SECTORS


# ---------- Disk formatting ----------

def create_blank_dsk(filename: str):
    boot = bytes(BOOT_SECTOR)
    if len(boot) != 512:
        raise RuntimeError("Embedded boot sector must be exactly 512 bytes")

    bpb = parse_bpb(boot)
    apply_bpb_to_globals(bpb)

    with open(filename, "wb") as f:
        # boot sector as-is
        f.write(boot)

        # FATs
        fat = fat12_init()
        write_fat(f, fat)

        # root dir
        f.seek(sector_offset(ROOT_START_SECTOR))
        f.write(bytearray(SECTOR_SIZE * ROOT_DIR_SECTORS))

        # data area
        data_sectors = TOTAL_SECTORS - DATA_START_SECTOR
        f.seek(sector_offset(DATA_START_SECTOR))
        f.write(bytearray(SECTOR_SIZE * data_sectors))

    print(f"Formatted MSX-DOS1-style disk image: {filename}")

# ---------- File injection ----------

def inject_file(srcfile: str, dskfile: str, targetname: str):
    with open(srcfile, "rb") as f:
        data = f.read()

    # DOS 8.3 name
    name, ext = os.path.splitext(os.path.basename(targetname))
    name = name.upper().ljust(8)[:8]
    ext = ext[1:].upper().ljust(3)[:3]  # strip dot

    file_size = len(data)
    total_sectors = (file_size + SECTOR_SIZE - 1) // SECTOR_SIZE
    num_clusters = (total_sectors + SECTORS_PER_CLUSTER - 1) // SECTORS_PER_CLUSTER

    with open(dskfile, "r+b") as f:
        # sync geometry from this image
        boot = f.read(512)
        bpb = parse_bpb(boot)
        apply_bpb_to_globals(bpb)

        fat = read_fat(f)

        # If a file with this name already exists, free its old cluster
        # chain and reuse its directory slot instead of leaving it in
        # place and appending a brand new entry - otherwise the old,
        # stale copy stays on disk (and stays first in directory order,
        # so DOS keeps finding and running/reading it instead of the new
        # one) no matter how many times this is run.
        existing = find_existing_dir_entry(f, name, ext)
        if existing is not None:
            existing_pos, existing_start_cluster = existing
            free_cluster_chain(fat, existing_start_cluster)

        clusters = allocate_clusters(fat, num_clusters)

        # write data into clusters
        bytes_remaining = file_size
        data_pos = 0
        for cl in clusters:
            first_sector = cluster_to_first_sector(cl)
            f.seek(sector_offset(first_sector))
            to_write = min(SECTORS_PER_CLUSTER * SECTOR_SIZE, bytes_remaining)
            f.write(data[data_pos:data_pos + to_write])
            if to_write < SECTORS_PER_CLUSTER * SECTOR_SIZE:
                f.write(b"\x00" * (SECTORS_PER_CLUSTER * SECTOR_SIZE - to_write))
            bytes_remaining -= to_write
            data_pos += to_write

        # update FATs
        write_fat(f, fat)

        # reuse the existing entry's own slot if this is an overwrite,
        # otherwise claim a fresh one
        dir_pos = existing_pos if existing is not None else find_free_dir_entry(f)
        f.seek(dir_pos)
        f.write(name.encode("ascii"))   # 0-7
        f.write(ext.encode("ascii"))    # 8-10
        f.write(b"\x00")                # 11: attribute
        # 12-25: reserved/time/date/high-cluster/write time/date (14 bytes)
        f.write(b"\x00" * 14)
        # 26-27: starting cluster (low word)
        f.write(struct.pack("<H", clusters[0]))
        # 28-31: file size
        f.write(struct.pack("<I", file_size))

    print(f"File '{srcfile}' injected as '{name.strip()}.{ext.strip()}'")


# ---------- CLI ----------

def main():
    if len(sys.argv) < 2:
        show_usage()

    cmd = sys.argv[1].lower()

    try:
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

            dskfile, sep, targetname = raw_target.partition(":")
            if not sep or not targetname:
                raise ValueError("Target must be in format diskimage.dsk:NAME.EXT")

            print(f"Copying: {srcfile} to {dskfile}:{targetname}")
            inject_file(srcfile, dskfile, targetname)
            print("Done")

        else:
            raise ValueError(f"Unknown command: {cmd}")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
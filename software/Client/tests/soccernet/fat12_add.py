"""Add (or replace) a file in a FAT12 floppy image:  fat12_add.py image.dsk file [NAME.EXT]

Only what the MSXPi test disks need: 512-byte sectors, 8.3 names in the root
directory, no long names. Prints free space before and after.
"""
import struct, sys, os, time

def main(img_path, src, name=None):
    img = bytearray(open(img_path, 'rb').read())
    bps, spc, rsv, nfat, nroot, tot16, _, spf = struct.unpack_from('<HBHBHHBH', img, 11)
    assert bps == 512, bps
    fat0 = rsv * bps
    fat_len = spf * bps
    root0 = (rsv + nfat * spf) * bps
    data0 = root0 + nroot * 32
    nclus = (tot16 - (rsv + nfat * spf + nroot * 32 // bps)) // spc
    def fat_get(c):
        o = fat0 + c * 3 // 2
        v = img[o] | (img[o + 1] << 8)
        return (v >> 4) if c & 1 else (v & 0xFFF)
    def fat_set(c, val):
        for f in range(nfat):
            o = fat0 + f * fat_len + c * 3 // 2
            v = img[o] | (img[o + 1] << 8)
            v = ((v & 0x000F) | (val << 4)) if c & 1 else ((v & 0xF000) | val)
            img[o], img[o + 1] = v & 0xFF, v >> 8
    def free_clusters():
        return [c for c in range(2, nclus + 2) if fat_get(c) == 0]
    base = (name or os.path.basename(src)).upper()
    n, _, e = base.partition('.')
    ent_name = (n[:8].ljust(8) + e[:3].ljust(3)).encode('ascii')
    # remove an existing entry of that name
    slot = None
    for i in range(nroot):
        o = root0 + i * 32
        if img[o] == 0x00:
            if slot is None: slot = o
            break
        if img[o] == 0xE5:
            if slot is None: slot = o
            continue
        if bytes(img[o:o + 11]) == ent_name:
            c = struct.unpack_from('<H', img, o + 26)[0]
            while 2 <= c < 0xFF8:
                nxt = fat_get(c); fat_set(c, 0); c = nxt
            img[o] = 0xE5
            if slot is None: slot = o
    if slot is None: raise SystemExit("root directory full")
    data = open(src, 'rb').read()
    csize = spc * bps
    need = max(1, -(-len(data) // csize)) if data else 0
    free = free_clusters()
    print("%s: %d clusters free (%d bytes), need %d" % (os.path.basename(img_path), len(free), len(free) * csize, need))
    if need > len(free): raise SystemExit("not enough free space")
    chain = free[:need]
    for k, c in enumerate(chain):
        fat_set(c, chain[k + 1] if k + 1 < len(chain) else 0xFFF)
        chunk = data[k * csize:(k + 1) * csize].ljust(csize, b'\0')
        o = data0 + (c - 2) * csize
        img[o:o + csize] = chunk
    t = time.localtime()
    dos_time = (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2)
    dos_date = ((t.tm_year - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday
    ent = bytearray(32)
    ent[0:11] = ent_name
    ent[11] = 0x20
    struct.pack_into('<HHHHHHHI', ent, 12, 0, 0, 0, 0, 0, dos_time, dos_date, 0) if False else None
    struct.pack_into('<H', ent, 22, dos_time); struct.pack_into('<H', ent, 24, dos_date)
    struct.pack_into('<H', ent, 26, chain[0] if chain else 0); struct.pack_into('<I', ent, 28, len(data))
    img[slot:slot + 32] = ent
    open(img_path, 'wb').write(img)
    print("added %s (%d bytes) to %s" % (base, len(data), os.path.basename(img_path)))

if __name__ == '__main__':
    main(*sys.argv[1:4])

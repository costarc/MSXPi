"""Prints the loader's Fletcher-16 (mod 256) check values for soccer.rom and
confirms the ROM is the SHA-256 the patches were written against."""
import hashlib, sys
EXPECT_SHA256 = "b9536809a1784afb2e49a43d80ba9c6c8c15cd31ecbd6c284e9bf62c6927dcd4"
d = open(sys.argv[1] if len(sys.argv) > 1 else "soccer.rom", "rb").read()
a = b = 0
for x in d:
    a = (a + x) & 255
    b = (b + a) & 255
print("sha256 ok:", hashlib.sha256(d).hexdigest() == EXPECT_SHA256)
print("fletcher A=%02X B=%02X (loader expects ROM_SUM_A / ROM_SUM_B)" % (a, b))

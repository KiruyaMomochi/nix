"""Check the firmware-facing PE contract without running the application."""
import struct
import sys

b = open(sys.argv[1], "rb").read()
assert b[:2] == b"MZ", "missing DOS header"
pe = struct.unpack_from("<I", b, 0x3C)[0]
assert b[pe:pe + 4] == b"PE\0\0", "missing PE signature"
machine, sections, _, _, _, opt_size, flags = struct.unpack_from("<HHIIIHH", b, pe + 4)
assert machine == 0xAA64, "not AArch64"
assert flags & 0x0002, "not executable"
assert not flags & 0x2000, "must be an application, not a DLL"
opt = pe + 24
assert struct.unpack_from("<H", b, opt)[0] == 0x20B, "not PE32+"
assert struct.unpack_from("<I", b, opt + 16)[0] != 0, "missing entry point"
assert struct.unpack_from("<H", b, opt + 68)[0] == 10, "not EFI application subsystem"
assert struct.unpack_from("<II", b, opt + 112 + 8)[0:2] == (0, 0), "unexpected imports"
reloc_rva, reloc_size = struct.unpack_from("<II", b, opt + 112 + 5 * 8)
assert reloc_rva and reloc_size, "missing base relocations"
assert not flags & 0x0001, "base relocations stripped"
print("PE verified: AArch64, EFI application, no imports, relocatable")

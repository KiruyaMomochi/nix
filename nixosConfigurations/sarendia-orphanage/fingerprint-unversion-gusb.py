# The vendor lib was linked against a libgusb that exported these six symbols
# as LIBGUSB_0.1.0; upstream gusb exports them as LIBGUSB_0.2.8. Mark the
# references unversioned so they bind to the default version.
import sys
from elftools.elf.elffile import ELFFile

SYMS = {
    "g_usb_device_get_interfaces",
    "g_usb_device_get_release",
    "g_usb_interface_get_class",
    "g_usb_interface_get_number",
    "g_usb_interface_get_protocol",
    "g_usb_interface_get_subclass",
}

path = sys.argv[1]
with open(path, "rb") as f:
    elf = ELFFile(f)
    dynsym = elf.get_section_by_name(".dynsym")
    versym = elf.get_section_by_name(".gnu.version")
    offsets = [
        versym["sh_offset"] + 2 * i
        for i, sym in enumerate(dynsym.iter_symbols())
        if sym.name in SYMS
    ]

if len(offsets) != len(SYMS):
    sys.exit(f"expected {len(SYMS)} symbols, found {len(offsets)}")

with open(path, "r+b") as f:
    for off in offsets:
        f.seek(off)
        f.write((1).to_bytes(2, "little"))

#!/usr/bin/env python3
"""Patch new 8188eu.ko's 15 symbol CRCs with device's correct values"""
import struct
import sys

if sys.platform.startswith('linux'):
    SRC_KO = '/root/build/rtl8188eu-master/8188eu.ko'
    DST_KO = '/mnt/f/Debug/8188eu_new_v3_patched.ko'
else:
    SRC_KO = r'F:\Debug\8188eu_new_v3.ko'
    DST_KO = r'F:\Debug\8188eu_new_v3_patched.ko'

# Device's correct CRCs (10 USB + 5 new from getcrc3.ko)
CORRECT_CRC = {
    # 10 USB symbols (from getcrc2.ko)
    'usb_put_dev':               0x23a0af6b,
    'usb_alloc_urb':             0x2a28f0f5,
    'usb_kill_urb':              0xc6bf4c8c,
    'usb_control_msg':           0xcff3367a,
    'usb_deregister':            0xabe45a4a,
    'usb_autopm_get_interface':  0x38a487e0,
    'dev_get_by_name':           0x70adb9af,
    'usb_free_urb':              0x1260899e,
    'usb_submit_urb':            0xc241383a,
    'usb_register_driver':       0x9983d0f3,
    # 5 new symbols (from getcrc3.ko)
    'usb_reset_device':          0x624fc04a,
    'usb_get_dev':               0x9e77c9f3,
    'netif_device_attach':       0xe7c62d28,
    'request_firmware':          0x3c04d96c,
    'release_firmware':          0xf8417e51,
}

with open(SRC_KO, 'rb') as f:
    data = bytearray(f.read())

e_shoff = struct.unpack('<Q', data[0x28:0x30])[0]
e_shentsize = struct.unpack('<H', data[0x3A:0x3C])[0]
e_shnum = struct.unpack('<H', data[0x3C:0x3E])[0]
e_shstrndx = struct.unpack('<H', data[0x3E:0x40])[0]

sections = []
for i in range(e_shnum):
    off = e_shoff + i * e_shentsize
    sh_name = struct.unpack('<I', data[off:off+4])[0]
    sh_offset = struct.unpack('<Q', data[off+24:off+32])[0]
    sh_size = struct.unpack('<Q', data[off+32:off+40])[0]
    sections.append({'name_off': sh_name, 'offset': sh_offset, 'size': sh_size})

shstr_off = sections[e_shstrndx]['offset']
for s in sections:
    end = data.find(b'\x00', shstr_off + s['name_off'])
    s['name'] = data[shstr_off + s['name_off']:end].decode('ascii', errors='replace')

versions_sec = None
for s in sections:
    if s['name'] == '__versions':
        versions_sec = s
        break

print(f"__versions: {versions_sec['size'] // 64} entries")
print()

patched_count = 0
not_found = list(CORRECT_CRC.keys())

for i in range(versions_sec['size'] // 64):
    off = versions_sec['offset'] + i * 64
    crc = struct.unpack('<Q', data[off:off+8])[0]
    name = data[off+8:off+64].split(b'\x00')[0].decode('ascii', errors='replace')

    if name in CORRECT_CRC:
        new_crc = CORRECT_CRC[name]
        old_crc_low32 = crc & 0xFFFFFFFF
        match = "already correct" if old_crc_low32 == new_crc else "PATCHING"
        print(f"  {name}: 0x{old_crc_low32:08x} -> 0x{new_crc:08x} [{match}]")

        if old_crc_low32 != new_crc:
            struct.pack_into('<Q', data, off, new_crc)
            patched_count += 1

        not_found.remove(name)

if not_found:
    print(f"\nWARNING: {len(not_found)} symbols not found in __versions:")
    for name in not_found:
        print(f"  {name}")

print(f"\nPatched {patched_count} CRCs")

with open(DST_KO, 'wb') as f:
    f.write(data)

print(f"Output: {DST_KO}")
print(f"Size: {len(data)} bytes")

#!/usr/bin/env python3
"""Generate embedded firmware C header from binary blob"""
import sys

src_bin = '/mnt/c/Users/Administrator/AppData/Roaming/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6a576966a234771c48c5f1e8/rtl8188eufw.bin'
dst_hdr = '/root/build/rtl8188eu-master/hal/rtl8188eufw_embedded.h'

with open(src_bin, 'rb') as f:
    data = f.read()

with open(dst_hdr, 'w') as out:
    out.write('/* Auto-generated embedded firmware for rtl8188eu */\n')
    out.write('static const unsigned char rtl8188eufw_bin[] = {\n')
    for i in range(0, len(data), 12):
        line = data[i:i+12]
        out.write('  ' + ','.join('0x%02x' % b for b in line) + ',\n')
    out.write('};\n')
    out.write('static const unsigned int rtl8188eufw_bin_len = %d;\n' % len(data))

print(f'Generated {dst_hdr}: {len(data)} bytes, {len(data)//12 + 1} lines')

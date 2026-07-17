#!/usr/bin/env python3
"""Patch load_firmware to use embedded firmware data, bypassing all file I/O"""
import re

SRC = '/root/build/rtl8188eu-master/hal/rtl8188e_hal_init.c'

with open(SRC, 'r') as f:
    content = f.read()

# 1. Add include for embedded firmware header (after last #include in the file's top block)
# Find a stable anchor: the IS_FW_81xxC define line
include_line = '#include "rtl8188eufw_embedded.h"\n'
if 'rtl8188eufw_embedded.h' not in content:
    content = content.replace(
        '#define IS_FW_81xxC(padapter)',
        include_line + '\n#define IS_FW_81xxC(padapter)',
        1
    )

# 2. Replace the entire load_firmware function body
# Match from "static int load_firmware" to the next "Exit:" + closing brace
new_func = '''static int load_firmware(struct rt_firmware *pFirmware, struct device *device)
{
\ts32 rtStatus = _SUCCESS;

\tpr_info("rtw: using embedded firmware (%u bytes)\\n", rtl8188eufw_bin_len);

\tpFirmware->szFwBuffer = kzalloc(FW_8188E_SIZE, GFP_KERNEL);
\tif (!pFirmware->szFwBuffer) {
\t\tpr_err("rtw: kzalloc failed for firmware buffer\\n");
\t\trtStatus = _FAIL;
\t\tgoto Exit;
\t}
\tmemcpy(pFirmware->szFwBuffer, rtl8188eufw_bin, rtl8188eufw_bin_len);
\tpFirmware->ulFwLength = rtl8188eufw_bin_len;
\tDBG_88E_LEVEL(_drv_info_, "+%s: !bUsedWoWLANFw, FmrmwareLen:%d+\\n", __func__, pFirmware->ulFwLength);

Exit:
\treturn rtStatus;
}'''

# Match the old function: from "static int load_firmware" to the line "Exit:\n\treturn rtStatus;\n}"
# Use regex with DOTALL
pattern = r'static int load_firmware\(struct rt_firmware \*pFirmware, struct device \*device\)\s*\{.*?\nExit:\n\treturn rtStatus;\n\}'
m = re.search(pattern, content, re.DOTALL)
if m:
    print(f'Found old load_firmware: {len(m.group(0))} chars, lines ~{m.group(0).count(chr(10))}')
    content = content[:m.start()] + new_func + content[m.end():]
    print('Replaced with embedded version')
else:
    print('ERROR: Could not find load_firmware function')
    # Try to find what's there
    idx = content.find('static int load_firmware')
    if idx >= 0:
        print('Context around load_firmware:')
        print(content[idx:idx+200])
    exit(1)

with open(SRC, 'w') as f:
    f.write(content)

print(f'Patched {SRC}')

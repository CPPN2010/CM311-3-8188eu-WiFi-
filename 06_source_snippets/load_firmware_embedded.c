/*
 * Modified load_firmware() - uses embedded firmware, bypasses file I/O
 * File: hal/rtl8188e_hal_init.c
 *
 * Reason: Android 9 request_firmware()/kernel_read() returns -22 (EINVAL)
 * because vfs_read() FMODE_CAN_READ check fails. Embedding the firmware
 * binary as a static const array completely bypasses all file I/O.
 *
 * Requires: #include "rtl8188eufw_embedded.h" at top of file
 */

#include "rtl8188eufw_embedded.h"

#define IS_FW_81xxC(padapter)   (((GET_HAL_DATA(padapter))->FirmwareSignature & 0xFFF0) == 0x88C0)

static int load_firmware(struct rt_firmware *pFirmware, struct device *device)
{
    s32 rtStatus = _SUCCESS;

    pr_info("rtw: using embedded firmware (%u bytes)\n", rtl8188eufw_bin_len);

    pFirmware->szFwBuffer = kzalloc(FW_8188E_SIZE, GFP_KERNEL);
    if (!pFirmware->szFwBuffer) {
        pr_err("rtw: kzalloc failed for firmware buffer\n");
        rtStatus = _FAIL;
        goto Exit;
    }
    memcpy(pFirmware->szFwBuffer, rtl8188eufw_bin, rtl8188eufw_bin_len);
    pFirmware->ulFwLength = rtl8188eufw_bin_len;
    DBG_88E_LEVEL(_drv_info_, "+%s: !bUsedWoWLANFw, FmrmwareLen:%d+\n", __func__, pFirmware->ulFwLength);

Exit:
    return rtStatus;
}

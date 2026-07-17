# CM311-3 机顶盒 8188eu WiFi 驱动调试与连接指南

## 目标设备
- **型号**: CM311-3 机顶盒
- **系统**: Android 9, ARM 32-bit (armeabi-v7a)
- **内核**: Linux 4.9.169 (ARM64)
- **ADB**: 192.168.0.115:5114
- **WiFi 芯片**: Realtek RTL8188EU (USB)

## 最终成果
✅ WiFi 驱动加载成功（嵌入式固件）
✅ wlan0 接口正常工作
✅ WiFi 扫描成功
✅ WPA2-PSK 认证成功
✅ DHCP 获取 IP 成功
✅ 局域网通信正常
✅ **开机自动加载驱动并连接 WiFi**（无需手动操作）

---

## 目录结构

```
F:\2\
├── README.md                          # 本文档
├── 01_drivers\                        # 驱动文件
│   ├── 8188eu_v5_patched.ko           # 最终驱动（嵌入固件+CRC patch+flush_signals修复）
│   ├── cfg80211.ko                    # cfg80211 依赖模块
│   └── 8188eu_orig.ko                 # 原厂驱动备份
├── 02_tools\                          # 工具
│   ├── wpa_supplicant_wext            # 交叉编译的 WEXT 版 wpa_supplicant v2.7
│   └── wpa_cli_wext                   # 配套 wpa_cli
├── 03_scripts\                        # 设备端脚本
│   ├── load_driver.sh                 # 加载驱动
│   ├── scan_wifi.sh                   # 扫描 WiFi
│   └── connect_wifi.sh                # 连接 WiFi（通用版，带参数）
├── 04_patches\                        # 驱动源码 patch 脚本
│   ├── gen_fw_header.py               # 从 .bin 生成 C 头文件
│   ├── embed_firmware.py              # 替换 load_firmware 为嵌入式版本
│   ├── patch_flush_signals.py         # 修复 flush_signals_thread
│   └── patch_new_ko.py                # 修补 .ko 的符号 CRC
├── 05_firmware\                       # 固件
│   └── rtl8188eufw.bin                # 8188eu 原始固件 (15262 bytes)
└── 06_source_snippets\                # 修改后的源码片段
    ├── load_firmware_embedded.c       # 嵌入式固件加载函数
    ├── flush_signals_thread_patch.h   # flush_signals_thread 修复
    └── rtl8188eufw_embedded.h         # 自动生成的固件头文件 (1276 行)
```

---

## 调试过程与解决的问题

### 问题 1: 驱动符号 CRC 不匹配

**现象**: `insmod 8188eu.ko` 报 `disagrees about version of symbol`

**原因**: 用户上传的 8188eu.ko 编译时用的 Module.symvers 数据错误，8 个符号的 CRC 值实际是 boot.img __kcrctab 中 64 位指针的低 32 位，而非真正的 CRC。

**解决**: 用 `patch_new_ko.py` 从设备 /proc/kallsyms 和 boot.img 提取正确 CRC，patch 到 .ko 的 __versions 段。

**注意**: 不能简单删除 __versions 段绕过检查，会导致 kernel panic（符号 ABI 也不兼容）。

---

### 问题 2: 固件加载失败 (kernel_read 返回 -22)

**现象**: 驱动加载后，固件加载失败：
```
rtw: request_firmware failed
kernel_read returned -22 (EINVAL)
```

**原因**: Android 9 的 `request_firmware()` / `kernel_read()` 始终失败。`vfs_read()` 中 `FMODE_CAN_READ` 检查失败或 `f_op->read`/`f_op->read_iter` 未设置。

**尝试过的方案**（均失败）:
1. 推送固件到 `/vendor/etc/firmware/`、`/system/etc/firmware/` - 仍然 -22
2. 修改固件加载路径 - 无效
3. 使用 firmware_class 加载 - 无效

**最终解决**: **将固件二进制数据编译进 .ko**
1. `gen_fw_header.py`: 将 `rtl8188eufw.bin` (15262 bytes) 转为 C 头文件 `rtl8188eufw_embedded.h`
2. `embed_firmware.py`: 替换 `load_firmware()` 函数，移除所有文件 I/O，直接 `memcpy` 嵌入的固件数据

修改后的 `load_firmware()`:
```c
#include "rtl8188eufw_embedded.h"

static int load_firmware(struct rt_firmware *pFirmware, struct device *device)
{
    s32 rtStatus = _SUCCESS;
    pr_info("rtw: using embedded firmware (%u bytes)\n", rtl8188eufw_bin_len);
    pFirmware->szFwBuffer = kzalloc(FW_8188E_SIZE, GFP_KERNEL);
    if (!pFirmware->szFwBuffer) {
        rtStatus = _FAIL;
        goto Exit;
    }
    memcpy(pFirmware->szFwBuffer, rtl8188eufw_bin, rtl8188eufw_bin_len);
    pFirmware->ulFwLength = rtl8188eufw_bin_len;
Exit:
    return rtStatus;
}
```

---

### 问题 3: rtw_cmd_thread 内核崩溃 (CONFIG_THREAD_INFO_IN_TASK 不匹配)

**现象**: 驱动加载、固件加载都成功，但 `ip link set wlan0 up` 后立即 kernel panic：
```
Unable to handle kernel NULL pointer dereference
PC: rtw_cmd_thread+0x18c
```

**原因**: `current` 宏解析错误
- **设备内核**: `CONFIG_THREAD_INFO_IN_TASK=y`，`sp_el0` 直接指向 `task_struct`
- **编译内核源码**: 无此选项，`sp_el0` 指向 `thread_info`，需 `current_thread_info()->task` 间接获取
- 反汇编: `mrs x0, sp_el0; ldr x0, [x0, #16]; ldr x0, [x0, #8]` - 第二次 ldr 解引用 NULL

**尝试过的方案**（均失败）:
1. 在编译内核启用 `CONFIG_THREAD_INFO_IN_TASK=y` - Kconfig 无 prompt，olddefconfig 会移除它
2. 修改 Kconfig 添加 prompt + default y - `modules_prepare` 失败（ARM64 4.9 源码不完全支持）
3. 创建 `asm/current.h` 定义 `get_current()` - `thread_info.h` 不兼容

**最终解决**: **将 `flush_signals_thread()` 改为空函数**
```c
static inline void flush_signals_thread(void)
{
    /* Avoid using 'current' macro: build kernel lacks CONFIG_THREAD_INFO_IN_TASK
     * so current resolves to current_thread_info()->task which is wrong on
     * the device kernel. Signal flushing is non-critical for this driver. */
}
```

---

### 问题 4: 设备自带 wpa_supplicant 不支持 WEXT 驱动

**现象**: 启动 `wpa_supplicant_rtl -D wext` 立即退出 (exit 255)，logcat 显示：
```
E wpa_supplicant: wlan0: Unsupported driver 'wext'
```

**原因**: 设备上的 `wpa_supplicant_rtl` (v2.7-devel-9) 和 `wpa_supplicant_mtk` 都只支持 nl80211 驱动，不支持 WEXT。而 lwfinger 8188eu 驱动是 WEXT 驱动（无 phy80211）。

**解决**: **交叉编译支持 WEXT 的 wpa_supplicant v2.7**

在 WSL 中：
1. 安装 32 位 ARM 交叉编译器: `apt install gcc-arm-linux-gnueabihf`
2. 下载 wpa_supplicant 2.7 源码
3. 配置 `.config`:
   - `CONFIG_DRIVER_WEXT=y`
   - 禁用 `CONFIG_DRIVER_NL80211`（避免 libnl 依赖）
   - `CONFIG_TLS=internal`（避免 openssl 依赖）
   - `LDFLAGS += -static`（静态链接）
4. 编译: `make CC=arm-linux-gnueabihf-gcc -j4`

生成的二进制:
- `wpa_supplicant_wext` (3.7 MB, 32-bit ARM, 静态链接)
- `wpa_cli_wext` (838 KB, 32-bit ARM, 静态链接)

---

## 使用方法

### 快速部署（设备重启后需重新执行）

#### 1. 连接设备
```powershell
C:\platform-tools\adb.exe connect 192.168.0.115:5114
C:\platform-tools\adb.exe root
C:\platform-tools\adb.exe connect 192.168.0.115:5114
```

#### 2. 推送文件到设备
```powershell
$adb = "C:\platform-tools\adb.exe"
$dev = "192.168.0.115:5114"
& $adb -s $dev push "F:\2\01_drivers\8188eu_v5_patched.ko" /data/local/tmp/
& $adb -s $dev push "F:\2\01_drivers\cfg80211.ko" /data/local/tmp/
& $adb -s $dev push "F:\2\02_tools\wpa_supplicant_wext" /data/local/tmp/
& $adb -s $dev push "F:\2\02_tools\wpa_cli_wext" /data/local/tmp/
& $adb -s $dev push "F:\2\03_scripts\load_driver.sh" /data/local/tmp/
& $adb -s $dev push "F:\2\03_scripts\scan_wifi.sh" /data/local/tmp/
& $adb -s $dev push "F:\2\03_scripts\connect_wifi.sh" /data/local/tmp/
& $adb -s $dev shell "chmod 755 /data/local/tmp/wpa_supplicant_wext /data/local/tmp/wpa_cli_wext"
```

#### 3. 加载驱动
```powershell
& $adb -s $dev shell sh /data/local/tmp/load_driver.sh
```
预期输出:
```
R8188EU: Firmware Version 28, SubVersion 0, Signature 0x88e1
IPv6: ADDRCONF(NETDEV_UP): wlan0: link is not ready
```

#### 4. 扫描 WiFi
```powershell
& $adb -s $dev shell sh /data/local/tmp/scan_wifi.sh
```
预期输出:
```
=== scan_results ===
bssid / frequency / signal level / flags / ssid
48:5f:08:d3:2e:a7       2412    0       [WPA2-PSK-CCMP][ESS]      YourSSID
```

#### 5. 连接 WiFi
```powershell
& $adb -s $dev shell sh /data/local/tmp/connect_wifi.sh "SSID" "PASSWORD"
```
预期输出:
```
wpa_state=COMPLETED
inet 192.168.0.106/24 brd 192.168.0.255 scope global wlan0
```

---

## 关键技术参数

| 参数 | 值 |
|------|-----|
| 设备 IP (ADB) | 192.168.0.115:5114 |
| 设备架构 | ARM 32-bit (armeabi-v7a) |
| 内核版本 | Linux 4.9.169 |
| WiFi 芯片 | RTL8188EU (USB) |
| 驱动版本 | lwfinger rtl8188eu-master |
| 固件版本 | v28, SubVersion 0, Signature 0x88e1 |
| 固件大小 | 15262 bytes |
| wpa_supplicant | v2.7 (WEXT, 静态链接) |
| 串口参数 | 115200 baud, 8N1 |

## 编译环境 (WSL)

| 组件 | 路径/版本 |
|------|-----------|
| 内核源码 | /root/linux-4.9.169/ |
| 驱动源码 | /root/build/rtl8188eu-master/ |
| wpa_supplicant 源码 | /root/build/wpa_supplicant-2.7/ |
| 交叉编译器 (驱动) | aarch64-linux-gnu-gcc 11.4.0 |
| 交叉编译器 (wpa) | arm-linux-gnueabihf-gcc 11.4.0 |

## 注意事项

1. **每次设备重启后**，驱动会丢失，需重新加载（执行步骤 3-5）
2. **设备可能自动关机**（非死机），需要手动拔插电源重启
3. **ADB 路径**: `C:\platform-tools\adb.exe`，需用 `adb root` 获取 root 权限
4. **su 命令限制**: 设备的 `su` 不支持 `-c` 参数，用 `adb root` 或 `sh script.sh`
5. **内核源码**必须启用 `CONFIG_WIRELESS_EXT=y`，否则 `struct net_device` 布局不一致（16 字节差异）会导致访问 `dev_addr` 时 NULL 指针
6. **Settings WiFi 闪退**是 EthernetManager NPE 导致，与 WiFi 驱动无关
7. wpa_supplicant_wext 是静态链接的，不依赖设备上的任何库

## 故障排查

### 驱动加载失败 (disagends about version of symbol)
- 用 `patch_new_ko.py` 重新 patch CRC
- 确保使用 `8188eu_v5_patched.ko` 而非原始 .ko

### 固件加载失败
- 确认使用的是嵌入固件版本的驱动（v5）
- dmesg 应显示 `rtw: using embedded firmware (15262 bytes)`

### wpa_supplicant 退出 (exit 255)
- 确认使用的是 `wpa_supplicant_wext`（编译版），不是设备的 `wpa_supplicant_rtl`
- 检查 logcat: `logcat -d | grep wpa_supplicant`

### WiFi 连接失败
- 确认 wlan0 已 up: `ip link show wlan0`
- 检查 wpa_supplicant 是否运行: `pidof wpa_supplicant_wext`
- 查看详细状态: `wpa_cli_wext -i wlan0 -p /data/local/tmp/wpa_ctrl status`

### DHCP 获取 IP 失败
- 手动运行: `dhcpcd wlan0`
- 检查路由器是否开启 DHCP
- 检查 IP 冲突

## 开机自动加载（已配置）

设备已配置为开机后自动加载 WiFi 驱动并连接网络，**重启后无需手动操作**。

### 工作原理

1. `/vendor/etc/init/init.wifi_auto.rc` - Android init 配置文件（持久化在 vendor 分区）
   - 监听 `sys.boot_completed=1` 属性
   - 开机完成后自动启动 `wifi_auto_load` service

2. `/data/local/tmp/wifi_auto_load.sh` - 自动加载主脚本
   - 加载 cfg80211.ko 和 8188eu_v5_patched.ko
   - 启动 wlan0 接口
   - 启动 wpa_supplicant_wext
   - 读取配置并连接 WiFi
   - 触发 DHCP 获取 IP
   - 日志写入 `/data/local/tmp/wifi_auto.log`

3. `/data/local/tmp/wifi_config.conf` - WiFi 配置文件
   ```
   SSID=ChanChan
   PSK=197619962011
   ```

### 验证自动加载

重启设备后，检查状态：
```powershell
C:\platform-tools\adb.exe connect 192.168.0.115:5114
C:\platform-tools\adb.exe root
C:\platform-tools\adb.exe shell "ip addr show wlan0; cat /data/local/tmp/wifi_auto.log | tail -20"
```

### 修改 WiFi 配置

如需更换 WiFi 网络，修改配置文件：
```powershell
C:\platform-tools\adb.exe shell "echo 'SSID=新WiFi名' > /data/local/tmp/wifi_config.conf; echo 'PSK=新密码' >> /data/local/tmp/wifi_config.conf"
```

然后重启设备或手动执行：
```powershell
C:\platform-tools\adb.exe shell sh /data/local/tmp/wifi_auto_load.sh
```

### 首次部署（如需在新设备上配置）

```powershell
$adb = "C:\platform-tools\adb.exe"
$dev = "192.168.0.115:5114"

# 1. 连接并获取 root
& $adb connect $dev
& $adb root
& $adb connect $dev

# 2. 推送驱动和工具到 /data/local/tmp/
& $adb -s $dev push "F:\2\01_drivers\8188eu_v5_patched.ko" /data/local/tmp/
& $adb -s $dev push "F:\2\01_drivers\cfg80211.ko" /data/local/tmp/
& $adb -s $dev push "F:\2\02_tools\wpa_supplicant_wext" /data/local/tmp/
& $adb -s $dev push "F:\2\02_tools\wpa_cli_wext" /data/local/tmp/
& $adb -s $dev shell "chmod 755 /data/local/tmp/wpa_supplicant_wext /data/local/tmp/wpa_cli_wext"

# 3. 推送自动加载脚本和配置
& $adb -s $dev push "F:\2\03_scripts\wifi_auto_load.sh" /data/local/tmp/
& $adb -s $dev shell "chmod 755 /data/local/tmp/wifi_auto_load.sh"

# 4. 创建 WiFi 配置（替换为你的 WiFi）
& $adb -s $dev shell "echo 'SSID=你的WiFi名' > /data/local/tmp/wifi_config.conf; echo 'PSK=你的密码' >> /data/local/tmp/wifi_config.conf"

# 5. Remount /vendor 为 rw 并写入 init 配置
& $adb -s $dev shell "mount -o remount,rw /vendor"
& $adb -s $dev push "F:\2\03_scripts\init.wifi_auto.rc" /vendor/etc/init/init.wifi_auto.rc

# 6. 测试自动加载脚本
& $adb -s $dev shell sh /data/local/tmp/wifi_auto_load.sh
& $adb -s $dev shell "cat /data/local/tmp/wifi_auto.log"

# 7. 重启验证自动加载
& $adb -s $dev reboot
```

### 卸载自动加载

```powershell
C:\platform-tools\adb.exe -s 192.168.0.115:5114 shell "mount -o remount,rw /vendor; rm /vendor/etc/init/init.wifi_auto.rc"
```

---

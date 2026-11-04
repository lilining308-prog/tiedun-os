# 铁盾 OS 1.0.2.4 刷机指南与验证清单（小米 8 / dipper）

> ⚠️ 刷机有风险；操作前务必备份数据。本指南按交接清单 B13 编写，成品包验证后定稿。

## 一、准备
- 解锁 Bootloader（小米官方解锁工具）
- 电脑已装 adb / fastboot（platform-tools）
- 下载：铁盾 OS 刷机包 zip、MIUI 基带固件包（官方 V12.5.2.0.QEACNXM：
  `https://bn.d.miui.com/V12.5.2.0.QEACNXM/miui_MI8_V12.5.2.0.QEACNXM_f5ec813d1c_10.0.zip`，解压取 firmware-update/ 目录）

## 二、刷入步骤
1. **基带固件**（首次或跨 ROM 必刷）：进 fastboot，逐个刷 firmware-update/ 下的 img：
   abl aop bluetooth cmnlib devcfg dsp hyp keymaster logo modem qupfw storsec tz xbl 等
   （`fastboot flash <分区> <img>`；分区名与文件名对应，xbl 刷 xbl xbl_config 两处时按文件名）
2. **Recovery/TWRP 或 Lineage Recovery**：`fastboot flash recovery recovery.img`（如需）
3. **刷入系统包**：
   - fastboot 引导 recovery 后 sideload：`adb sideload 铁盾OS-1.0.2.4-dipper.zip`
   - 或线刷方式（如包内含 payload）
4. **必须 format data**（跨 ROM 铁律，不清会反复重启/加密错乱）
5. **dtbo 必须随 4.19 内核一起刷**（铁律）：`fastboot flash dtbo dtbo.img`
   （若 zip 为 AnyKernel3 内核补丁包，与本系统包配套顺序：先刷系统包，再刷内核补丁包）
6. 重启（首次开机 5-10 分钟属正常）

## 三、救砖
- 黑屏/卡米：fastboot 全线刷回（步骤1的全部 img + boot.img + dtbo.img）即可恢复
- 无限重启：进 recovery format data 后重启

## 四、验证清单（刷完逐项过）
| 项 | 命令/操作 | 预期 |
|---|---|---|
| WiFi 无异常 | 连家用 WiFi | 无叹号、无「网络异常」弹窗 |
| Captive portal | `adb shell settings get global captive_portal_http_url` | 国内可达 generate_204 地址 |
| 内核 | `adb shell uname -a` | 4.19.325 系 |
| 关于页 | 设置 → 关于手机 | 六组版本齐全（全称）+ 鸣谢页 |
| KernelSU | 安装 KSU 管理器 | 显示「已安装/Active」；`adb shell ls /data/adb/ksu` 存在 |
| Shizuku | Shizuku App | 开机自启、显示运行中、已自动授权铁盾 |
| 铁盾之盾 | 打开 App | root 通道免弹窗可用 |
| 相机 | 打开 Snap | 预览/拍照正常 |
| 调度档位 | 设置中切换 | 均衡/性能/省电 生效 |

## 五、已知限制（Q11 先出包后抛光）
- 个别硬件可能打折（详见随包 KNOWN-ISSUES），后续版本迭代
- SELinux 状态以实际包为准（见 KNOWN-ISSUES）

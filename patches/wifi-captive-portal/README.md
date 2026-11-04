# WiFi "老是提示异常" 修复补丁

## 病因
Android 联网验证（captive portal）默认访问 Google 服务器
（connectivitycheck.gstatic.com / play.googleapis.com），国内不可达 →
每次连 WiFi 都被判"网络异常/连接受限"，图标带叹号、反复弹提示。
用户现用 lineage-23.2 包即此症状（非 WiFi 驱动问题）。

## 修复（随 A17 包进设备树）
1. overlay/：把 NetworkStack 的 captive_portal_http(s)_url 改为
   connect.rom.miui.com/generate_204（主）+ wifi.qq.com/generate_204（备）
2. 默认 captive_portal_mode 保持 1（提示），但验证走国内服务器后自然通过，不再弹
3. 兜底：device.mk 里预置 Settings.Global 默认值（captive_portal_*_url）

## 应用方式（编译阶段）
把 wifi-captive-portal/overlay/ 目录内容合并进 device/xiaomi/dipper/overlay/，
并在 device.mk 追加：
  DEVICE_PACKAGE_OVERLAYS += device/xiaomi/dipper/overlay
（官方 dipper 树已有 DEVICE_PACKAGE_OVERLAYS，合并目录即可）

## 验证方法（刷机后）
adb shell settings get global captive_portal_http_url   # 应输出 generate_204 地址
连 WiFi 后不应再出现"网络异常/网络连接受限"提示，图标无叹号

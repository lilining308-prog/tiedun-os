# 铁盾 OS 1.0.2.4 变更记录（CHANGELOG）

## 1.0.2.4（本次交付）
- Android 17（LineageOS 24.0 底包）+ 4.19 内核（4.19.325-CIP 系，perf 血统）
- 内置 KernelSU（KernelSU-Next 12759 + SUSFS），默认激活，KSU 模块 tiedun-priv 预置白名单
- WiFi「网络异常」修复：captive portal 验证地址改国内可达节点（B1 补丁）
- 预装三件套：铁盾之盾 v3.0-adb / Shizuku v13.6.0 / FOSS Browser（默认浏览器，移除 Jelly）
- 开机动画：静态黑底纯文字「TieDun OS 1.0.2.4」+ Powered by Android（无 logo）
- 关于页：黑渐变 hero + 六组全称版本行 + 鸣谢页（四组致敬链 + 署名）
- 简体中文 + 北京时区默认；默认加密（开机向导可选）
- 可切换调度档位：均衡 / 性能 / 省电
- 装卸策略：系统应用卸载二次确认 + 凭据验证（无密码强制设密）；普通应用二次确认直删；
  安装全放行 + 降级强装醒目提示 + 签名异常三选项弹窗
- 相机：Snap 优先 / Aperture 兜底
- 版本属性 ro.tiedun.* 六组进 build.prop

## 已知限制（Q11 先出包后抛光）
见 KNOWN-ISSUES.md

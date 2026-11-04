# 铁盾 OS 1.0.2.4 已知问题（KNOWN-ISSUES）

> Q11 妥协授权：先出包后抛光。本页如实记录，后续版本迭代。

## 编译适配类（A 系列）
1. wfd 无线显示：其 blob 依赖与 24.0 平台音频 AIDL 版本冲突，37 个 wfd 预编译模块的
   shared_libs 已清空（不影响加载，仅影响构建期声明）。wfd 运行时表现待实机验证。
2. 显示栈：采用 qcom-caf/sdm845 display HAL（清单钦定）；非 CAF 旧树已移出构建。
   与 stock blob 并存的最终选择待实机验证（gralloc/hwcomposer 选择器）。
3. vendor/lineage/config/device_framework_matrix.xml 为 22.2 时代文件补齐（24.0 上游已移除）。

## 硬件类
4. SELinux 状态：如 enforcing 下 tiedun-priv 首启自装未生效，重启一次即生效（设计如此）。
5. 其他硬件打折项以实机验证为准，欢迎反馈补录。

## 界面类
6. 关机动画：已随包提供 shutdownanimation.zip（同款缩小字标）；如系统未接关机动画播放点，
   则仅静态黑屏（属抛光项）。
7. 「Google 安全补丁级别」按定稿格式 YYYY-MM-05 展示（日固定 05，月份取源码真值）。
8. 「M3E 大磁贴通知栏/控制中心样式」: Android 17 平台 SystemUI 即 Material 3 Expressive
   大磁贴样式(Pixel 风由平台自带); 风格层独立 overlay(TieDunFrameworkOverlay)已预留可整体替换,
   深度自定义留作抛光迭代。
9. 「默认加密」: Android 17 强制 FBE, 出厂即加密(满足); 开机向导锁屏可跳过、设置中可随时更改。
10. 「系统层(动画曲线等)」: 按模仿深度界定③「只挑性价比高的做」, 本次未拾取, 留作迭代。
11. 系统应用「可卸」= 对当前用户卸载(隐藏+清数据), 不物理删除 /product 分区文件(需 root, 属迭代项)。
12. 相机: Snap(org.codeaurora.snapcam)上游止步 lineage-18.1(Android 11), A17 移植代价过大,
    按冻结授权「Snap优先,Aperture兜底」采用 Aperture(tree 内置, Lineage 官方相机)。

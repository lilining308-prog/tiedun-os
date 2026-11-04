# B7 装卸策略 · 施工设计（framework 改造）

> 需求冻结(第十一节 11/12): 系统应用卸载=二次确认+锁屏密码(无密码强制设密)；
> 普通应用=二次确认直删；安装=全放行+降级强装醒目提示+签名异常三选项弹窗。
> 注意: 24.0 实际路径为 **frameworks/base/packages/PackageInstaller**
> (包 com.android.packageinstaller.handheld), 清单旧写 packages/apps/PackageInstaller 已作废。

## 1. 卸载确认(UninstallAlertDialogFragment.java)
- 系统应用(isSystemApp): 确认按钮点击 → KeyguardManager.isDeviceSecure()
  - 已设密: 启动 ConfirmDeviceCredential(ActivityOptions 创建确认凭据), RESULT_OK 后才继续卸载
  - 无密码: 启动 ChooseLockGeneric(Settings.ACTION_BIOMETRIC_ENROLL? no —
    Settings.ACTION_CHOOSE_LOCK_GENERIC, extra password_only=true), 设密完成回来再走确认
- 普通应用: 确认即删(仅二次确认, 无凭据)
- 对话框文案: 系统应用标题「卸载系统应用」+ 正文说明不可逆 + 按钮【卸载/取消】

## 2. 安装放行(PackageInstallerActivity.java / InstallStaging)
- 默认全放行: 未知来源检查处直接放行(冻结需求: 安装默认全放行)
- 降级: 解析 INSTALL_FAILED_VERSION_DOWNGRADE 时弹醒目提示(红字)【强制安装/取消】,
  强制安装走 INSTALL_ALLOW_DOWNGRADE + DELETE_ALL_USERS(先卸后装)
- 签名不一致(INSTALL_FAILED_UPDATE_INCOMPATIBLE / signatures differ):
  弹窗【强制安装/取消/关闭】; 强制安装=卸载旧包(保数据选项另行)后全新安装

## 3. PMS 侧(services/core/java/com/android/server/pm)
- DeletePackageHelper: 允许 DELETE_SYSTEM_APP 真实卸载(system app 从 packages.xml 移除
  并隐藏系统副本; KSU root 通道配合保底)
- InstallPackageHelper: 降级/签名校验失败改为返回可强装的错误码(供安装器弹窗),
  不静默拦截

## 4. 凭据验证工具(TieDunCredentialGate, 新增类)
- static void verify(Activity host, int requestCode, Runnable onPass):
  isDeviceSecure ? ConfirmDeviceCredential : ChooseLockGeneric→回来继续

## 5. 实施顺序(67 恢复后)
1) 读实际源码锚点(UninstallAlertDialogFragment/PackageInstallerActivity/DeletePackageHelper)
2) 新增 TieDunCredentialGate + 对话框文案资源
3) 锚点 python 补丁(带 assert, 锚点失配立即报错不落盘)
4) 单编验证: m frameworks/base 与 m PackageInstaller 模块级编译
5) 并入全量构建

# B8 调度档位 · 施工设计
- 三档: 均衡/性能/省电。参考 Lineage 硬件配置(power HAL / lineage-sdk 性能档 API)。
- 实施位: XiaomiParts(device/xiaomi/sdm845-common/XiaomiParts)加「性能档位」三选一,
  或 lineage-sdk PerformanceProfile 接口(若 sdm845 power HAL 支持)。
- 67 恢复后先查: XiaomiParts 现有结构 + org.lineageos.platform.hardware 可用性。

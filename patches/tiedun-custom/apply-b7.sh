#!/bin/bash
# 铁盾OS B7 施工脚本(按文件幂等): 装卸策略(安装全放行/降级强装/签名三选项/卸载凭据闸)
# 目标: frameworks/base/packages/PackageInstaller (24.0 真实路径)
# 用法: bash apply-b7.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
HERE="$(cd "$(dirname "$0")" && pwd)/b7"
P="$SRC/frameworks/base/packages/PackageInstaller"
[ -d "$P" ] || { echo "PackageInstaller 未找到: $P"; exit 1; }

echo "== 新类 TieDunCredentialGate =="
mkdir -p "$P/src/com/android/packageinstaller/tiedun"
cp "$HERE/TieDunCredentialGate.java" "$P/src/com/android/packageinstaller/tiedun/"

python3 - "$P" <<'PYEOF'
import sys
P = sys.argv[1]

# ── 1. UninstallAlertDialogFragment: 系统应用卸载凭据闸 + 结果回传 ──
p = P + "/src/com/android/packageinstaller/handheld/UninstallAlertDialogFragment.java"
s = open(p, encoding="utf-8").read()
if "TieDunCredentialGate" in s:
    print("UninstallAlertDialogFragment 已施工, 跳过")
else:
    anchor = "import com.android.packageinstaller.UninstallerActivity;"
    assert anchor in s, "UAF anchor1"
    s = s.replace(anchor, anchor + "\nimport com.android.packageinstaller.tiedun.TieDunCredentialGate;\nimport android.content.Intent;", 1)

    old_click = """    @Override
    public void onClick(DialogInterface dialog, int which) {
        if (which == Dialog.BUTTON_POSITIVE) {
            ((UninstallerActivity) getActivity()).startUninstallProgress(
                    mKeepData != null && mKeepData.isChecked(), mIsClonedApp);
        } else {
            ((UninstallerActivity) getActivity()).dispatchAborted();
        }
    }"""
    new_click = """    @Override
    public void onClick(DialogInterface dialog, int which) {
        if (which == Dialog.BUTTON_POSITIVE) {
            // 铁盾OS B7: 系统应用卸载需凭据验证(无密码强制设密); 普通应用二次确认直删
            final UninstallerActivity activity = (UninstallerActivity) getActivity();
            final android.content.pm.ApplicationInfo ai =
                    activity != null && activity.getDialogInfo() != null
                            ? activity.getDialogInfo().appInfo : null;
            if (TieDunCredentialGate.isSystemApp(ai)
                    && !TieDunCredentialGate.check(activity, this)) {
                return; // 等凭据/设密结果经 onActivityResult 回传后继续
            }
            activity.startUninstallProgress(
                    mKeepData != null && mKeepData.isChecked(), mIsClonedApp);
        } else {
            ((UninstallerActivity) getActivity()).dispatchAborted();
        }
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (TieDunCredentialGate.isPassed(requestCode, resultCode)) {
            final UninstallerActivity activity = (UninstallerActivity) getActivity();
            if (activity != null) {
                activity.startUninstallProgress(
                        mKeepData != null && mKeepData.isChecked(), mIsClonedApp);
            }
            return;
        }
        if (requestCode == TieDunCredentialGate.REQ_CREDENTIAL) {
            ((UninstallerActivity) getActivity()).dispatchAborted();
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }"""
    assert old_click in s, "UAF onClick anchor"
    s = s.replace(old_click, new_click, 1)
    open(p, "w").write(s)
    print("UninstallAlertDialogFragment patched")

# ── 2. PackageInstallerActivity: 安装默认全放行 + 降级/签名预检(无需新导入) ──
p = P + "/src/com/android/packageinstaller/PackageInstallerActivity.java"
s = open(p, encoding="utf-8").read()
if "tiedunPreInstallCheck" in s:
    print("PackageInstallerActivity 已施工, 跳过")
else:
    old_allow = """    private void checkIfAllowedAndInitiateInstall() {
        if (mAllowUnknownSources || getIntent().getBooleanExtra(EXTRA_IS_TRUSTED_SOURCE, false)) {
            if (mLocalLOGV) Log.i(TAG, "install allowed");
            initiateInstall();
        } else {
            handleUnknownSources();
        }
    }"""
    new_allow = """    private void checkIfAllowedAndInitiateInstall() {
        // 铁盾OS B7: 安装默认全放行(需求冻结第十一节12); 降级/签名异常先醒目弹窗
        if (mLocalLOGV) Log.i(TAG, "install allowed (tiedun policy)");
        if (!tiedunPreInstallCheck()) {
            return;
        }
        initiateInstall();
    }

    /** 铁盾OS B7 预检: true=继续安装; false=弹窗进行中 */
    private boolean tiedunPreInstallCheck() {
        try {
            android.content.pm.PackageInfo installed =
                    mPm.getPackageInfo(mPkgInfo.packageName, 0);
            boolean downgrade =
                    mPkgInfo.getLongVersionCode() < installed.getLongVersionCode();
            boolean sigMismatch = tiedunSignatureMismatch(installed);
            if (!downgrade && !sigMismatch) {
                return true;
            }
            final int msgId = sigMismatch
                    ? R.string.tiedun_install_sig_mismatch
                    : R.string.tiedun_install_downgrade;
            AlertDialog.Builder b = new AlertDialog.Builder(this)
                    .setTitle(R.string.tiedun_install_force_title)
                    .setMessage(msgId)
                    .setCancelable(true);
            if (sigMismatch) {
                // 签名异常: 【强制安装/取消/关闭】 — 强制=卸旧后全新安装
                b.setPositiveButton(R.string.tiedun_force_install, (d, w) -> {
                    Intent del = new Intent(Intent.ACTION_DELETE,
                            Uri.parse("package:" + mPkgInfo.packageName));
                    del.putExtra(Intent.EXTRA_RETURN_RESULT, true);
                    startActivityForResult(del, TIEDUN_REQ_UNINSTALL_THEN_INSTALL);
                });
                b.setNegativeButton(R.string.cancel, (d, w) -> {
                    finish();
                });
                b.setNeutralButton(R.string.tiedun_close, (d, w) -> finish());
            } else {
                // 降级: 醒目提示【强制安装/取消】
                b.setPositiveButton(R.string.tiedun_force_install, (d, w) -> {
                    mTiedunForceInstall = true;
                    startInstall();
                });
                b.setNegativeButton(R.string.cancel, (d, w) -> {
                    finish();
                });
            }
            b.show();
            return false;
        } catch (NameNotFoundException e) {
            return true; // 全新安装
        }
    }

    /** 铁盾OS B7: 与已装版本比对签名(file 源才可取新包签名) */
    private boolean tiedunSignatureMismatch(android.content.pm.PackageInfo installed) {
        try {
            if (!ContentResolver.SCHEME_FILE.equals(mPackageURI.getScheme())) {
                return false;
            }
            android.content.pm.PackageInfo newInfo = PackageUtil.getPackageInfo(this,
                    new File(mPackageURI.getPath()),
                    PackageManager.GET_SIGNING_CERTIFICATES);
            if (newInfo == null || newInfo.signingInfo == null
                    || installed.signingInfo == null) {
                return false;
            }
            android.content.pm.Signature[] a =
                    newInfo.signingInfo.getApkContentsSigners();
            android.content.pm.Signature[] b =
                    installed.signingInfo.getApkContentsSigners();
            if (a == null || b == null || a.length != b.length) {
                return true;
            }
            for (int i = 0; i < a.length; i++) {
                if (!a[i].equals(b[i])) {
                    return true;
                }
            }
            return false;
        } catch (Throwable t) {
            return false;
        }
    }

    private static final int TIEDUN_REQ_UNINSTALL_THEN_INSTALL = 49102;
    private boolean mTiedunForceInstall = false;
"""
    assert old_allow in s, "PIA allow anchor"
    s = s.replace(old_allow, new_allow, 1)

    old_si = """        if (mAppSnippet != null) {
            newIntent.putExtra(EXTRA_APP_SNIPPET, mAppSnippet);
        }"""
    new_si = """        if (mAppSnippet != null) {
            newIntent.putExtra(EXTRA_APP_SNIPPET, mAppSnippet);
        }
        if (mTiedunForceInstall) {
            newIntent.putExtra(EXTRA_TIEDUN_FORCE_INSTALL, true);
        }"""
    assert old_si in s, "PIA startInstall anchor"
    s = s.replace(old_si, new_si, 1)

    old_ari = """    public void onActivityResult(int request, int result, Intent data) {
        if (request == REQUEST_TRUST_EXTERNAL_SOURCE) {"""
    new_ari = """    public void onActivityResult(int request, int result, Intent data) {
        // 铁盾OS B7: 强装(签名异常)先卸旧后回来续装
        if (request == TIEDUN_REQ_UNINSTALL_THEN_INSTALL) {
            if (result == Activity.RESULT_OK) {
                mTiedunForceInstall = true;
                startInstall();
            } else {
                finish();
            }
            return;
        }
        if (request == REQUEST_TRUST_EXTERNAL_SOURCE) {"""
    assert old_ari in s, "PIA existing onActivityResult anchor"
    s = s.replace(old_ari, new_ari, 1)

    old_k = "    private static final int DLG_BASE = 0;"
    new_k = """    public static final String EXTRA_TIEDUN_FORCE_INSTALL =
            PackageInstallerActivity.class.getName() + "TIEDUN_FORCE_INSTALL";

    private static final int DLG_BASE = 0;"""
    assert old_k in s, "PIA const anchor"
    s = s.replace(old_k, new_k, 1)
    open(p, "w").write(s)
    print("PackageInstallerActivity patched")

# ── 3. InstallStaging: 强装 -> setAllowDowngrade ──
p = P + "/src/com/android/packageinstaller/InstallStaging.java"
s = open(p, encoding="utf-8").read()
if "EXTRA_TIEDUN_FORCE_INSTALL" in s:
    print("InstallStaging 已施工, 跳过")
else:
    old_st = """        params.setOriginatingUid(intent.getIntExtra(Intent.EXTRA_ORIGINATING_UID,"""
    new_st = """        // 铁盾OS B7: 强制安装(降级)授权
        if (intent.getBooleanExtra(PackageInstallerActivity.EXTRA_TIEDUN_FORCE_INSTALL, false)) {
            params.setAllowDowngrade(true);
        }
        params.setOriginatingUid(intent.getIntExtra(Intent.EXTRA_ORIGINATING_UID,"""
    assert old_st in s, "IS anchor"
    s = s.replace(old_st, new_st, 1)
    open(p, "w").write(s)
    print("InstallStaging patched")

# ── 4. 字符串(幂等) ──
import os
def merge_strings(path, items):
    txt = open(path, encoding="utf-8").read()
    if "tiedun_force_install" in txt:
        print("strings 已合并 ->", path)
        return
    add = "\n    <!-- TieDun OS B7 -->\n" + "\n".join(items) + "\n"
    txt = txt.replace("</resources>", add + "</resources>", 1)
    open(path, "w").write(txt)

en_items = [
    '    <string name="tiedun_uninstall_cred_title">Uninstall system app</string>',
    '    <string name="tiedun_uninstall_cred_subtitle">Verify your screen lock to continue</string>',
    '    <string name="tiedun_install_force_title">Install with caution</string>',
    '    <string name="tiedun_install_downgrade">This APK is an older version than the installed one. Force install anyway?</string>',
    '    <string name="tiedun_install_sig_mismatch">Signature mismatch! The APK is signed differently from the installed app. Force install will remove the old app and its data first.</string>',
    '    <string name="tiedun_force_install">Force install</string>',
    '    <string name="tiedun_close">Close</string>',
]
zh_items = [
    '    <string name="tiedun_uninstall_cred_title">卸载系统应用</string>',
    '    <string name="tiedun_uninstall_cred_subtitle">请验证锁屏凭据后继续</string>',
    '    <string name="tiedun_install_force_title">安装警示</string>',
    '    <string name="tiedun_install_downgrade">该 APK 版本低于已装版本（降级）。是否强制安装？</string>',
    '    <string name="tiedun_install_sig_mismatch">签名异常！该 APK 与已装应用签名不一致。强制安装将先卸载旧应用（含其数据）。</string>',
    '    <string name="tiedun_force_install">强制安装</string>',
    '    <string name="tiedun_close">关闭</string>',
]
merge_strings(P + "/res/values/strings.xml", en_items)
zh = P + "/res/values-zh-rCN/strings.xml"
if not os.path.exists(zh):
    os.makedirs(P + "/res/values-zh-rCN", exist_ok=True)
    open(zh, "w").write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n')
merge_strings(zh, zh_items)
print("strings done")
PYEOF

echo "== B7 完成 =="

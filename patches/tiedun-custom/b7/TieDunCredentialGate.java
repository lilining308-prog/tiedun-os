/*
 * 铁盾OS B7: 卸载凭据闸(系统应用卸载需锁屏凭据; 无密码强制设密)
 * 需求冻结第十一节11: 系统应用卸载必须密码验证+无密码强制设密
 * SPDX-License-Identifier: Apache-2.0
 */
package com.android.packageinstaller.tiedun;

import android.app.Activity;
import android.app.Fragment;
import android.app.admin.DevicePolicyManager;
import android.content.Intent;
import android.os.Build;
import android.os.UserHandle;
import android.app.KeyguardManager;

import com.android.packageinstaller.R;

/** 系统应用卸载前的凭据验证/强制设密流程。 */
public final class TieDunCredentialGate {

    public static final int REQ_CREDENTIAL = 49101;

    private TieDunCredentialGate() {
    }

    /**
     * 发起凭据验证(已设密)或强制设密(未设密)。
     * 返回 true=直接放行; false=流程已发起, 结果经 onActivityResult 回传。
     */
    public static boolean check(Activity host, Fragment requester) {
        final KeyguardManager km = host.getSystemService(KeyguardManager.class);
        if (km != null && km.isDeviceSecure()) {
            final Intent confirm = km.createConfirmDeviceCredentialIntent(
                    host.getString(R.string.tiedun_uninstall_cred_title),
                    host.getString(R.string.tiedun_uninstall_cred_subtitle));
            if (confirm != null) {
                requester.startActivityForResult(confirm, REQ_CREDENTIAL);
                return false;
            }
            return true;
        }
        // 无密码: 强制设密(ChooseLockGeneric), 完成后回来继续
        final Intent setup = new Intent(DevicePolicyManager.ACTION_SET_NEW_PASSWORD);
        requester.startActivityForResult(setup, REQ_CREDENTIAL);
        return false;
    }

    /** onActivityResult 结果判定 */
    public static boolean isPassed(int requestCode, int resultCode) {
        return requestCode == REQ_CREDENTIAL && resultCode == Activity.RESULT_OK;
    }

    /** 是否系统应用(需凭据) */
    public static boolean isSystemApp(android.content.pm.ApplicationInfo ai) {
        return ai != null && (ai.flags & android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0;
    }

    /** 内部: 防 lint 未使用告警 */
    static String abi() {
        return Build.DEVICE + "/" + UserHandle.myUserId();
    }
}

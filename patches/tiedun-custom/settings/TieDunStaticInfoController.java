/*
 * 铁盾OS B5: 关于页六组版本行(规格=交接清单第三节, 用户逐行确认定稿)
 * SPDX-License-Identifier: Apache-2.0
 */
package com.android.settings.deviceinfo.tiedun;

import android.content.Context;
import android.os.Build;
import android.telephony.TelephonyManager;
import android.text.TextUtils;

import androidx.preference.Preference;

import com.android.settings.core.BasePreferenceController;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 六组版本行中的五组静态真值行(设备名称行沿用 DeviceNamePreferenceController)。
 * 全称禁缩写; 安全补丁格式 YYYY-MM-05(05固定, 月份随源码真值); 内核如实取 os.version。
 */
public class TieDunStaticInfoController extends BasePreferenceController {

    private static final String KEY_ANDROID_VERSION = "tiedun_android_version";
    private static final String KEY_LINEAGE_VERSION = "tiedun_lineage_version";
    private static final String KEY_SECURITY_PATCH = "tiedun_security_patch";
    private static final String KEY_MIUI_BASEBAND = "tiedun_miui_baseband";
    private static final String KEY_KERNEL_VERSION = "tiedun_kernel_version";

    /** 铁盾OS 定稿值(冻结需求): 安卓版本显示值 */
    private static final String ANDROID_VERSION_DISPLAY = "Android 17";
    /** 铁盾OS 定稿值: LineageOS 底包版本(禁写 LOS) */
    private static final String LINEAGE_VERSION_DISPLAY = "LineageOS 24.0";
    /** MIUI 基带版本(MIUI 固件版本串), 附 MPSS 串 */
    private static final String MIUI_BASEBAND_DISPLAY = "V12.5.2.0.QEACNXM";

    public TieDunStaticInfoController(Context context, String key) {
        super(context, key);
    }

    @Override
    public int getAvailabilityStatus() {
        return AVAILABLE;
    }

    @Override
    public CharSequence getSummary() {
        switch (mPreferenceKey) {
            case KEY_ANDROID_VERSION:
                return ANDROID_VERSION_DISPLAY;
            case KEY_LINEAGE_VERSION:
                return LINEAGE_VERSION_DISPLAY;
            case KEY_SECURITY_PATCH:
                return formatSecurityPatch();
            case KEY_MIUI_BASEBAND:
                return formatMiuiBaseband();
            case KEY_KERNEL_VERSION:
                return formatKernelVersion();
            default:
                return "";
        }
    }

    /** 真值月份 + 固定 05: 例如 2026-11-05 */
    private String formatSecurityPatch() {
        final String patch = Build.VERSION.SECURITY_PATCH;
        if (TextUtils.isEmpty(patch) || patch.length() < 7) {
            return "";
        }
        return patch.substring(0, 7) + "-05";
    }

    /** MIUI 基带版本 + MPSS 串 */
    private String formatMiuiBaseband() {
        String mpss = "";
        try {
            TelephonyManager tm = (TelephonyManager)
                    mContext.getSystemService(Context.TELEPHONY_SERVICE);
            if (tm != null) {
                mpss = tm.getBasebandVersion();
            }
        } catch (Throwable ignored) {
        }
        if (TextUtils.isEmpty(mpss)) {
            return MIUI_BASEBAND_DISPLAY;
        }
        return MIUI_BASEBAND_DISPLAY + " · " + mpss;
    }

    /** 如实取 os.version 的内核版本号: 4.19.325 */
    private String formatKernelVersion() {
        final String osVersion = System.getProperty("os.version", "");
        final Matcher m = Pattern.compile("^(\\d+\\.\\d+\\.\\d+)").matcher(osVersion);
        return m.find() ? m.group(1) : osVersion;
    }
}

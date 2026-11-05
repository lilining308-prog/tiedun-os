/*
 * 铁盾OS「铁盾系统更新」— Recovery 安装 / 本地包安装
 * Copyright (C) 2026 lilining308
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
package com.lilining.tiedun.updater;

import android.content.Context;
import android.os.PowerManager;
import android.os.RecoverySystem;

import java.io.File;

/** 写入 Recovery 指令并自动重启刷入；或走本地包安装。 */
public final class InstallHelper {

    /** 校验通过的包 → uncrypt + BCB → 重启进 recovery 自动刷入。 */
    public static void installPackage(Context context, File pkg) throws Exception {
        RecoverySystem.processPackage(context, pkg, null);
        PowerManager pm = context.getSystemService(PowerManager.class);
        pm.reboot("recovery");
    }
}

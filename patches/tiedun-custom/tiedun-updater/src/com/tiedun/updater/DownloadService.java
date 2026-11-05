/*
 * 铁盾OS C6: 铁盾系统更新 — 前台下载服务(进度通知 + 广播), 可选下载后直接刷入
 * SPDX-License-Identifier: GPL-3.0
 */
package com.tiedun.updater;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import java.io.File;

public class DownloadService extends Service {

    private static final String TAG = "TiedunUpdater";
    private static final String CHANNEL = "tiedun_download";
    private static final int NOTIF_ID = 10;

    public static final String EXTRA_URL = "url";
    public static final String EXTRA_FILENAME = "filename";
    public static final String EXTRA_SHA256 = "sha256";
    public static final String EXTRA_TOTAL = "total";
    public static final String EXTRA_INSTALL = "install";

    private volatile boolean mCancelled;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        final String url = intent.getStringExtra(EXTRA_URL);
        final String filename = intent.getStringExtra(EXTRA_FILENAME);
        final String sha256 = intent.getStringExtra(EXTRA_SHA256);
        final long total = intent.getLongExtra(EXTRA_TOTAL, 0);
        final boolean install = intent.getBooleanExtra(EXTRA_INSTALL, false);

        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(CHANNEL,
                    getString(R.string.notif_channel_download),
                    NotificationManager.IMPORTANCE_LOW);
            nm.createNotificationChannel(ch);
        }
        Notification notif = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(getString(R.string.app_name))
                .setContentText(getString(R.string.status_downloading))
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(NOTIF_ID, notif);
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    File dir = new File(getFilesDir(), "ota");
                    dir.mkdirs();
                    File dest = new File(dir, filename);
                    OtaClient.download(url, dest, total, new OtaClient.Progress() {
                        @Override
                        public void onProgress(long bytes, long t) {
                            Intent i = new Intent(OtaClient.ACTION_PROGRESS).setPackage(getPackageName());
                            i.putExtra(OtaClient.EXTRA_BYTES, bytes);
                            i.putExtra(OtaClient.EXTRA_TOTAL, t);
                            sendBroadcast(i);
                            int pct = (t > 0) ? (int) (bytes * 100 / t) : 0;
                            Notification n = new Notification.Builder(DownloadService.this, CHANNEL)
                                    .setSmallIcon(R.drawable.ic_launcher)
                                    .setContentTitle(getString(R.string.app_name))
                                    .setContentText(getString(R.string.status_downloading) + " " + pct + "%")
                                    .setProgress(100, pct, t <= 0)
                                    .setOngoing(true)
                                    .build();
                            nm.notify(NOTIF_ID, n);
                        }
                    });
                    sendState("verifying");
                    if (sha256 != null && sha256.length() > 0) {
                        String actual = OtaClient.sha256(dest);
                        if (!sha256.equalsIgnoreCase(actual)) {
                            dest.delete();
                            sendState("sha_fail");
                            finish(nm);
                            return;
                        }
                    }
                    // 签名锁死: 必须是铁盾OS 专有 OTA 密钥签名的包(完整性+真伪)
                    if (!Installer.verifySignedByOtaCert(dest)) {
                        dest.delete();
                        sendState("sig_fail");
                        finish(nm);
                        return;
                    }
                    sendState("done");
                    finish(nm);
                    if (install) {
                        boolean verified = Installer.verifyPackage(dest, null);
                        if (!verified) {
                            Log.w(TAG, "verifyPackage failed, try install anyway");
                        }
                        sendState("installing");
                        Installer.install(DownloadService.this, dest);
                    }
                } catch (Throwable t) {
                    Log.e(TAG, "download/install failed", t);
                    sendState("failed");
                    finish(nm);
                }
            }
        }, "tiedun-download").start();
        return START_NOT_STICKY;
    }

    private void sendState(String state) {
        Intent i = new Intent(OtaClient.ACTION_STATUS).setPackage(getPackageName());
        i.putExtra(OtaClient.EXTRA_STATE, state);
        sendBroadcast(i);
    }

    private void finish(NotificationManager nm) {
        stopForeground(true);
        nm.cancel(NOTIF_ID);
        stopSelf();
    }
}

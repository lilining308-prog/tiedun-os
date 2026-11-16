/*
 * 铁盾OS C6: 铁盾系统更新 — 开机/定时检查更新, 发现新版本发通知
 * SPDX-License-Identifier: GPL-3.0
 */
package com.tiedun.updater;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.os.SystemProperties;
import android.util.Log;

import java.util.List;

public class CheckReceiver extends BroadcastReceiver {

    private static final String TAG = "TiedunUpdater";
    private static final String CHANNEL = "tiedun_check";
    private static final int NOTIF_ID = 11;
    private static final long INTERVAL_MS = 6 * 60 * 60 * 1000L;

    public static String serverUrl(Context context) {
        SharedPreferences sp = context.getSharedPreferences("tiedun", Context.MODE_PRIVATE);
        String url = sp.getString("server_url", "");
        if (url.length() == 0) {
            url = SystemProperties.get("ro.tiedun.updater.uri", "");
        }
        String device = SystemProperties.get("ro.lineage.device",
                SystemProperties.get("ro.product.device", "dipper"));
        return url.replace("{device}", device);
    }

    /**
     * 内置双通道(铁盾更新器): 主选 IPv6 直连, 穿透为备选。
     * 检测到 IPv6 可达时走直连, 否则/失败自动降级穿透。
     */
    public static final String SERVER_IPV6 =
            "http://[2409:8a55:40b0:c421::192]:8848/api/v2/devices/{device}/builds";
    public static final String SERVER_TUNNEL =
            "https://home-195.tail10a661.ts.net/api/v2/devices/{device}/builds";

    /** 候选通道(按优先级): 自定义 > IPv6 直连 > 穿透 */
    public static java.util.List<String> channelCandidates(Context context) {
        java.util.ArrayList<String> out = new java.util.ArrayList<>();
        String custom = serverUrl(context);
        String device = SystemProperties.get("ro.lineage.device",
                SystemProperties.get("ro.product.device", "dipper"));
        String ipv6 = SERVER_IPV6.replace("{device}", device);
        String tunnel = SERVER_TUNNEL.replace("{device}", device);
        if (custom.length() > 0 && !out.contains(custom)) {
            out.add(custom);
        }
        if (!out.contains(ipv6)) {
            out.add(ipv6);
        }
        if (!out.contains(tunnel)) {
            out.add(tunnel);
        }
        return out;
    }

    /** IPv6 直连是否可用(短超时探测, 需在工作线程调用) */
    public static boolean ipv6Ready() {
        try {
            java.net.Socket s = new java.net.Socket();
            try {
                s.connect(new java.net.InetSocketAddress(
                        java.net.InetAddress.getByName("2409:8a55:40b0:c421::192"), 8848), 2500);
                return true;
            } finally {
                s.close();
            }
        } catch (Throwable t) {
            return false;
        }
    }

    /** 检查/上报 URL: 附加机型·版本·设备ID(服务端据此统计装机名单) */
    public static String reportUrl(Context context) {
        return appendReport(context, serverUrl(context));
    }

    /** 给更新检查 URL 附加上报参数(已带 did= 时不重复添加) */
    public static String appendReport(Context context, String url) {
        if (url == null || url.length() == 0 || url.indexOf("did=") >= 0) {
            return url;
        }
        String model = SystemProperties.get("ro.product.model", "unknown");
        String device = SystemProperties.get("ro.lineage.device",
                SystemProperties.get("ro.product.device", "dipper"));
        String ver = SystemProperties.get("ro.tiedun.version", "");
        String sep = url.indexOf('?') >= 0 ? "&" : "?";
        return url + sep + "model=" + enc(model) + "&codename=" + enc(device)
                + "&version=" + enc(ver) + "&did=" + enc(deviceId(context));
    }

    /** 设备指纹: ANDROID_ID 的 SHA-256 截断(免权限、开机可用、不上报原值) */
    public static String deviceId(Context context) {
        String aid = android.provider.Settings.Secure.getString(
                context.getContentResolver(), android.provider.Settings.Secure.ANDROID_ID);
        if (aid == null || aid.length() == 0) {
            aid = "unknown";
        }
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-256");
            byte[] d = md.digest(("tiedun-" + aid).getBytes("UTF-8"));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 8; i++) {
                sb.append(String.format(java.util.Locale.US, "%02x", d[i]));
            }
            return sb.toString();
        } catch (Exception e) {
            return Integer.toHexString(aid.hashCode());
        }
    }

    private static String enc(String s) {
        try {
            return java.net.URLEncoder.encode(s == null ? "" : s, "UTF-8");
        } catch (Exception e) {
            return "";
        }
    }

    public static void schedule(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        Intent i = new Intent(context, CheckReceiver.class);
        i.setAction("com.tiedun.updater.ACTION_CHECK");
        PendingIntent pi = PendingIntent.getBroadcast(context, 0, i, PendingIntent.FLAG_IMMUTABLE);
        am.setInexactRepeating(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 10 * 60 * 1000L, INTERVAL_MS, pi);
    }

    @Override
    public void onReceive(final Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            schedule(context);
        }
        final String url = reportUrl(context);
        if (url.length() == 0) {
            return;
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    List<OtaClient.Entry> entries = OtaClient.fetch(url);
                    long buildDate = SystemProperties.getLong("ro.build.date.utc", 0);
                    OtaClient.Entry best = null;
                    for (OtaClient.Entry e : entries) {
                        if (e.datetime > buildDate && (best == null || e.datetime > best.datetime)) {
                            best = e;
                        }
                    }
                    if (best != null) {
                        notifyUpdate(context, best);
                    }
                } catch (Throwable t) {
                    Log.w(TAG, "check failed: " + t.getMessage());
                }
            }
        }, "tiedun-check").start();
    }

    private void notifyUpdate(Context context, OtaClient.Entry e) {
        NotificationManager nm = (NotificationManager)
                context.getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel ch = new NotificationChannel(CHANNEL,
                context.getString(R.string.notif_channel_check),
                NotificationManager.IMPORTANCE_DEFAULT);
        nm.createNotificationChannel(ch);
        Intent open = new Intent(context, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pi = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(context.getString(R.string.msg_update_found))
                .setContentText(e.version + " · " + e.filename)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build();
        nm.notify(NOTIF_ID, n);
    }
}

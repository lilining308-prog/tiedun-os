/*
 * 铁盾OS C6: 铁盾系统更新 — OTA 数据源(JSON 解析) + 下载(断点续传) + SHA-256
 * 服务端 JSON 兼容 LineageOS Updater v2 格式(见 docs/OTA.md):
 *   [ { "datetime":…, "files":[{ "filename","sha256","size","url", … }], "type","version" } ]
 * SPDX-License-Identifier: GPL-3.0
 */
package com.tiedun.updater;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

public final class OtaClient {

    public static final String ACTION_PROGRESS = "com.tiedun.updater.DOWNLOAD_PROGRESS";
    public static final String ACTION_STATUS = "com.tiedun.updater.DOWNLOAD_STATUS";
    public static final String EXTRA_BYTES = "bytes";
    public static final String EXTRA_TOTAL = "total";
    public static final String EXTRA_STATE = "state";

    public interface Progress {
        void onProgress(long bytes, long total);
    }

    public static class Entry {
        public String version = "";
        public String type = "";
        public long datetime;
        public String filename = "";
        public String url = "";
        public String sha256 = "";
        public long size;
    }

    private OtaClient() {
    }

    private static HttpURLConnection open(String urlStr) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("User-Agent", "TieDunUpdater/1.0");
        return conn;
    }

    /** 拉取更新列表(数组或 {response:[…]}/{builds:[…]} 均可) */
    public static List<Entry> fetch(String serverUrl) throws IOException {
        HttpURLConnection conn = open(serverUrl);
        String body;
        try {
            int code = conn.getResponseCode();
            if (code != 200) {
                throw new IOException("HTTP " + code);
            }
            BufferedReader r = new BufferedReader(
                    new InputStreamReader(conn.getInputStream(), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line);
            }
            r.close();
            body = sb.toString();
        } finally {
            conn.disconnect();
        }
        List<Entry> out = new ArrayList<>();
        try {
            JSONArray arr = null;
            String trimmed = body.trim();
            if (trimmed.startsWith("[")) {
                arr = new JSONArray(trimmed);
            } else {
                JSONObject root = new JSONObject(trimmed);
                if (root.has("response")) {
                    arr = root.getJSONArray("response");
                } else if (root.has("builds")) {
                    arr = root.getJSONArray("builds");
                }
            }
            if (arr == null) {
                throw new IOException("bad response shape");
            }
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                JSONArray files = o.optJSONArray("files");
                if (files == null || files.length() == 0) {
                    continue;
                }
                JSONObject f = files.getJSONObject(0);
                Entry e = new Entry();
                e.version = o.optString("version", "");
                e.type = o.optString("type", "");
                e.datetime = o.optLong("datetime", 0);
                e.filename = f.optString("filename", "");
                e.url = f.optString("url", "");
                e.sha256 = f.optString("sha256", "");
                e.size = f.optLong("size", 0);
                if (e.url.length() > 0 && e.filename.length() > 0) {
                    out.add(e);
                }
            }
        } catch (IOException e) {
            throw e;
        } catch (Throwable t) {
            throw new IOException("bad response: " + t.getMessage());
        }
        return out;
    }

    /** 断点续传下载到 dest */
    public static void download(String urlStr, File dest, long total, Progress progress)
            throws IOException {
        long existing = dest.exists() ? dest.length() : 0;
        HttpURLConnection conn = open(urlStr);
        // 服务端串行下载(一台更完另一台再更), 排队可达30分钟: 读超时放宽到35分钟
        conn.setReadTimeout(35 * 60 * 1000);
        boolean append = false;
        try {
            if (existing > 0) {
                conn.setRequestProperty("Range", "bytes=" + existing + "-");
            }
            int code = conn.getResponseCode();
            if (code == 206 && existing > 0) {
                append = true;
            } else if (code == 200) {
                existing = 0;
            } else {
                throw new IOException("HTTP " + code);
            }
            InputStream in = conn.getInputStream();
            FileOutputStream out = new FileOutputStream(dest, append);
            byte[] buf = new byte[262144];
            long done = existing;
            int n;
            try {
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                    done += n;
                    if (progress != null) {
                        progress.onProgress(done, total);
                    }
                }
            } finally {
                try {
                    out.close();
                } catch (IOException ignored) {
                }
                in.close();
            }
        } finally {
            conn.disconnect();
        }
    }

    /** SHA-256 十六进制 */
    public static String sha256(File f) throws IOException {
        MessageDigest md;
        try {
            md = MessageDigest.getInstance("SHA-256");
        } catch (Exception e) {
            throw new IOException(e.getMessage());
        }
        InputStream in = new java.io.FileInputStream(f);
        byte[] buf = new byte[262144];
        int n;
        try {
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        } finally {
            in.close();
        }
        StringBuilder sb = new StringBuilder();
        for (byte b : md.digest()) {
            sb.append(String.format(LocaleHolder.LOCALE, "%02x", b));
        }
        return sb.toString();
    }

    private static final class LocaleHolder {
        static final java.util.Locale LOCALE = java.util.Locale.US;
    }
}

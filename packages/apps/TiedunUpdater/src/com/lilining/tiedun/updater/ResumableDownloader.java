/*
 * 铁盾OS「铁盾系统更新」— 断点续传下载 + SHA-256 校验
 * Copyright (C) 2026 lilining308
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
package com.lilining.tiedun.updater;

import java.io.File;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/** HTTP Range 断点续传下载器；完成后做 SHA-256 校验。 */
public final class ResumableDownloader {

    public interface Progress {
        void onProgress(long downloaded, long total);
    }

    /** 下载（可续传）。返回 true 表示完整下载且 SHA-256 通过。 */
    public static boolean download(String url, File dest, String expectSha256,
                                   Progress progress, Object pauseLock) throws Exception {
        long existing = dest.exists() ? dest.length() : 0;
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        if (existing > 0) {
            conn.setRequestProperty("Range", "bytes=" + existing + "-");
        }
        conn.setConnectTimeout(15_000);
        conn.setReadTimeout(30_000);
        int code = conn.getResponseCode();
        boolean append = (code == 206);
        if (!append && code != 200) {
            conn.disconnect();
            return false;
        }
        long total = conn.getContentLengthLong() + (append ? existing : 0);
        if (!append) existing = 0;

        try (InputStream in = conn.getInputStream();
             RandomAccessFile raf = new RandomAccessFile(dest, "rw")) {
            raf.seek(existing);
            byte[] buf = new byte[256 * 1024];
            long done = existing;
            int n;
            while ((n = in.read(buf)) > 0) {
                synchronized (pauseLock) {
                    while (pauseLock instanceof Boolean && (Boolean) pauseLock) {
                        pauseLock.wait();
                    }
                }
                raf.write(buf, 0, n);
                done += n;
                if (progress != null) progress.onProgress(done, total);
            }
        } finally {
            conn.disconnect();
        }

        String actual = sha256Hex(dest);
        if (!actual.equals(expectSha256)) {
            //noinspection ResultOfMethodCallIgnored
            dest.delete();
            return false;
        }
        return true;
    }

    public static String sha256Hex(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new java.io.FileInputStream(f)) {
            byte[] buf = new byte[256 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
        }
        StringBuilder sb = new StringBuilder();
        for (byte b : md.digest()) sb.append(String.format("%02x", b));
        return sb.toString();
    }
}

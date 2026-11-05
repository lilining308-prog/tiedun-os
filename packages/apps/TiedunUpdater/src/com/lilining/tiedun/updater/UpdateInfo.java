/*
 * 铁盾OS「铁盾系统更新」— 更新源信息获取
 * Copyright (C) 2026 lilining308
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
package com.lilining.tiedun.updater;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** 从 OTA 服务端拉取最新版本元数据（协议见 docs/OTA.md）。 */
public final class UpdateInfo {
    public final String version;
    public final String url;
    public final String sha256;
    public final long size;
    public final String changelog;

    private UpdateInfo(String version, String url, String sha256, long size, String changelog) {
        this.version = version;
        this.url = url;
        this.sha256 = sha256;
        this.size = size;
        this.changelog = changelog;
    }

    public static UpdateInfo fetch(String endpoint) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(endpoint).openConnection();
        conn.setConnectTimeout(10_000);
        conn.setReadTimeout(10_000);
        try (InputStream in = conn.getInputStream();
             BufferedReader br = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = br.readLine()) != null) sb.append(line);
            JSONObject o = new JSONObject(sb.toString());
            return new UpdateInfo(
                    o.getString("version"),
                    o.getString("url"),
                    o.getString("sha256").toLowerCase(),
                    o.getLong("size"),
                    o.optString("changelog", ""));
        } finally {
            conn.disconnect();
        }
    }
}

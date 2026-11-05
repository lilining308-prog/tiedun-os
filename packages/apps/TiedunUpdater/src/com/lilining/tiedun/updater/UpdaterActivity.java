/*
 * 铁盾OS「铁盾系统更新」— 主界面
 * Copyright (C) 2026 lilining308
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
package com.lilining.tiedun.updater;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemProperties;
import android.view.View;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class UpdaterActivity extends Activity {

    private static final int REQ_PICK_LOCAL = 1;

    private TextView mLatest, mChangelog;
    private ProgressBar mProgress;
    private Button mBtnCheck, mBtnDownload, mBtnInstall, mBtnLocal;

    private final ExecutorService mIo = Executors.newSingleThreadExecutor();
    private final Object mPauseLock = new Object();
    private UpdateInfo mInfo;
    private File mPkg;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_updater);

        TextView current = findViewById(R.id.current_version);
        mLatest = findViewById(R.id.latest_version);
        mChangelog = findViewById(R.id.changelog);
        mProgress = findViewById(R.id.progress);
        mBtnCheck = findViewById(R.id.btn_check);
        mBtnDownload = findViewById(R.id.btn_download);
        mBtnInstall = findViewById(R.id.btn_install);
        mBtnLocal = findViewById(R.id.btn_local);

        String ver = SystemProperties.get("ro.tiedun.version",
                SystemProperties.get("ro.lineage.version", "unknown"));
        current.setText(getString(R.string.current_version) + ": TieDun OS " + ver);

        mBtnCheck.setOnClickListener(v -> checkUpdate());
        mBtnDownload.setOnClickListener(v -> download());
        mBtnInstall.setOnClickListener(v -> install());
        mBtnLocal.setOnClickListener(v -> pickLocal());
    }

    private String endpoint() {
        // OTA 服务端地址: 系统属性优先, 默认本机 OTA 服务(docs/OTA.md)
        return SystemProperties.get("ro.tiedun.ota_url",
                "http://192.168.31.67:8000/update.json");
    }

    private void checkUpdate() {
        mBtnCheck.setEnabled(false);
        mLatest.setText(R.string.checking);
        mIo.execute(() -> {
            try {
                UpdateInfo info = UpdateInfo.fetch(endpoint());
                runOnUiThread(() -> {
                    mInfo = info;
                    mLatest.setText(getString(R.string.update_available, info.version));
                    mChangelog.setText(info.changelog);
                    mBtnDownload.setEnabled(true);
                    mBtnCheck.setEnabled(true);
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    mLatest.setText(R.string.server_unreachable);
                    mBtnCheck.setEnabled(true);
                });
            }
        });
    }

    private void download() {
        if (mInfo == null) return;
        mPkg = new File(getCacheDir(), "tiedun-" + mInfo.version + ".zip");
        mProgress.setVisibility(View.VISIBLE);
        mBtnDownload.setEnabled(false);
        mIo.execute(() -> {
            try {
                boolean ok = ResumableDownloader.download(
                        mInfo.url, mPkg, mInfo.sha256,
                        (done, total) -> runOnUiThread(() -> {
                            int pct = total > 0 ? (int) (done * 100 / total) : 0;
                            mProgress.setProgress(pct);
                            mLatest.setText(getString(R.string.downloading, pct));
                        }),
                        mPauseLock);
                runOnUiThread(() -> {
                    if (ok) {
                        mLatest.setText(R.string.install);
                        mBtnInstall.setEnabled(true);
                    } else {
                        mLatest.setText(R.string.verify_failed);
                        mBtnDownload.setEnabled(true);
                    }
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    mLatest.setText(getString(R.string.check_failed, e.getMessage()));
                    mBtnDownload.setEnabled(true);
                });
            }
        });
    }

    private void install() {
        if (mPkg == null) return;
        mLatest.setText(R.string.installing);
        mIo.execute(() -> {
            try {
                InstallHelper.installPackage(this, mPkg);
            } catch (Exception e) {
                runOnUiThread(() ->
                        mLatest.setText(getString(R.string.install_failed, e.getMessage())));
            }
        });
    }

    private void pickLocal() {
        Intent i = new Intent(Intent.ACTION_GET_CONTENT);
        i.setType("application/zip");
        i.addCategory(Intent.CATEGORY_OPENABLE);
        startActivityForResult(i, REQ_PICK_LOCAL);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_PICK_LOCAL || resultCode != RESULT_OK || data == null) return;
        Uri uri = data.getData();
        mIo.execute(() -> {
            try {
                File local = new File(getCacheDir(), "local-install.zip");
                try (java.io.InputStream in = getContentResolver().openInputStream(uri);
                     java.io.OutputStream out = new java.io.FileOutputStream(local)) {
                    byte[] buf = new byte[256 * 1024];
                    int n;
                    while ((in != null) && (n = in.read(buf)) > 0) out.write(buf, 0, n);
                }
                InstallHelper.installPackage(this, local);
            } catch (Exception e) {
                runOnUiThread(() ->
                        Toast.makeText(this, e.getMessage(), Toast.LENGTH_LONG).show());
            }
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        mIo.shutdownNow();
    }
}

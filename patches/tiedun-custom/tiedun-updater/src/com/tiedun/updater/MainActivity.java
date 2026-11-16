/*
 * 铁盾OS C6: 铁盾系统更新 — 主界面
 * 检查更新 / 下载(断点续传) / SHA-256 校验 / recovery 刷入 / 本地包安装
 * SPDX-License-Identifier: GPL-3.0
 */
package com.tiedun.updater;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemProperties;
import android.text.TextUtils;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MainActivity extends Activity {

    private TextView mInfo;
    private TextView mStatus;
    private TextView mNotice;
    private ProgressBar mProgress;
    private LinearLayout mResults;
    private EditText mUrlEdit;

    private final BroadcastReceiver mReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent == null || intent.getAction() == null) {
                return;
            }
            if (OtaClient.ACTION_PROGRESS.equals(intent.getAction())) {
                long bytes = intent.getLongExtra(OtaClient.EXTRA_BYTES, 0);
                long total = intent.getLongExtra(OtaClient.EXTRA_TOTAL, 0);
                mProgress.setIndeterminate(total <= 0);
                if (total > 0) {
                    mProgress.setMax(100);
                    mProgress.setProgress((int) (bytes * 100 / total));
                    mStatus.setText(getString(R.string.status_downloading) + " "
                            + (bytes / 1048576) + "/" + (total / 1048576) + " MB");
                }
            } else if (OtaClient.ACTION_STATUS.equals(intent.getAction())) {
                String state = intent.getStringExtra(OtaClient.EXTRA_STATE);
                if ("verifying".equals(state)) {
                    mStatus.setText(R.string.status_verifying);
                } else if ("done".equals(state)) {
                    mStatus.setText(R.string.status_idle);
                    mProgress.setProgress(0);
                    mProgress.setIndeterminate(false);
                    mNotice.setVisibility(View.GONE);
                } else if ("installing".equals(state)) {
                    mStatus.setText(R.string.status_installing);
                } else if ("sha_fail".equals(state)) {
                    mStatus.setText(R.string.msg_sha_fail);
                    toast(R.string.msg_sha_fail);
                } else if ("sig_fail".equals(state)) {
                    mStatus.setText(R.string.msg_sig_fail);
                    toast(R.string.msg_sig_fail);
                } else if ("failed".equals(state)) {
                    mStatus.setText(R.string.msg_install_failed);
                    toast(R.string.msg_install_failed);
                }
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        CheckReceiver.schedule(this);
        if (checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1);
        }
        buildUi();
        IntentFilter f = new IntentFilter();
        f.addAction(OtaClient.ACTION_PROGRESS);
        f.addAction(OtaClient.ACTION_STATUS);
        registerReceiver(mReceiver, f, Context.RECEIVER_NOT_EXPORTED);
        checkUpdates();
    }

    @Override
    protected void onDestroy() {
        try {
            unregisterReceiver(mReceiver);
        } catch (Throwable ignored) {
        }
        super.onDestroy();
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void toast(int resId) {
        Toast.makeText(this, resId, Toast.LENGTH_LONG).show();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(20), dp(20), dp(20));
        scroll.addView(root);

        TextView title = new TextView(this);
        title.setText(getString(R.string.app_name) + "  ·  TieDun OS "
                + SystemProperties.get("ro.tiedun.version", ""));
        title.setTextSize(22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        mInfo = new TextView(this);
        mInfo.setPadding(0, dp(12), 0, dp(12));
        mInfo.setText(buildInfoText());
        root.addView(mInfo);

        TextView urlLabel = new TextView(this);
        urlLabel.setText(R.string.label_server_url);
        root.addView(urlLabel);

        LinearLayout urlRow = new LinearLayout(this);
        urlRow.setOrientation(LinearLayout.HORIZONTAL);
        mUrlEdit = new EditText(this);
        mUrlEdit.setSingleLine(true);
        mUrlEdit.setText(CheckReceiver.serverUrl(this));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        urlRow.addView(mUrlEdit, lp);
        Button save = new Button(this);
        save.setText(R.string.btn_save);
        save.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String url = mUrlEdit.getText().toString().trim();
                getSharedPreferences("tiedun", MODE_PRIVATE).edit()
                        .putString("server_url", url).apply();
                toast(R.string.msg_saved);
            }
        });
        urlRow.addView(save);
        root.addView(urlRow);

        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        Button check = new Button(this);
        check.setText(R.string.btn_check);
        check.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                checkUpdates();
            }
        });
        btnRow.addView(check);
        Button local = new Button(this);
        local.setText(R.string.btn_local_install);
        local.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                pickLocal();
            }
        });
        btnRow.addView(local);
        root.addView(btnRow);

        mStatus = new TextView(this);
        mStatus.setPadding(0, dp(12), 0, dp(4));
        mStatus.setText(R.string.status_idle);
        root.addView(mStatus);

        mProgress = new ProgressBar(this, null,
                android.R.attr.progressBarStyleHorizontal);
        mProgress.setMax(100);
        root.addView(mProgress);

        mNotice = new TextView(this);
        mNotice.setPadding(0, dp(8), 0, 0);
        mNotice.setTextSize(12);
        mNotice.setTextColor(0xff888888);
        mNotice.setText(R.string.msg_bandwidth);
        mNotice.setVisibility(View.GONE);
        root.addView(mNotice);

        mResults = new LinearLayout(this);
        mResults.setOrientation(LinearLayout.VERTICAL);
        root.addView(mResults);

        setContentView(scroll);
    }

    private String buildInfoText() {
        StringBuilder sb = new StringBuilder();
        sb.append(getString(R.string.title_current)).append("\n");
        sb.append(SystemProperties.get("ro.tiedun.name", "TieDun OS")).append(" ")
                .append(SystemProperties.get("ro.tiedun.version", "")).append("\n");
        sb.append("Android ").append(SystemProperties.get("ro.tiedun.android", ""))
                .append(" · ").append(SystemProperties.get("ro.tiedun.base", "")).append("\n");
        sb.append("Kernel ").append(SystemProperties.get("ro.tiedun.kernel", "")).append("\n");
        sb.append("Security patch ")
                .append(SystemProperties.get("ro.build.version.security_patch", "")).append("\n");
        long date = SystemProperties.getLong("ro.build.date.utc", 0);
        if (date > 0) {
            sb.append("Build date ").append(new SimpleDateFormat("yyyy-MM-dd HH:mm",
                    Locale.getDefault()).format(new Date(date * 1000)));
        }
        return sb.toString();
    }

    private void checkUpdates() {
        mResults.removeAllViews();
        mStatus.setText(R.string.status_checking);
        new Thread(new Runnable() {
            @Override
            public void run() {
                List<OtaClient.Entry> got = null;
                String used = null;
                for (String base : CheckReceiver.channelCandidates(MainActivity.this)) {
                    try {
                        got = OtaClient.fetch(CheckReceiver.appendReport(MainActivity.this, base));
                        used = base;
                        break;
                    } catch (Throwable ignored) {
                        // 该通道失败, 降级到下一候选(穿透备选)
                    }
                }
                final List<OtaClient.Entry> entries = got;
                final String active = used;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        if (entries == null) {
                            mStatus.setText(R.string.msg_net_fail);
                            toast(R.string.msg_net_fail);
                            return;
                        }
                        if (active != null) {
                            mUrlEdit.setText(active);
                        }
                        showEntries(entries);
                    }
                });
            }
        }, "tiedun-ui-check").start();
    }

    private void showEntries(List<OtaClient.Entry> entries) {
        mResults.removeAllViews();
        if (entries.isEmpty()) {
            mStatus.setText(R.string.msg_no_update);
            return;
        }
        long buildDate = SystemProperties.getLong("ro.build.date.utc", 0);
        boolean found = false;
        for (final OtaClient.Entry e : entries) {
            boolean isNew = e.datetime > buildDate;
            if (isNew) {
                found = true;
            }
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(8), dp(12), dp(8), dp(12));

            TextView name = new TextView(this);
            name.setTextSize(16);
            name.setTypeface(Typeface.DEFAULT_BOLD);
            name.setText((isNew ? "★ " : "") + (e.version.length() > 0 ? e.version : e.filename));
            card.addView(name);

            TextView meta = new TextView(this);
            String date = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
                    .format(new Date(e.datetime * 1000));
            meta.setText(date + " · " + (e.size / 1048576) + " MB\n" + e.filename);
            card.addView(meta);

            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            Button install = new Button(this);
            install.setText(R.string.btn_install);
            install.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    confirmInstall(e);
                }
            });
            row.addView(install);
            Button download = new Button(this);
            download.setText(R.string.btn_download);
            download.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    startDownload(e, false);
                }
            });
            row.addView(download);
            card.addView(row);
            mResults.addView(card);
        }
        mStatus.setText(found ? R.string.msg_update_found : R.string.msg_no_update);
    }

    private void confirmInstall(final OtaClient.Entry e) {
        new AlertDialog.Builder(this)
                .setMessage(R.string.msg_install_confirm)
                .setPositiveButton(R.string.btn_confirm, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        startDownload(e, true);
                    }
                })
                .setNegativeButton(R.string.btn_cancel, null)
                .show();
    }

    private void startDownload(OtaClient.Entry e, boolean install) {
        Intent i = new Intent(this, DownloadService.class);
        i.putExtra(DownloadService.EXTRA_URL, e.url);
        i.putExtra(DownloadService.EXTRA_FILENAME, e.filename);
        i.putExtra(DownloadService.EXTRA_SHA256, e.sha256);
        i.putExtra(DownloadService.EXTRA_TOTAL, e.size);
        i.putExtra(DownloadService.EXTRA_INSTALL, install);
        startService(i);
        mStatus.setText(R.string.status_downloading);
        // 排队/下载中提示: 作者宽带有限, 一次只服务一位
        mNotice.setVisibility(View.VISIBLE);
    }

    private void pickLocal() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("application/zip");
        try {
            startActivityForResult(i, 2);
        } catch (Throwable t) {
            toast(R.string.msg_install_failed);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != 2 || resultCode != RESULT_OK || data == null
                || data.getData() == null) {
            return;
        }
        final Uri uri = data.getData();
        mStatus.setText(R.string.status_downloading);
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    File dir = new File(getFilesDir(), "ota");
                    dir.mkdirs();
                    String name = "local-" + System.currentTimeMillis() + ".zip";
                    File dest = new File(dir, name);
                    InputStream in = getContentResolver().openInputStream(uri);
                    FileOutputStream out = new FileOutputStream(dest);
                    byte[] buf = new byte[262144];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                    }
                    out.close();
                    in.close();
                    final boolean verified = Installer.verifyPackage(dest, null);
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            if (!verified) {
                                toast(R.string.msg_verify_fail);
                            }
                            confirmLocalInstall(dest);
                        }
                    });
                } catch (Throwable t) {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            mStatus.setText(R.string.msg_install_failed);
                            toast(R.string.msg_install_failed);
                        }
                    });
                }
            }
        }, "tiedun-local-copy").start();
    }

    private void confirmLocalInstall(final File dest) {
        boolean trusted = Installer.verifySignedByOtaCert(dest);
        if (!trusted) {
            // 铁盾更新器: 本地包必须是本人(OTA 证书)签名, 否则硬拒, 不给安装入口
            mStatus.setText(R.string.msg_sig_fail);
            new AlertDialog.Builder(this)
                    .setMessage(R.string.msg_sig_reject)
                    .setPositiveButton(R.string.btn_confirm, null)
                    .show();
            return;
        }
        new AlertDialog.Builder(this)
                .setMessage(R.string.msg_install_confirm)
                .setPositiveButton(R.string.btn_confirm, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        try {
                            mStatus.setText(R.string.status_installing);
                            Installer.install(MainActivity.this, dest);
                        } catch (Throwable t) {
                            mStatus.setText(R.string.msg_install_failed);
                            toast(R.string.msg_install_failed);
                        }
                    }
                })
                .setNegativeButton(R.string.btn_cancel, null)
                .show();
    }
}

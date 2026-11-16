/*
 * 铁盾OS C6: 铁盾系统更新 — 校验 + recovery 刷入 + 签名证书钉扎
 * 刷入路径与 LineageOS Updater 同款: RecoverySystem.installPackage(uncrypt 副本)
 * 签名锁死(用户拍板: 专有 OTA 密钥): 更新包的签名证书必须等于内嵌的 OTA 证书,
 * 否则拒绝安装(外人 testkey 也无法冒充)。证书为公开信息, 常量内嵌无密可泄。
 * SPDX-License-Identifier: GPL-3.0
 */
package com.tiedun.updater;

import android.content.Context;
import android.os.RecoverySystem;
import android.os.storage.StorageManager;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.PosixFilePermission;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.util.Arrays;
import java.util.Collection;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public final class Installer {

    public interface VerifyListener {
        void onProgress(int percent);
    }

    /**
     * 铁盾OS 专有 OTA 签名证书(公钥, 30年有效)。
     * 私钥保存在制作机 /mnt/data/tiedun-ota/secrets/(不入仓不分发)。
     */
    private static final String OTA_CERT_PEM =
            "-----BEGIN CERTIFICATE-----\n" +
            "MIIDIzCCAgugAwIBAgIUGWa6NmOCQv9qC12OMHzynkbGp3swDQYJKoZIhvcNAQEL\n" +
            "BQAwIDEeMBwGA1UEAwwVVGllRHVuIE9TIE9UQSBTaWduaW5nMCAXDTI2MTEwMzEz\n" +
            "MDA1N1oYDzIwNTYxMDI2MTMwMDU3WjAgMR4wHAYDVQQDDBVUaWVEdW4gT1MgT1RB\n" +
            "IFNpZ25pbmcwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCgBGyWNv3Q\n" +
            "etwJ87WDnJRjCJLpwvFjFBxRvTJ14yh9eAmHzSQVlKvmlYulF2zfbc8n95bWTjAz\n" +
            "ldvQp/H9up3TwXDktYtMhGGsQRe7lrAr58AOVLrYY6oACDwqThK3GfC1ASkGFXFh\n" +
            "QT8tboGV7QWAFvB2CMJIafjiJR6YxR1W5lz2HflGCDbmbPylgpiUR6k2DSSkpafL\n" +
            "ggJfb8ErDviFwCgrPG7Mg4rk0s6G8kQ1RYp+e7uzzrkCFKc1r9fp1nxD63bFzUQ4\n" +
            "babqJtl8T2GPc5cQHtwFn6np/Rv7FN1eL2mMTkGGQil5prWnqAvnPEKnHzxJoZ92\n" +
            "Kzr0IF2WyrBXAgMBAAGjUzBRMB0GA1UdDgQWBBSnqN1/+YEL2EhtLAEUB+LM236V\n" +
            "gzAfBgNVHSMEGDAWgBSnqN1/+YEL2EhtLAEUB+LM236VgzAPBgNVHRMBAf8EBTAD\n" +
            "AQH/MA0GCSqGSIb3DQEBCwUAA4IBAQATUFpM9/XzRncQ+iEsbfaMtqf4YGLH6qcc\n" +
            "vVV7urBSkNg7c3Kg0He/NzzZwxAHWpsi3SS05fvDJ4vXjU4jeQOKjTQPGhmyQl+l\n" +
            "/1Wqjdt98qyksoDF26PoCPtfZb0yOJ1sTsxG6JoHNZWiHqJPbva7FL7g9uK0KpJX\n" +
            "ngVg2f/Qip+5r/5Jy6jmIcojqDCA9GaqF4kBNppEsbPnFbWIWIUrQixtCphs4sn0\n" +
            "PbDKp3mkgpjD32aN1c8z0OetzYjrxYjxjAnMW4MdcbMN8eUKG9CGy4kFIn0wSbtl\n" +
            "Bi6EdWtmnG43qy4zTK5YzNKOwG54wEQWnB7/d2jYQfNwZmL76U6U\n" +
            "-----END CERTIFICATE-----\n";

    private Installer() {
    }

    private static byte[] sha256(byte[] data) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(data);
        } catch (Exception e) {
            return new byte[0];
        }
    }

    /** 取内嵌 OTA 证书的指纹 */
    private static byte[] pinnedCertDigest() {
        try {
            CertificateFactory cf = CertificateFactory.getInstance("X.509");
            Certificate c = cf.generateCertificate(new ByteArrayInputStream(
                    OTA_CERT_PEM.getBytes(StandardCharsets.UTF_8)));
            return sha256(c.getEncoded());
        } catch (Exception e) {
            return new byte[0];
        }
    }

    /**
     * 签名锁死: zip 的 META-INF 签名块(PKCS#7)里必须含内嵌 OTA 证书签的名。
     * 通过 = 真正的官方包; 不通过 = 伪造/未知来源, 调用方应拒绝安装。
     */
    public static boolean verifySignedByOtaCert(File file) {
        byte[] want = pinnedCertDigest();
        if (want.length == 0) {
            return false;
        }
        try {
            CertificateFactory cf = CertificateFactory.getInstance("X.509");
            ZipFile z = new ZipFile(file);
            try {
                Enumeration<? extends ZipEntry> en = z.entries();
                while (en.hasMoreElements()) {
                    ZipEntry e = en.nextElement();
                    String n = e.getName().toUpperCase(LocaleHolder.LOCALE);
                    if (!n.startsWith("META-INF/") || n.contains("/")) {
                        continue;
                    }
                    if (!(n.endsWith(".RSA") || n.endsWith(".EC") || n.endsWith(".DSA"))) {
                        continue;
                    }
                    InputStream in = z.getInputStream(e);
                    try {
                        Collection<? extends Certificate> certs =
                                cf.generateCertificates(in);
                        for (Certificate c : certs) {
                            if (Arrays.equals(want, sha256(c.getEncoded()))) {
                                return true;
                            }
                        }
                    } finally {
                        in.close();
                    }
                }
            } finally {
                z.close();
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    /** OTA 证书签名校验(失败仅提示, 是否强装由调用方决定) */
    public static boolean verifyPackage(File file, VerifyListener listener) {
        try {
            RecoverySystem.verifyPackage(file, new RecoverySystem.ProgressListener() {
                @Override
                public void onProgress(int progress) {
                    if (listener != null) {
                        listener.onProgress(progress);
                    }
                }
            }, null);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /** 重启到 recovery 刷入(FBE 存储先转 .uncrypt 副本供 uncrypt 建块映射) */
    public static void install(Context context, File file) throws IOException {
        File target = file;
        try {
            StorageManager sm = (StorageManager) context.getSystemService(Context.STORAGE_SERVICE);
            if (sm != null && sm.isEncrypted(file)) {
                target = new File(file.getAbsolutePath() + ".uncrypt");
                copyFile(file, target);
                Set<PosixFilePermission> perms = new HashSet<>();
                perms.add(PosixFilePermission.OWNER_READ);
                perms.add(PosixFilePermission.OWNER_WRITE);
                perms.add(PosixFilePermission.GROUP_READ);
                perms.add(PosixFilePermission.OTHERS_READ);
                Files.setPosixFilePermissions(target.toPath(), perms);
            }
        } catch (Throwable ignored) {
        }
        RecoverySystem.installPackage(context, target);
    }

    private static void copyFile(File src, File dst) throws IOException {
        FileInputStream in = new FileInputStream(src);
        FileOutputStream out = new FileOutputStream(dst);
        byte[] buf = new byte[262144];
        int n;
        try {
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
        } finally {
            try {
                out.close();
            } catch (IOException ignored) {
            }
            in.close();
        }
    }

    private static final class LocaleHolder {
        static final java.util.Locale LOCALE = java.util.Locale.US;
    }
}

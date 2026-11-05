#
# Copyright (C) 2018-2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_o_mr1.mk)

# Get non-open-source specific aspects
$(call inherit-product, vendor/xiaomi/dipper/dipper-vendor.mk)

# Boot animation
TARGET_SCREEN_HEIGHT := 2248
TARGET_SCREEN_WIDTH := 1080

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay \
    $(LOCAL_PATH)/overlay-lineage

PRODUCT_PACKAGES += \
    NoCutoutOverlay

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.nfc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.xml \
    frameworks/native/data/etc/android.hardware.nfc.hce.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hce.xml \
    frameworks/native/data/etc/android.hardware.nfc.hcef.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hcef.xml \
    frameworks/native/data/etc/android.hardware.sensor.barometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.barometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.hifi_sensors.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.hifi_sensors.xml \
    frameworks/native/data/etc/com.android.nfc_extras.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.android.nfc_extras.xml \
    frameworks/native/data/etc/com.nxp.mifare.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.nxp.mifare.xml

# Screen density
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

# Treble
PRODUCT_USE_VNDK_OVERRIDE := true

# Inherit from sdm845-common
$(call inherit-product, device/xiaomi/sdm845-common/sdm845.mk)

# ===== 铁盾OS 定制(需求冻结定稿) =====
# B4: 开机动画(黑底纯文字无logo) + 关机动画
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/tiedun-media/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip \
    $(LOCAL_PATH)/tiedun-media/shutdownanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/shutdownanimation.zip

# B3: tiedun-priv KSU 通道(KSU白名单预置/Shizuku root拉起开机自启自动授权)
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/tiedun-priv/tiedun-priv.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/tiedun-priv.rc \
    $(LOCAL_PATH)/tiedun-priv/module.prop:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/module.prop \
    $(LOCAL_PATH)/tiedun-priv/service.sh:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/service.sh \
    $(LOCAL_PATH)/tiedun-priv/tiedun-ksu-grant:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/tiedun-ksu-grant \
    $(LOCAL_PATH)/tiedun-priv/tiedun-priv.zip:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/tiedun-priv.zip

# B8: 性能档位(均衡/性能/省电) init 调频触发器
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/tiedun-perf/tiedun-perf.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/tiedun-perf.rc

# B2: 预装件 + B11: Lawnchair 默认桌面
PRODUCT_PACKAGES += \
    TieDunShield \
    Shizuku \
    FossBrowser \
    Lawnchair \
    TiedunUpdater

# B11: 风格层独立overlay(默认壁纸) + Roboto 字体
PRODUCT_PACKAGES += \
    TieDunFrameworkOverlay

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Regular.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Regular.ttf \
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Medium.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Medium.ttf \
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Bold.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Bold.ttf \
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Light.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Light.ttf \
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Italic.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Italic.ttf

# B6: 版本属性六组 + B10: 简中/北京时区默认
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.tiedun.name=TieDun OS \
    ro.tiedun.version=1.0.2.4 \
    ro.tiedun.android=17 \
    ro.tiedun.base=LineageOS 24.0 \
    ro.tiedun.kernel=4.19.325 \
    ro.tiedun.author=lilining308 \
    ro.product.locale=zh-CN \
    persist.sys.timezone=Asia/Shanghai \
    ro.product.marketname=小米 8

# Audio
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/audio_platform_info.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_platform_info.xml \
    $(LOCAL_PATH)/audio/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml \
    $(LOCAL_PATH)/audio/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml \
    $(LOCAL_PATH)/audio/mixer_paths_overlay_dynamic.xml:$(TARGET_COPY_OUT_VENDOR)/etc/mixer_paths_overlay_dynamic.xml \
    $(LOCAL_PATH)/audio/mixer_paths_overlay_static.xml:$(TARGET_COPY_OUT_VENDOR)/etc/mixer_paths_overlay_static.xml \
    $(LOCAL_PATH)/audio/sound_trigger_mixer_paths_wcd9340.xml:$(TARGET_COPY_OUT_VENDOR)/etc/sound_trigger_mixer_paths_wcd9340.xml \
    $(LOCAL_PATH)/audio/sound_trigger_platform_info.xml:$(TARGET_COPY_OUT_VENDOR)/etc/sound_trigger_platform_info.xml

# Control groups and task profiles
PRODUCT_COPY_FILES += \
    system/core/libprocessgroup/profiles/cgroups_28.json:$(TARGET_COPY_OUT_VENDOR)/etc/cgroups.json \
    system/core/libprocessgroup/profiles/task_profiles_28.json:$(TARGET_COPY_OUT_VENDOR)/etc/task_profiles.json

# Device fstab
PRODUCT_PACKAGES += \
    fstab.qcom \
    fstab.qcom.ramdisk

# Device init scripts
PRODUCT_PACKAGES += \
    init.target.rc

# GPS
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/gps/gps_debug.conf:$(TARGET_COPY_OUT_SYSTEM)/etc/gps_debug.conf

PRODUCT_PACKAGES += \
    gps.conf_symlink

# Input
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/idc/uinput-fpc.idc:system/usr/idc/uinput-fpc.idc \
    $(LOCAL_PATH)/idc/uinput-goodix.idc:system/usr/idc/uinput-goodix.idc

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/gpio-keys.kl:system/usr/keylayout/gpio-keys.kl \
    $(LOCAL_PATH)/keylayout/uinput-fpc.kl:system/usr/keylayout/uinput-fpc.kl \
    $(LOCAL_PATH)/keylayout/uinput-goodix.kl:system/usr/keylayout/uinput-goodix.kl

# LiveDisplay
PRODUCT_PACKAGES += \
    vendor.lineage.livedisplay-service.xiaomi_sdm845

# NFC
PRODUCT_PACKAGES += \
    android.hardware.nfc-service.nxp \
    com.android.nfc_extras \
    Tag

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/nfc/libnfc-nci.conf:$(TARGET_COPY_OUT_PRODUCT)/etc/libnfc-nci.conf \
    $(LOCAL_PATH)/nfc/libnfc-nxp.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nxp.conf

# PocketMode
PRODUCT_PACKAGES += \
    XiaomiPocketMode

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# WiFi
PRODUCT_PACKAGES += \
    TargetWifiOverlay

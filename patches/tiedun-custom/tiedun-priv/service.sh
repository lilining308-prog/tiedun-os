#!/system/bin/sh
# 铁盾 OS · tiedun-priv KSU 模块 (Q3=内置KernelSU默认激活的白名单载体)
# ① KSU 白名单预置: 铁盾之盾 + Shizuku root免弹窗 (内核专有通道)
# ② Shizuku root拉起 + 开机自启
# 由 KernelSU 每次开机以 root 执行
MODDIR=${0%/*}
TAG="tiedun-priv"
LOG=/data/adb/tiedun-priv.log
log() { echo "$(date '+%m-%d %H:%M:%S') [$TAG] $1" >> "$LOG"; }

log "===== boot service start ====="

# ── ① KSU 白名单预置 (tiedun-ksu-grant: prctl -> CMD_SET_APP_PROFILE, 持久化) ──
GRANT="$MODDIR/tiedun-ksu-grant"
chmod 755 "$GRANT" 2>/dev/null
if [ -x "$GRANT" ]; then
    i=0
    while [ $i -lt 30 ]; do
        if "$GRANT" com.lilining.lockescape moe.shizuku.privileged.api >> "$LOG" 2>&1; then
            log "allowlist preset ok"
            break
        fi
        log "grant retry #$i (应用可能尚未安装/初始化)"
        i=$((i+1))
        sleep 10
    done
else
    log "tiedun-ksu-grant missing!"
fi

# ── ② Shizuku root拉起(等开机完成) + 开机自启 ──
(
  i=0
  while [ $i -lt 90 ]; do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 2
    i=$((i+1))
  done
  sleep 5
  SH=/data/user_de/0/moe.shizuku.privileged.api/start.sh
  if [ -f "$SH" ]; then
    sh "$SH" >> "$LOG" 2>&1 && log "shizuku root start ok"
  else
    log "shizuku start.sh 不存在(Shizuku 未装或未初始化), 跳过"
  fi
) &


# ── ③ Android 权限全量预授权 (铁盾OS B15: 用户要求全给, 不逐项深查) ──
(
  i=0
  while [ $i -lt 90 ]; do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 2
    i=$((i+1))
  done
  sleep 5
  PKG=com.lilining.lockescape
  # (a) manifest 声明的所有可授运行时权限 → pm grant
  for P in $(dumpsys package $PKG 2>/dev/null | grep -oE "android\.permission\.[A-Z_0-9]+|moe\.shizuku\.manager\.permission\.API_V23" | sort -u); do
    pm grant $PKG $P 2>/dev/null
  done
  log "manifest 权限 pm grant 完成"
  # (b) 所有 AppOps → allow(悬浮窗/后台/通知/开机自启等全覆盖)
  for OP in $(appops get $PKG 2>/dev/null | sed -n 's/^ *\([A-Za-z_0-9]*\):.*/\1/p' | sort -u); do
    appops set $PKG $OP allow 2>/dev/null
  done
  log "appops 全量 allow 完成"
  # (c) 电池优化白名单 + 无障碍第三档通道
  dumpsys deviceidle whitelist +$PKG >/dev/null 2>&1 && log "电池优化白名单 ok"
  SVC="$PKG/com.lilining.lockescape.EscapeAccessibilityService"
  CUR=$(settings get secure enabled_accessibility_services 2>/dev/null)
  case "$CUR" in
    *$PKG*) log "无障碍已启用, 跳过" ;;
    *)
      if [ -n "$CUR" ] && [ "$CUR" != "null" ]; then
        settings put secure enabled_accessibility_services "$CUR:$SVC" 2>/dev/null
      else
        settings put secure enabled_accessibility_services "$SVC" 2>/dev/null
      fi
      settings put secure accessibility_enabled 1 2>/dev/null
      log "无障碍第三档预启用: $SVC" ;;
  esac
) &

log "===== boot service done ====="

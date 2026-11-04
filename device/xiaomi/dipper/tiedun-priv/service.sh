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

log "===== boot service done ====="

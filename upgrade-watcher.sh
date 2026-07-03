#!/usr/bin/env bash
# ============================================================
# Spider-Pool 升级监听器
# 后端 POST /api/system/upgrade 会在 $INSTALL_DIR/signal/.upgrade-request 写信号文件。
# 本 watcher 检测到该文件后执行 pull + up -d(后端启动自动跑幂等迁移),然后删信号。
#
# 两种运行方式:
#   常驻(systemd):  spider-pool-upgrade-watcher          # 循环轮询
#   单次(cron):     spider-pool-upgrade-watcher --once   # 检查一次即退出
# ============================================================
set -euo pipefail

INSTALL_DIR="${SPIDER_POOL_DIR:-/opt/spider-pool}"
SIGNAL="$INSTALL_DIR/signal/.upgrade-request"
COMPOSE_FILE="docker-compose.prod.yml"
LOG="$INSTALL_DIR/upgrade.log"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

do_upgrade() {
  [ -f "$SIGNAL" ] || return 0
  log "检测到升级信号,开始升级…"
  # 先删信号,避免升级中后端重启又触发重复升级
  rm -f "$SIGNAL"
  cd "$INSTALL_DIR"
  if $DC -f "$COMPOSE_FILE" pull >>"$LOG" 2>&1 && \
     $DC -f "$COMPOSE_FILE" up -d >>"$LOG" 2>&1; then
    log "升级完成(镜像已更新并重启,迁移由后端启动自动应用)。"
  else
    log "升级失败,请检查 $LOG 与 docker 状态。"
  fi
}

if [ "${1:-}" = "--once" ]; then
  do_upgrade
  exit 0
fi

log "升级监听器已启动,轮询 $SIGNAL"
while true; do
  do_upgrade
  sleep 10
done

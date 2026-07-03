#!/usr/bin/env bash
# ============================================================
# spider-pool —— Spider-Pool 便捷运维命令
#   spider-pool status | logs | upgrade | restart | stop | start
# ============================================================
set -euo pipefail

INSTALL_DIR="${SPIDER_POOL_DIR:-/opt/spider-pool}"
COMPOSE_FILE="docker-compose.prod.yml"
REPO_RAW="https://raw.githubusercontent.com/llff9527-blip/spider-pool-installer/main"

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
cd "$INSTALL_DIR" 2>/dev/null || { echo "未找到安装目录 $INSTALL_DIR"; exit 1; }

case "${1:-}" in
  status) $DC -f "$COMPOSE_FILE" ps ;;
  logs)   shift; $DC -f "$COMPOSE_FILE" logs -f "${@:-}" ;;
  restart) $DC -f "$COMPOSE_FILE" restart ;;
  stop)   $DC -f "$COMPOSE_FILE" down ;;
  start)  $DC -f "$COMPOSE_FILE" up -d ;;
  upgrade)
    # 直接拉最新安装脚本重跑(等价升级)
    curl -fsSL "$REPO_RAW/install.sh" | bash ;;
  *)
    echo "用法: spider-pool {status|logs|upgrade|restart|stop|start}" ;;
esac

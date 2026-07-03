#!/usr/bin/env bash
# ============================================================
# Spider-Pool 一键安装 / 升级
#   curl -fsSL https://raw.githubusercontent.com/llff9527-blip/spider-pool-installer/main/install.sh | bash
#
# 首次运行:安装 Docker(如缺) → 拉取 GHCR 公开镜像 → 启动全栈。
# 再次运行:等价升级(pull 最新镜像 + 重启;后端启动自动跑幂等迁移)。
# 幂等:任意次数重复执行安全。
# ============================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/llff9527-blip/spider-pool-installer/main"
INSTALL_DIR="${SPIDER_POOL_DIR:-/opt/spider-pool}"
COMPOSE_FILE="docker-compose.prod.yml"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info() { echo -e "${G}==>${N} $*"; }
warn() { echo -e "${Y}!! ${N} $*"; }
err()  { echo -e "${R}xx ${N} $*" >&2; }

# root 检查(装 docker / 写 /opt 需要)
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    err "需要 root 权限(安装 Docker / 写 $INSTALL_DIR)。请用 root 运行或安装 sudo。"; exit 1
  fi
fi

# ---------- 1. 安装 Docker(如缺) ----------
if ! command -v docker >/dev/null 2>&1; then
  info "未检测到 Docker,自动安装(get.docker.com)…"
  curl -fsSL https://get.docker.com | $SUDO sh
  $SUDO systemctl enable --now docker 2>/dev/null || true
else
  info "Docker 已安装:$(docker --version)"
fi

# compose 命令兼容
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  err "未找到 docker compose 插件,请升级 Docker(需 Compose V2)。"; exit 1
fi

# ---------- 2. 准备安装目录 ----------
$SUDO mkdir -p "$INSTALL_DIR/signal"
cd "$INSTALL_DIR"

IS_UPGRADE=0
[ -f "$INSTALL_DIR/.env" ] && IS_UPGRADE=1

# ---------- 3. 下载 compose + nginx.conf ----------
info "下载编排文件…"
$SUDO curl -fsSL "$REPO_RAW/$COMPOSE_FILE" -o "$INSTALL_DIR/$COMPOSE_FILE"
$SUDO curl -fsSL "$REPO_RAW/nginx.conf" -o "$INSTALL_DIR/nginx.conf"

# ---------- 4. 首次生成 .env(随机密钥);升级则保留 ----------
if [ "$IS_UPGRADE" -eq 0 ]; then
  info "首次安装:生成 .env(随机 DB 密码 / JWT 密钥)…"
  rand() { LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "${1:-32}"; }
  $SUDO tee "$INSTALL_DIR/.env" >/dev/null <<EOF
# Spider-Pool 生产配置(首次自动生成,可按需修改后重跑 install.sh 生效)
IMAGE_TAG=latest
DB_PASSWORD=$(rand 24)
JWT_SECRET=$(rand 40)
# AI 凭证(留空则登录后管后在「系统设置」填写)
AI_API_KEY=
AI_API_URL=https://api.deepseek.com
AI_MODEL=deepseek-chat
VERSION_MANIFEST_URL=$REPO_RAW/version.json
EOF
else
  info "检测到已安装 → 升级模式(保留现有 .env)。"
fi

# ---------- 5. 拉镜像并启动 ----------
info "拉取最新镜像…"
$SUDO $DC -f "$COMPOSE_FILE" pull
info "启动 / 重启服务…"
$SUDO $DC -f "$COMPOSE_FILE" up -d

# ---------- 6. 安装升级 watcher + spider-pool CLI ----------
info "安装升级监听与 spider-pool 命令…"
$SUDO curl -fsSL "$REPO_RAW/upgrade-watcher.sh" -o /usr/local/bin/spider-pool-upgrade-watcher
$SUDO chmod +x /usr/local/bin/spider-pool-upgrade-watcher
$SUDO curl -fsSL "$REPO_RAW/spider-pool.sh" -o /usr/local/bin/spider-pool
$SUDO chmod +x /usr/local/bin/spider-pool

# systemd 优先;无 systemd 则回退 cron
if command -v systemctl >/dev/null 2>&1; then
  $SUDO tee /etc/systemd/system/spider-pool-watcher.service >/dev/null <<EOF
[Unit]
Description=Spider-Pool upgrade watcher
After=docker.service
[Service]
Environment=SPIDER_POOL_DIR=$INSTALL_DIR
ExecStart=/usr/local/bin/spider-pool-upgrade-watcher
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now spider-pool-watcher.service
else
  warn "无 systemd,改用 cron 每分钟检查升级信号。"
  ( $SUDO crontab -l 2>/dev/null | grep -v spider-pool-upgrade-watcher; \
    echo "* * * * * SPIDER_POOL_DIR=$INSTALL_DIR /usr/local/bin/spider-pool-upgrade-watcher --once" ) | $SUDO crontab -
fi

# ---------- 7. 完成 ----------
echo ""
if [ "$IS_UPGRADE" -eq 1 ]; then
  info "升级完成!服务已重启为最新版本。"
else
  info "安装完成!"
fi
echo -e "${G}========================================${N}"
echo -e "  后管前端:  ${G}http://<本机IP>:13000${N}  (admin / admin123)"
echo -e "  后端 API:  http://<本机IP>:8095"
echo -e "  泛站入口:  http://<域名>/  (需 DNS 泛解析到本机)"
echo -e "  安装目录:  $INSTALL_DIR"
echo -e "  常用命令:  ${Y}spider-pool {status|logs|upgrade|restart|stop}${N}"
echo -e "${G}========================================${N}"

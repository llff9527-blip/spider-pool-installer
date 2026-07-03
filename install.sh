#!/usr/bin/env bash
# ============================================================
# Spider-Pool 一键安装 / 升级(零 token,编译产物分发)
#   curl -fsSL https://raw.githubusercontent.com/llff9527-blip/spider-pool-installer/main/install.sh | bash
#
# 原理:源码不公开;CI 编译产物(后端二进制 + 前端 standalone,均不含源码)发布到本
# 公开仓库的 Release 资产,免 token 下载。运行时用官方公开镜像(chromium/node)挂载产物。
#
# 首次:装 Docker(如缺) → 下载产物 → 官方镜像挂载启动全栈。
# 再次:等价升级(重新下载最新产物 + 重启;后端启动自动跑幂等迁移)。幂等,可重复执行。
# ============================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/llff9527-blip/spider-pool-installer/main"
REL_BASE="https://github.com/llff9527-blip/spider-pool-installer/releases/download/latest"
INSTALL_DIR="${SPIDER_POOL_DIR:-/opt/spider-pool}"
COMPOSE_FILE="docker-compose.prod.yml"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info() { echo -e "${G}==>${N} $*"; }
warn() { echo -e "${Y}!! ${N} $*"; }
err()  { echo -e "${R}xx ${N} $*" >&2; }

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

if docker compose version >/dev/null 2>&1; then
  DC="$SUDO docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="$SUDO docker-compose"
else
  err "未找到 docker compose 插件,请升级 Docker(需 Compose V2)。"; exit 1
fi

# ---------- 2. 准备安装目录 ----------
$SUDO mkdir -p "$INSTALL_DIR/signal"
cd "$INSTALL_DIR"

IS_UPGRADE=0
[ -f "$INSTALL_DIR/.env" ] && IS_UPGRADE=1

# ---------- 3. 下载编排 + 配置 ----------
info "下载编排文件…"
$SUDO curl -fsSL "$REPO_RAW/$COMPOSE_FILE" -o "$INSTALL_DIR/$COMPOSE_FILE"
$SUDO curl -fsSL "$REPO_RAW/nginx.conf" -o "$INSTALL_DIR/nginx.conf"

# ---------- 4. 下载并解压编译产物(免 token) ----------
info "下载后端产物…"
$SUDO curl -fsSL "$REL_BASE/backend.tar.gz" -o /tmp/sp-backend.tar.gz
$SUDO rm -rf "$INSTALL_DIR/backend" && $SUDO mkdir -p "$INSTALL_DIR/backend"
$SUDO tar -C "$INSTALL_DIR/backend" -xzf /tmp/sp-backend.tar.gz
$SUDO chmod +x "$INSTALL_DIR/backend/server"

info "下载前端产物…"
$SUDO curl -fsSL "$REL_BASE/frontend.tar.gz" -o /tmp/sp-frontend.tar.gz
$SUDO rm -rf "$INSTALL_DIR/frontend" && $SUDO mkdir -p "$INSTALL_DIR/frontend"
$SUDO tar -C "$INSTALL_DIR/frontend" -xzf /tmp/sp-frontend.tar.gz
$SUDO rm -f /tmp/sp-backend.tar.gz /tmp/sp-frontend.tar.gz

# ---------- 5. 首次生成 .env(随机密钥);升级保留 ----------
if [ "$IS_UPGRADE" -eq 0 ]; then
  info "首次安装:生成 .env(随机 DB 密码 / JWT 密钥)…"
  rand() { LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "${1:-32}"; }
  $SUDO tee "$INSTALL_DIR/.env" >/dev/null <<EOF
# Spider-Pool 生产配置(首次自动生成)
DB_PASSWORD=$(rand 24)
JWT_SECRET=$(rand 40)
AI_API_KEY=
AI_API_URL=https://api.deepseek.com
AI_MODEL=deepseek-chat
VERSION_MANIFEST_URL=$REPO_RAW/version.json
EOF
else
  info "检测到已安装 → 升级模式(保留现有 .env)。"
fi

# ---------- 6. 拉官方镜像并启动 ----------
info "拉取官方运行镜像(chromium/node/postgres/redis/nginx)…"
$DC -f "$COMPOSE_FILE" pull 2>/dev/null || true
info "启动 / 重启服务…"
$DC -f "$COMPOSE_FILE" up -d
# 后端/前端产物是 bind-mount:文件内容变了但容器配置未变,up -d 不会重建,
# 旧二进制/旧 standalone 仍常驻内存,导致升级后版本号不变(升级提示不消失)。
# 升级模式下必须强制重建这两个容器,让其重新加载最新挂载产物。
if [ "$IS_UPGRADE" -eq 1 ]; then
  info "强制重建 backend/frontend 以加载最新产物…"
  $DC -f "$COMPOSE_FILE" up -d --force-recreate --no-deps backend frontend
fi

# ---------- 7. 安装升级 watcher + spider-pool CLI ----------
info "安装升级监听与 spider-pool 命令…"
$SUDO curl -fsSL "$REPO_RAW/upgrade-watcher.sh" -o /usr/local/bin/spider-pool-upgrade-watcher
$SUDO chmod +x /usr/local/bin/spider-pool-upgrade-watcher
$SUDO curl -fsSL "$REPO_RAW/spider-pool.sh" -o /usr/local/bin/spider-pool
$SUDO chmod +x /usr/local/bin/spider-pool

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

# ---------- 8. 完成 ----------
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

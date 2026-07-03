# Spider-Pool 一键安装

站群 SEO 系统的公开安装器。源码仓库私有,镜像通过 GHCR 公开分发,`docker pull` 免认证。

## 安装 / 升级

在任意 Linux 服务器(需 root 或 sudo)执行:

```bash
curl -fsSL https://raw.githubusercontent.com/llff9527-blip/spider-pool-installer/main/install.sh | bash
```

- **首次**:自动安装 Docker(如缺)→ 拉取镜像 → 启动全栈(PostgreSQL / Redis / 后端 / 后管前端 / nginx)。
- **再次执行**:等价升级(拉最新镜像 + 重启;数据库迁移由后端启动自动幂等应用)。

安装后访问:

| 服务 | 地址 |
|------|------|
| 后管前端 | `http://<本机IP>:13000`(默认 `admin` / `admin123`) |
| 后端 API | `http://<本机IP>:8095` |
| 泛站入口 | `http://<域名>/`(需 DNS 泛解析到本机) |

## 升级方式

1. **后管一键升级**:有新版本时后管顶部悬浮提示 → 点「一键升级」→ 后端写升级信号 → 宿主 `spider-pool-watcher` 自动 `pull + up` 重启。
2. **命令行**:`spider-pool upgrade`(等价重跑安装脚本)。

## 常用命令

```bash
spider-pool status    # 查看服务状态
spider-pool logs      # 跟随日志
spider-pool upgrade   # 手动升级到最新
spider-pool restart   # 重启
spider-pool stop      # 停止
spider-pool start     # 启动
```

## 文件说明

| 文件 | 作用 |
|------|------|
| `install.sh` | 一键安装/升级主脚本 |
| `upgrade-watcher.sh` | 宿主升级监听器(systemd/cron),监听后端升级信号 |
| `spider-pool.sh` | `spider-pool` 便捷运维命令 |
| `docker-compose.prod.yml` | 生产编排(引用 GHCR 镜像) |
| `nginx.conf` | 泛站反向代理配置 |
| `version.json` | 最新版本清单(CI 自动更新,后管据此判断有无新版) |

> 安装目录默认 `/opt/spider-pool`;可用 `SPIDER_POOL_DIR` 环境变量自定义。

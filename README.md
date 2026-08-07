# Seafile 极简部署

基于 Docker Compose，一键部署 Seafile 私有云。

## 快速开始

### 1. 环境检查
```bash
docker --version
docker compose version
```

### 2. 配置修改
编辑 `config/.env`，设置：
- `SEAFILE_ADMIN_PASSWORD`
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_PASSWORD`

**密码生成工具**：
```bash
generate_password() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16; }
echo "密码: $(generate_password)"
```

### 3. 一键部署
```bash
chmod +x deploy.sh
./deploy.sh
```

访问：`http://IP:8080`

## 架构

```
┌─────────┐     ┌──────────┐     ┌────────────┐
│  Caddy  │────▶│  Seafile │────▶│  MariaDB   │
│  :8080  │     │   :80    │     │   :3306    │
└─────────┘     └──────────┘     └────────────┘
                              └────────────┐
                                         ▼
                                   ┌──────────┐
                                   │Memcached │
                                   │  :11211  │
                                   └──────────┘
```

## 目录结构
```
seafile-deploy/
├── deploy.sh              # 主部署脚本
├── config/                # 配置文件
│   ├── .env              # 环境变量
│   ├── docker-compose.yml # 服务配置
│   └── Caddyfile         # 反向代理
├── scripts/               # 辅助脚本
│   └── config_seafile.sh # 应用配置
└── data/                  # 数据存储
    ├── seafile/          # 应用数据
    ├── mariadb/          # 数据库
    └── caddy/            # Caddy 数据和日志
```

## 服务管理

```bash
docker compose -p seafile -f config/docker-compose.yml up -d    # 启动
docker compose -p seafile -f config/docker-compose.yml down    # 停止
docker compose -p seafile -f config/docker-compose.yml restart # 重启
docker compose -p seafile -f config/docker-compose.yml logs -f # 日志
```

## 数据备份

```bash
# 备份
docker compose -p seafile -f config/docker-compose.yml down
tar -czvf seafile-backup-$(date +%Y%m%d).tar.gz data/
docker compose -p seafile -f config/docker-compose.yml up -d

# 恢复
docker compose -p seafile -f config/docker-compose.yml down
rm -rf data/
tar -xzf seafile-backup-20240101.tar.gz
docker compose -p seafile -f config/docker-compose.yml up -d
```

## 配置说明

### 环境变量 (.env)
- 服务器：`SERVER_IP`, `HTTP_PORT`
- 管理员：`SEAFILE_ADMIN_EMAIL`, `SEAFILE_ADMIN_PASSWORD`
- 数据库：`MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`
- 时区：`TZ`

### Docker Compose (docker-compose.yml)
- 服务：MariaDB、Memcached、Seafile、Caddy
- 数据：本地目录挂载
- 资源：树莓派优化配置
- 健康：服务状态检查

> **💡 缓存建议**：Seafile 镜像默认使用 Memcached，零配置即可工作。如使用 Redis 需要额外配置 `seahub_settings.py`，复杂度较高，建议保持默认的 Memcached。

## 启用 HTTPS

修改 `config/Caddyfile`：

```caddy
# 证书配置二选一
# 自签名证书（内网用，没有域名，建议使用）
{$SERVER_IP}:443 {
    tls internal
    reverse_proxy seafile-app:80
}

# Let's Encrypt（有域名，建议使用）
example.com:443 {
    tls your@email.com
    reverse_proxy seafile-app:80
}

# HTTP 重定向 HTTPS（附加功能，配合上面任意一个证书）
:80 {
    redir https://{host}{uri}
}
```

重启：`docker compose -p seafile -f config/docker-compose.yml restart caddy`

> 💡 使用 Memcached 而非 Redis，零配置，更简单。

---


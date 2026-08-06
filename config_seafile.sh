# Seafile 极简部署配置
# 版本: 2026.03.22
# 遵循UNIX哲学：Just Enough

#!/bin/bash
set -euo pipefail

# 目录定义
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$PROJECT_DIR/config"

# 检查环境文件
if [ ! -f "$CONFIG_DIR/.env" ]; then
    echo "错误: 环境配置文件 $CONFIG_DIR/.env 不存在" >&2
    exit 1
fi

# 安全加载环境变量
set -a
source "$CONFIG_DIR/.env"
set +a

# 确定 Docker Compose 命令
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

# 执行容器命令（带错误处理）
exec_in_container() {
    local service="$1"
    local command="$2"
    $DOCKER_COMPOSE_CMD -p seafile -f "$CONFIG_DIR/docker-compose.yml" exec -T "$service" bash -c "$command"
}

# 配置 Seafile 服务
configure_seafile() {
    echo "配置 Seafile 服务..."
    
    # 使用 -s 代替 -f 来处理 302 重定向
    if exec_in_container seafile "curl -s http://localhost >/dev/null 2>&1"; then
        echo "✅ Seafile 服务正常"
    else
        echo "⚠️ Seafile 服务异常" >&2
        return 1
    fi
}

# 配置 Gunicorn 监听地址
configure_gunicorn() {
    echo "配置 Gunicorn 监听地址..."
    
    # 修改 gunicorn.conf.py 中的 bind 地址
    exec_in_container seafile "sed -i 's/bind = \"127.0.0.1:8000\"/bind = \"0.0.0.0:8000\"/' /opt/seafile/conf/gunicorn.conf.py"
    
    echo "✅ Gunicorn 配置完成"
}

# 配置性能优化
configure_performance() {
    echo "配置性能优化..."
    local conf="/opt/seafile/conf/seahub_settings.py"
    
    # 先确保配置文件存在
    exec_in_container seafile "touch '$conf'"
    
    # Seafile 默认使用 Memcached，不需要额外配置 CACHES
    # 只保留其他必要的配置

    # ========== 保留你原有的其他配置 ==========
    config_exists "$conf" "MAX_UPLOAD_SIZE" || add_config "$conf" "MAX_UPLOAD_SIZE = 10737418240"
    config_exists "$conf" "CSRF_TRUSTED_ORIGINS" || add_config "$conf" "CSRF_TRUSTED_ORIGINS = [\"http://$SERVER_IP:$HTTP_PORT\", \"http://localhost:$HTTP_PORT\"]"
    config_exists "$conf" "ALLOWED_HOSTS" || add_config "$conf" "ALLOWED_HOSTS = [\"$SERVER_IP\", \"localhost\", \"127.0.0.1\", \"seafile-app\"]"
    config_exists "$conf" "CSRF_COOKIE_SECURE" || add_config "$conf" "CSRF_COOKIE_SECURE = False"
    config_exists "$conf" "SESSION_COOKIE_DOMAIN" || add_config "$conf" "SESSION_COOKIE_DOMAIN = None"
 
    echo "✅ 性能优化 + CSRF 配置完成"
}

# 检查配置是否存在
config_exists() {
    local config_file="$1"
    local config_key="$2"
    exec_in_container seafile "grep -q '^$config_key' '$config_file' 2>/dev/null"
}

# 安全添加配置（避免重复和文件不存在）
add_config() {
    local config_file="$1"
    local config_line="$2"
    
    # 确保文件存在
    exec_in_container seafile "touch '$config_file'"
    
    # 检查是否已存在，避免重复添加
    if ! config_exists "$config_file" "${config_line%%=*}"; then
        exec_in_container seafile "echo '$config_line' >> '$config_file'"
    fi
}

# 主流程
main() {
    configure_seafile || exit 1
    configure_gunicorn || exit 1
    configure_performance || exit 1
}

# 执行主流程
main

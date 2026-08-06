# Seafile 极简部署配置
# 版本: 2026.03.22
# 遵循UNIX哲学：Just Enough

#!/bin/bash
set -euo pipefail

# 目录定义
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# 创建数据目录并设置权限
# 修改 create_data_dir 函数（修复权限）
create_data_dir() {
    echo "创建数据目录..."
    local dirs=(
        "./data/seafile"
        "./data/mariadb"
        "./data/caddy/data"
        "./data/caddy/config"
        "./data/caddy/log"
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" || exit 1
        # 仅保留权限设置，移除 chown（普通用户无权限修改所有权）
        chmod -R 755 "$dir"
    done
    echo "✅ 数据目录创建完成（跳过所有权修改，Docker 自动适配）"
}

# 启动服务
start_services() {
    echo "启动服务..."
    $DOCKER_COMPOSE_CMD -p seafile -f "$CONFIG_DIR/docker-compose.yml" up -d --wait --quiet-pull || exit 1
}

# 验证部署
verify_deployment() {
    echo "验证部署..."
    
    if curl -s "http://${SERVER_IP}:${HTTP_PORT}" >/dev/null 2>&1; then
        echo "✅ 部署成功"
    else
        echo "❌ 部署失败" >&2
        exit 1
    fi
}

# 主流程
main() {
    echo "开始部署 Seafile..."
    
    # 按顺序执行部署，任一失败则停止
    create_data_dir || exit 1
    start_services || exit 1

    # 新增：等待 Seafile 初始化完成（关键）
    echo "等待 Seafile 初始化..."
    sleep 60
    
    # 新增：执行配置脚本
    echo "配置 Seafile 服务..."
    bash "$PROJECT_DIR/scripts/config_seafile.sh" || exit 1
    
    # 重启 Seafile 使配置生效
    $DOCKER_COMPOSE_CMD -p seafile -f "$CONFIG_DIR/docker-compose.yml" restart seafile
 
    verify_deployment || exit 1

    # --------------------------
    # 调试阶段：添加权限命令（仅调试用）
    # 注意：在生产环境中，应避免直接修改文件权限，而应通过 Docker 配置来管理权限。
    # 假定用户为 student，UID 为 10000，GID 为 10000 ，用于部署和调试。
    # --------------------------
    #echo "赋予 student 用户数据目录访问权限（调试模式）..."
    #sudo chown -R student:student /home/student/seafile-deploy/data
    #sudo chmod -R 755 /home/student/seafile-deploy/data

    echo "Seafile 部署完成！"
    echo -e "\n访问地址: \033[32mhttp://${SERVER_IP}:${HTTP_PORT}\033[0m"
    echo -e "管理员邮箱: \033[32m${SEAFILE_ADMIN_EMAIL}\033[0m"
    echo -e "管理员密码: \033[32m${SEAFILE_ADMIN_PASSWORD}\033[0m"
}

# 执行主流程
main

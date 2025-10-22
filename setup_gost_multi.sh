#!/bin/bash
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 默认配置
SERVICE_COUNT=4
START_PORT=58002
SS_PASSWORD="mypassword123"
SOCKS5_SERVER=""
SOCKS5_USERNAME=""
SOCKS5_PASSWORD=""

# 显示使用说明
show_usage() {
    echo -e "${GREEN}使用方法:${NC}"
    echo "  $0 [选项]"
    echo ""
    echo -e "${GREEN}选项:${NC}"
    echo "  -c, --count    服务数量 (默认: $SERVICE_COUNT)"
    echo "  -p, --port     起始端口 (默认: $START_PORT)"
    echo "  -s, --socks5   SOCKS5服务器地址 (默认: $SOCKS5_SERVER)"
    echo "  -u, --user     SOCKS5用户名 (默认: $SOCKS5_USERNAME)"
    echo "  -w, --pass     SOCKS5密码 (默认: $SOCKS5_PASSWORD)"
    echo "  -k, --key      SS密码 (默认: $SS_PASSWORD)"
    echo "  -h, --help     显示此帮助信息"
    echo ""
    echo -e "${GREEN}示例:${NC}"
    echo "  $0 -c 8 -p 59000 -k newpassword123"
    echo "  $0 --count 4 --port 58002 --socks5 192.168.1.100"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--count)
            SERVICE_COUNT="$2"
            shift 2
            ;;
        -p|--port)
            START_PORT="$2"
            shift 2
            ;;
        -s|--socks5)
            SOCKS5_SERVER="$2"
            shift 2
            ;;
        -u|--user)
            SOCKS5_USERNAME="$2"
            shift 2
            ;;
        -w|--pass)
            SOCKS5_PASSWORD="$2"
            shift 2
            ;;
        -k|--key)
            SS_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "未知参数: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 验证输入
validate_input() {
    if ! [[ "$SERVICE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        error "服务数量必须是正整数"
        exit 1
    fi
    
    if ! [[ "$START_PORT" =~ ^[1-9][0-9]*$ ]] || [ "$START_PORT" -lt 1024 ] || [ "$START_PORT" -gt 65535 ]; then
        error "起始端口必须是 1024-65535 之间的数字"
        exit 1
    fi
    
    if [ -z "$SS_PASSWORD" ]; then
        error "SS密码不能为空"
        exit 1
    fi
    
    if [ -z "$SOCKS5_SERVER" ]; then
        error "SOCKS5服务器地址不能为空"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    if ! command -v /usr/local/bin/gost-go &> /dev/null; then
        error "未找到 gost-go，请先安装"
        exit 1
    fi
    
    if ! command -v systemctl &> /dev/null; then
        error "需要 systemd 支持"
        exit 1
    fi
}

# 显示配置信息
show_config() {
    info "=== 配置信息 ==="
    echo "服务数量: $SERVICE_COUNT"
    echo "起始端口: $START_PORT"
    echo "SS密码: $SS_PASSWORD"
    echo "SOCKS5服务器: $SOCKS5_SERVER"
    echo "SOCKS5用户名: $SOCKS5_USERNAME"
    echo "SOCKS5密码: $SOCKS5_PASSWORD"
    echo ""
    
    info "端口分配:"
    for ((i=0; i<SERVICE_COUNT; i++)); do
        port=$((START_PORT + i))
        socks5_port=$((10002 + i))
        echo "  端口 $port -> SOCKS5 ${SOCKS5_SERVER}:${socks5_port}"
    done
    echo ""
    
    read -p "确认以上配置？(y/n) [默认y]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        info "已取消安装"
        exit 0
    fi
}

# 创建服务文件
create_services() {
    info "创建服务文件..."
    
    for ((i=0; i<SERVICE_COUNT; i++)); do
        port=$((START_PORT + i))
        socks5_port=$((10002 + i))
        service_name="gost-${port}"
        
        # 创建服务文件
        sudo tee /etc/systemd/system/${service_name}.service > /dev/null << EOF
[Unit]
Description=Gost SS Proxy - Port ${port}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost-go -L "ss://aes-128-gcm:${SS_PASSWORD}@:${port}" -F "socks5://${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}@${SOCKS5_SERVER}:${socks5_port}"
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        
        info "创建服务: ${service_name}"
    done
}

# 配置防火墙
setup_firewall() {
    info "配置防火墙..."
    
    for ((i=0; i<SERVICE_COUNT; i++)); do
        port=$((START_PORT + i))
        
        if command -v ufw &> /dev/null; then
            sudo ufw allow ${port}/tcp
            info "UFW 开放端口: ${port}"
        elif command -v iptables &> /dev/null; then
            sudo iptables -A INPUT -p tcp --dport ${port} -j ACCEPT
            info "iptables 开放端口: ${port}"
        else
            warn "无法自动配置防火墙，请手动开放端口: ${port}"
        fi
    done
    
    if command -v ufw &> /dev/null; then
        sudo ufw reload
    elif command -v iptables-save &> /dev/null; then
        sudo iptables-save > /etc/sysconfig/iptables
    fi
}

# 启动服务
start_services() {
    info "启动服务..."
    
    sudo systemctl daemon-reload
    
    for ((i=0; i<SERVICE_COUNT; i++)); do
        port=$((START_PORT + i))
        service_name="gost-${port}"
        
        sudo systemctl stop ${service_name} 2>/dev/null || true
        sudo systemctl start ${service_name}
        sudo systemctl enable ${service_name}
        
        # 检查服务状态
        sleep 1
        if sudo systemctl is-active --quiet ${service_name}; then
            info "✅ 服务 ${service_name} 启动成功"
        else
            error "❌ 服务 ${service_name} 启动失败"
            sudo journalctl -u ${service_name} -n 5 --no-pager
        fi
    done
}

# 保存配置信息
save_config_info() {
    local config_file="/etc/gost/multi_service_config.txt"
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    sudo mkdir -p /etc/gost/
    sudo tee $config_file > /dev/null << EOF
=== Gost 多服务配置信息 ===
安装时间: $(date)
服务器IP: ${server_ip}
服务数量: ${SERVICE_COUNT}
起始端口: ${START_PORT}
SS密码: ${SS_PASSWORD}
SOCKS5服务器: ${SOCKS5_SERVER}
SOCKS5用户名: ${SOCKS5_USERNAME}
SOCKS5密码: ${SOCKS5_PASSWORD}

=== 服务列表 ===
EOF

    for ((i=0; i<SERVICE_COUNT; i++)); do
        port=$((START_PORT + i))
        socks5_port=$((10002 + i))
        sudo tee -a $config_file > /dev/null << EOF
服务 ${i}: 端口 ${port}
  SS连接: ss://aes-128-gcm:${SS_PASSWORD}@${server_ip}:${port}
  转发到: socks5://${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}@${SOCKS5_SERVER}:${socks5_port}

EOF
    done

    sudo tee -a $config_file > /dev/null << EOF
=== 管理命令 ===
启动所有: sudo systemctl start gost-${START_PORT} ... gost-$((START_PORT + SERVICE_COUNT - 1))
停止所有: sudo systemctl stop gost-${START_PORT} ... gost-$((START_PORT + SERVICE_COUNT - 1))
状态检查: sudo systemctl status gost-${START_PORT}
查看日志: sudo journalctl -u gost-${START_PORT} -f
EOF

    sudo chmod 600 $config_file
    info "配置信息已保存到: $config_file"
}

# 显示完成信息
show_completion() {
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    echo -e "\n${GREEN}========== 安装完成 ==========${NC}"
    echo -e "服务器IP: ${server_ip}"
    echo -e "服务数量: ${SERVICE_COUNT}"
    echo -e "端口范围: ${START_PORT} - $((START_PORT + SERVICE_COUNT - 1))"
    echo -e "SS密码: ${SS_PASSWORD}"
    echo -e "${GREEN}==============================${NC}"
    
    echo -e "\n${YELLOW}连接示例:${NC}"
    for ((i=0; i<3 && i<SERVICE_COUNT; i++)); do
        port=$((START_PORT + i))
        echo "ss://aes-128-gcm:${SS_PASSWORD}@${server_ip}:${port}"
    done
    if [ $SERVICE_COUNT -gt 3 ]; then
        echo "... 还有 $((SERVICE_COUNT - 3)) 个服务"
    fi
    
    echo -e "\n${YELLOW}管理命令:${NC}"
    echo "启动所有: systemctl start gost-${START_PORT} gost-$((START_PORT + 1)) ..."
    echo "停止所有: systemctl stop gost-${START_PORT} gost-$((START_PORT + 1)) ..."
    echo "查看状态: systemctl status gost-${START_PORT}"
    echo "查看日志: journalctl -u gost-${START_PORT} -f"
    echo -e "${GREEN}==============================${NC}"
}

# 主函数
main() {
    info "开始配置 Gost 多服务..."
    
    validate_input
    check_dependencies
    show_config
    create_services
    setup_firewall
    start_services
    save_config_info
    show_completion
    
    info "安装完成！"
}

# 运行主函数
main "$@"

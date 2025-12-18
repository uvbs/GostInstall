#!/bin/bash
set -e

# 配置变量（默认使用您的配置）
SS_PORT="34130"
SS_PASSWORD="lE9uL5weasfR3yR9"
SS_CIPHER="chacha20-ietf-poly1305"
OBFS_MODE="http"
OBFS_HOST="064cc026f0.iqiyi.com"
SERVICE_NAME="gost-ss-obfs"
GOST_VERSION="2.11.5"

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    info "安装必要的依赖..."
    if command -v dnf &> /dev/null; then
        dnf update -y
        dnf install -y wget gzip iptables iptables-services curl
    elif command -v yum &> /dev/null; then
        yum update -y
        yum install -y wget gzip iptables iptables-services curl
    elif command -v apt &> /dev/null; then
        apt update -y
        apt install -y wget gzip iptables curl
    else
        error "不支持的包管理器"
        exit 1
    fi
}

# 下载并安装Gost
install_gost() {
    info "下载 Gost v${GOST_VERSION}..."
    cd /tmp
    
    if ! wget -q https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-amd64-${GOST_VERSION}.gz; then
        error "下载Gost失败，请检查网络连接"
        exit 1
    fi
    
    info "解压并安装 Gost..."
    gzip -d gost-linux-amd64-${GOST_VERSION}.gz
    mv gost-linux-amd64-${GOST_VERSION} /usr/local/bin/gost
    chmod +x /usr/local/bin/gost
    
    if /usr/local/bin/gost -V &>/dev/null; then
        info "Gost 安装成功"
    else
        error "Gost 安装失败"
        exit 1
    fi
}

# 获取用户输入
get_user_input() {
    echo -e "\n${GREEN}=== 配置 Shadowsocks + Obfs 服务器 ===${NC}"
    
    # 1. 服务名称
    read -p "输入服务名称 [默认: ${SERVICE_NAME}]: " input_name
    SERVICE_NAME=${input_name:-$SERVICE_NAME}
    
    # 2. SS端口
    read -p "输入 SS 端口 [默认: ${SS_PORT}]: " input_port
    SS_PORT=${input_port:-$SS_PORT}
    
    # 3. SS密码
    read -p "输入 SS 密码 [默认: ${SS_PASSWORD}]: " input_pass
    SS_PASSWORD=${input_pass:-$SS_PASSWORD}
    
    # 4. 加密方式
    echo -e "\n可选加密方式:"
    echo "1) chacha20-ietf-poly1305 (推荐)"
    echo "2) aes-256-gcm"
    echo "3) aes-192-gcm"
    echo "4) aes-128-gcm"
    read -p "选择加密方式 [1-4, 默认1]: " cipher_choice
    
    case $cipher_choice in
        2) SS_CIPHER="aes-256-gcm" ;;
        3) SS_CIPHER="aes-192-gcm" ;;
        4) SS_CIPHER="aes-128-gcm" ;;
        *) SS_CIPHER="chacha20-ietf-poly1305" ;;
    esac
    
    # 5. 混淆模式
    echo -e "\n可选混淆模式:"
    echo "1) http (HTTP流量伪装)"
    echo "2) tls (TLS流量伪装)"
    echo "3) none (无混淆)"
    read -p "选择混淆模式 [1-3, 默认1]: " obfs_choice
    
    case $obfs_choice in
        2) 
            OBFS_MODE="tls"
            # 为tls模式提供默认host
            OBFS_HOST="cloudflare.com"
            ;;
        3) 
            OBFS_MODE="none"
            OBFS_HOST=""
            ;;
        *) 
            OBFS_MODE="http"
            OBFS_HOST="064cc026f0.iqiyi.com"
            ;;
    esac
    
    # 6. 混淆域名 (如果选择了混淆模式)
    if [[ "$OBFS_MODE" != "none" ]]; then
        read -p "输入混淆域名 [默认: ${OBFS_HOST}]: " input_host
        OBFS_HOST=${input_host:-$OBFS_HOST}
    fi
    
    # 显示配置确认
    echo -e "\n${GREEN}=== 配置确认 ===${NC}"
    echo "服务名称: $SERVICE_NAME"
    echo "SS 端口: $SS_PORT"
    echo "SS 密码: $SS_PASSWORD"
    echo "加密方式: $SS_CIPHER"
    echo "混淆模式: $OBFS_MODE"
    if [[ "$OBFS_MODE" != "none" ]]; then
        echo "混淆域名: $OBFS_HOST"
    fi
    
    read -p "确认以上配置是否正确？(y/n) [默认y]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        info "请重新运行脚本进行配置"
        exit 0
    fi
}

# 创建Systemd服务
create_service() {
    info "创建 Systemd 服务..."
    
    # 构建Gost命令
    local gost_cmd="/usr/local/bin/gost -L=ss://${SS_CIPHER}:${SS_PASSWORD}@:${SS_PORT}"
    
    # 添加混淆参数（如果启用）
    if [[ "$OBFS_MODE" != "none" ]]; then
        gost_cmd="${gost_cmd}?obfs=${OBFS_MODE}&obfs-host=${OBFS_HOST}"
    fi
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Gost Shadowsocks Server with Obfs (${SERVICE_NAME})
After=network.target

[Service]
Type=simple
User=root
ExecStart=${gost_cmd}
Restart=always
RestartSec=10
LimitNOFILE=65535

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log /run /tmp

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    info "Systemd 服务已创建: ${SERVICE_NAME}.service"
}

# 配置防火墙
setup_firewall() {
    info "配置防火墙..."
    
    # 检查端口是否被占用
    if netstat -tln | grep ":${SS_PORT} " > /dev/null; then
        warn "端口 ${SS_PORT} 已被占用，请检查"
        lsof -i :${SS_PORT} || true
    fi
    
    if command -v ufw &> /dev/null; then
        ufw allow ${SS_PORT}/tcp
        ufw allow ${SS_PORT}/udp
        ufw reload
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${SS_PORT}/tcp
        firewall-cmd --permanent --add-port=${SS_PORT}/udp
        firewall-cmd --reload
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport ${SS_PORT} -j ACCEPT
        iptables -A INPUT -p udp --dport ${SS_PORT} -j ACCEPT
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/sysconfig/iptables
        fi
    else
        warn "无法配置防火墙，请手动开放端口: ${SS_PORT}"
    fi
    
    info "防火墙已配置，开放端口: ${SS_PORT}"
}

# 启动服务
start_service() {
    info "启动 ${SERVICE_NAME} 服务..."
    
    # 先测试命令是否正确
    if timeout 5s /usr/local/bin/gost -V &>/dev/null; then
        info "Gost 命令测试成功"
    else
        error "Gost 命令测试失败"
        exit 1
    fi
    
    systemctl start ${SERVICE_NAME}
    systemctl enable ${SERVICE_NAME}
    sleep 2
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        info "${SERVICE_NAME} 服务启动成功"
    else
        error "${SERVICE_NAME} 服务启动失败"
        journalctl -u ${SERVICE_NAME} -n 20 --no-pager
        exit 1
    fi
}

# 保存配置信息
save_config_to_file() {
    local config_file="/etc/${SERVICE_NAME}/proxy_config.txt"
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    mkdir -p /etc/${SERVICE_NAME}/
    cat > "$config_file" << EOF
=== Gost Shadowsocks + Obfs 服务器配置信息 ===
安装时间: $(date)
服务名称: ${SERVICE_NAME}
服务器IP: ${server_ip}
SS 端口: ${SS_PORT}
SS 密码: ${SS_PASSWORD}
加密方式: ${SS_CIPHER}
混淆模式: ${OBFS_MODE}
混淆域名: ${OBFS_HOST:-无}

=== 客户端连接信息 ===
服务器: ${server_ip}
端口: ${SS_PORT}
密码: ${SS_PASSWORD}
加密: ${SS_CIPHER}

=== Clash 客户端配置 ===
proxies:
  - name: "${SERVICE_NAME}"
    type: ss
    server: ${server_ip}
    port: ${SS_PORT}
    cipher: ${SS_CIPHER}
    password: ${SS_PASSWORD}
EOF

    if [[ "$OBFS_MODE" != "none" ]]; then
        cat >> "$config_file" << EOF
    plugin: obfs
    plugin-opts:
      mode: ${OBFS_MODE}
      host: ${OBFS_HOST}
EOF
    fi
    
    # 生成SS URL
    local encoded_auth=$(echo -n "${SS_CIPHER}:${SS_PASSWORD}" | base64 | tr -d '\n')
    local ss_url="ss://${encoded_auth}@${server_ip}:${SS_PORT}"
    
    if [[ "$OBFS_MODE" != "none" ]]; then
        ss_url="${ss_url}/?plugin=obfs-local%3Bobfs%3D${OBFS_MODE}%3Bobfs-host%3D${OBFS_HOST}"
    fi
    ss_url="${ss_url}#${SERVICE_NAME}"
    
    cat >> "$config_file" << EOF

=== 连接URL ===
${ss_url}

=== 管理命令 ===
启动: systemctl start ${SERVICE_NAME}
停止: systemctl stop ${SERVICE_NAME}
状态: systemctl status ${SERVICE_NAME}
重启: systemctl restart ${SERVICE_NAME}
日志: journalctl -u ${SERVICE_NAME} -f

=== 服务状态检查 ===
端口监听: netstat -tlnp | grep ${SS_PORT}
进程状态: ps aux | grep gost | grep ${SS_PORT}
EOF
    
    chmod 600 "$config_file"
    info "配置信息已保存到: $config_file"
}

# 显示配置信息
show_info() {
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    echo -e "\n${GREEN}========== Shadowsocks + Obfs 服务器配置完成 ==========${NC}"
    echo -e "服务名称:   ${SERVICE_NAME}"
    echo -e "服务器IP:   ${server_ip}"
    echo -e "SS 端口:    ${SS_PORT}"
    echo -e "SS 密码:    ${SS_PASSWORD}"
    echo -e "加密方式:   ${SS_CIPHER}"
    echo -e "混淆模式:   ${OBFS_MODE}"
    if [[ "$OBFS_MODE" != "none" ]]; then
        echo -e "混淆域名:   ${OBFS_HOST}"
    fi
    echo -e "${GREEN}========================================================${NC}"
    
    # 生成SS URL
    local encoded_auth=$(echo -n "${SS_CIPHER}:${SS_PASSWORD}" | base64 | tr -d '\n')
    local ss_url="ss://${encoded_auth}@${server_ip}:${SS_PORT}"
    
    if [[ "$OBFS_MODE" != "none" ]]; then
        ss_url="${ss_url}/?plugin=obfs-local%3Bobfs%3D${OBFS_MODE}%3Bobfs-host%3D${OBFS_HOST}"
    fi
    ss_url="${ss_url}#${SERVICE_NAME}"
    
    echo -e "\n${YELLOW}=== 连接URL（可直接导入客户端）===${NC}"
    echo -e "${ss_url}"
    echo -e "${GREEN}========================================================${NC}"
    
    echo -e "\n${YELLOW}=== Clash 配置 ===${NC}"
    echo -e "proxies:"
    echo -e "  - name: \"${SERVICE_NAME}\""
    echo -e "    type: ss"
    echo -e "    server: ${server_ip}"
    echo -e "    port: ${SS_PORT}"
    echo -e "    cipher: ${SS_CIPHER}"
    echo -e "    password: ${SS_PASSWORD}"
    if [[ "$OBFS_MODE" != "none" ]]; then
        echo -e "    plugin: obfs"
        echo -e "    plugin-opts:"
        echo -e "      mode: ${OBFS_MODE}"
        echo -e "      host: ${OBFS_HOST}"
    fi
    echo -e "${GREEN}========================================================${NC}"
    
    echo -e "\n${YELLOW}=== 二维码生成 ===${NC}"
    echo -e "安装二维码工具: apt-get install qrencode"
    echo -e "生成二维码: qrencode -t ANSIUTF8 '${ss_url}'"
    echo -e "在线生成: https://cli.im/api/qrcode/code?text=$(echo -n ${ss_url} | sed 's/#/%23/g')"
    echo -e "${GREEN}========================================================${NC}"
    
    echo -e "\n${RED}重要：请立即保存以上连接信息！${NC}"
    echo -e "${YELLOW}配置信息已保存到: /etc/${SERVICE_NAME}/proxy_config.txt${NC}"
    echo -e "${GREEN}========================================================${NC}"
}

# 显示使用帮助
show_usage() {
    echo -e "${GREEN}=== Gost Shadowsocks + Obfs 服务器安装脚本 ===${NC}"
    echo -e "用法: $0 [选项]"
    echo -e "选项:"
    echo -e "  -h, --help     显示此帮助信息"
    echo -e "  -i, --install  快速安装（使用默认配置）"
    echo -e "  -c, --config   交互式配置安装"
    echo -e ""
    echo -e "${YELLOW}默认配置:${NC}"
    echo -e "  端口: 14131"
    echo -e "  密码: lE9uL5fR3yR9"
    echo -e "  加密: chacha20-ietf-poly1305"
    echo -e "  混淆: http"
    echo -e "  域名: 064cc026f0.iqiyi.com"
}

# 快速安装（使用默认配置）
quick_install() {
    info "开始快速安装（使用默认配置）..."
    check_root
    install_dependencies
    install_gost
    create_service
    setup_firewall
    start_service
    save_config_to_file
    show_info
}

# 主执行函数
main() {
    # 检查命令行参数
    if [[ $# -eq 0 ]]; then
        # 无参数，显示帮助
        show_usage
        exit 0
    fi
    
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -i|--install)
            quick_install
            ;;
        -c|--config)
            info "开始交互式配置安装..."
            check_root
            get_user_input
            install_dependencies
            install_gost
            create_service
            setup_firewall
            start_service
            save_config_to_file
            show_info
            ;;
        *)
            error "无效的参数: $1"
            show_usage
            exit 1
            ;;
    esac
    
    info "安装完成！"
}

# 执行主函数
main "$@"
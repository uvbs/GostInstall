#!/bin/bash
set -e

# 配置变量
SS_PORT="8388"
SS_PASSWORD=""
SOCKS5_SERVER=""
SOCKS5_USERNAME=""
SOCKS5_PASSWORD=""
GOST_VERSION="2.11.5"

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 生成随机密码（10个字符）
generate_random_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 10
}

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
    echo -e "\n${GREEN}=== 配置 SS 服务器 ===${NC}"
    read -p "输入 SS 端口 [默认: 8388]: " input_port
    SS_PORT=${input_port:-$SS_PORT}
    
    # 生成随机密码（10个字符）
    SS_PASSWORD=$(generate_random_password)
    
    echo -e "\n${GREEN}=== 配置二级 SOCKS5 代理 ===${NC}"
    while [[ -z "$SOCKS5_SERVER" ]]; do
        read -p "输入 SOCKS5 服务器IP地址: " socks_ip
        read -p "输入 SOCKS5 服务器端口: " socks_port
        if [[ -n "$socks_ip" && -n "$socks_port" ]]; then
            SOCKS5_SERVER="${socks_ip}:${socks_port}"
        else
            warn "IP和端口不能为空，请重新输入"
        fi
    done
    
    read -p "SOCKS5 需要认证吗？(y/n) [默认n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "输入 SOCKS5 用户名: " socks_user
        SOCKS5_USERNAME=${socks_user}
        read -p "输入 SOCKS5 密码: " socks_pass
        SOCKS5_PASSWORD=${socks_pass}
    fi
    
    # 显示配置确认
    echo -e "\n${GREEN}=== 配置确认 ===${NC}"
    echo "SS 端口: $SS_PORT"
    echo "SS 密码: $SS_PASSWORD"
    echo "加密方式: aes-128-gcm"
    echo "SOCKS5 服务器: $SOCKS5_SERVER"
    if [[ -n "$SOCKS5_USERNAME" ]]; then
        echo "SOCKS5 用户名: $SOCKS5_USERNAME"
        echo "SOCKS5 密码: $SOCKS5_PASSWORD"
    else
        echo "SOCKS5 认证: 无"
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
    local gost_cmd="/usr/local/bin/gost -L=ss://aes-128-gcm:${SS_PASSWORD}@:${SS_PORT}"
    
    if [[ -n "$SOCKS5_USERNAME" && -n "$SOCKS5_PASSWORD" ]]; then
        gost_cmd="${gost_cmd} -F=socks5://${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}@${SOCKS5_SERVER}"
    else
        gost_cmd="${gost_cmd} -F=socks5://${SOCKS5_SERVER}"
    fi
    
    cat > /etc/systemd/system/gost.service << EOF
[Unit]
Description=Gost SS to SOCKS5 Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=${gost_cmd}
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    info "Systemd 服务已创建"
}

# 配置防火墙
setup_firewall() {
    info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw allow ${SS_PORT}/tcp
        ufw allow ${SS_PORT}/udp
        ufw reload
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
    info "启动 Gost 服务..."
    
    # 先测试命令是否正确
    if timeout 5s /usr/local/bin/gost -V &>/dev/null; then
        info "Gost 命令测试成功"
    else
        error "Gost 命令测试失败"
        exit 1
    fi
    
    systemctl start gost
    systemctl enable gost
    sleep 2
    
    if systemctl is-active --quiet gost; then
        info "Gost 服务启动成功"
    else
        error "Gost 服务启动失败"
        journalctl -u gost -n 20 --no-pager
        exit 1
    fi
}

# 保存配置信息
save_config_to_file() {
    local config_file="/etc/gost/proxy_config.txt"
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    mkdir -p /etc/gost/
    cat > "$config_file" << EOF
=== Gost 代理配置信息 ===
安装时间: $(date)
SS 服务器: ${server_ip}
SS 端口: ${SS_PORT}
SS 密码: ${SS_PASSWORD}
加密方式: aes-128-gcm
二级代理: ${SOCKS5_SERVER}
SOCKS5 认证: $(if [[ -n "$SOCKS5_USERNAME" ]]; then echo "${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}"; else echo "无"; fi)

=== 客户端连接信息 ===
服务器: ${server_ip}
端口: ${SS_PORT}
密码: ${SS_PASSWORD}
加密: aes-128-gcm

=== 管理命令 ===
启动: systemctl start gost
停止: systemctl stop gost
状态: systemctl status gost
日志: journalctl -u gost -f
EOF
    
    chmod 600 "$config_file"
    info "配置信息已保存到: $config_file"
}

# 显示配置信息
show_info() {
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    echo -e "\n${GREEN}========== 配置完成 ==========${NC}"
    echo -e "SS 服务器:    ${server_ip}"
    echo -e "SS 端口:      ${SS_PORT}"
    echo -e "SS 密码:      ${SS_PASSWORD}"
    echo -e "加密方式:     aes-128-gcm"
    echo -e "二级代理:     ${SOCKS5_SERVER}"
    if [[ -n "$SOCKS5_USERNAME" ]]; then
        echo -e "SOCKS5 认证:  ${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}"
    else
        echo -e "SOCKS5 认证:  无"
    fi
    echo -e "${GREEN}===============================${NC}"
    echo -e "\n${YELLOW}=== 客户端连接信息 ===${NC}"
    echo -e "服务器: ${server_ip}"
    echo -e "端口: ${SS_PORT}"
    echo -e "密码: ${SS_PASSWORD}"
    echo -e "加密: aes-128-gcm"
    echo -e "${GREEN}===============================${NC}"
    echo -e "\n${RED}重要：请立即保存以上连接信息！${NC}"
    echo -e "${YELLOW}配置信息已保存到: /etc/gost/proxy_config.txt${NC}"
    echo -e "${GREEN}===============================${NC}"
}

# 主执行函数
main() {
    info "开始安装 Gost 二级代理..."
    check_root
    get_user_input
    install_dependencies
    install_gost
    create_service
    setup_firewall
    start_service
    save_config_to_file
    show_info
    info "安装完成！"
}

main "$@"

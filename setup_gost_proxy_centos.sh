#!/bin/bash

# Gost 二级代理一键安装脚本（CentOS 适配版）
# 功能：自动安装 Gost，配置 SS -> SOCKS5 代理链，并设置系统服务

set -e  # 遇到错误立即退出

# 配置变量
SS_PORT="8388"
SS_USERNAME=""
SS_PASSWORD=""
SOCKS5_SERVER=""
SOCKS5_USERNAME=""
SOCKS5_PASSWORD=""
GOST_VERSION="2.11.5"

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 生成随机字符串
generate_random_string() {
    local length=${1:-12}
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# 生成随机密码（包含特殊字符）
generate_random_password() {
    local length=${1:-16}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    info "安装必要的依赖..."
    dnf update -y
    dnf install -y wget gunzip iptables iptables-services
}

# 下载并安装 Gost
install_gost() {
    info "下载 Gost v${GOST_VERSION}..."
    cd /tmp
    wget -q https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-amd64-${GOST_VERSION}.gz
    
    info "解压并安装 Gost..."
    gunzip gost-linux-amd64-${GOST_VERSION}.gz
    mv gost-linux-amd64-${GOST_VERSION} /usr/local/bin/gost
    chmod +x /usr/local/bin/gost
    
    # 验证安装
    if gost -version &>/dev/null; then
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
    
    # 生成随机用户名和密码
    SS_USERNAME="user_$(generate_random_string 8)"
    SS_PASSWORD="$(generate_random_password 16)"
    
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
    echo "SS 用户名: $SS_USERNAME" 
    echo "SS 密码: $SS_PASSWORD"
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

# 创建配置文件
create_config() {
    info "创建 Gost 配置文件..."
    
    mkdir -p /etc/gost/
    
    cat > /etc/gost/config.yaml << EOF
services:
- name: service-0
  addr: :${SS_PORT}
  handler:
    type: ss
    auth:
      username: ${SS_USERNAME}
      password: ${SS_PASSWORD}
  listener:
    type: ss
  forwarder:
    nodes:
      - target: ${SOCKS5_SERVER}
        dialer:
          type: socks5
EOF

    # 如果 SOCKS5 需要认证，添加认证信息
    if [[ -n "$SOCKS5_USERNAME" && -n "$SOCKS5_PASSWORD" ]]; then
        sed -i "/type: socks5/a\          auth:\n            username: ${SOCKS5_USERNAME}\n            password: ${SOCKS5_PASSWORD}" /etc/gost/config.yaml
    fi
    
    info "配置文件已创建: /etc/gost/config.yaml"
}

# 创建系统服务
create_service() {
    info "创建 Systemd 服务..."
    
    cat > /etc/systemd/system/gost.service << EOF
[Unit]
Description=GO Simple Tunnel (SS -> SOCKS5 Proxy Chain)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost -C /etc/gost/config.yaml
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    info "Systemd 服务已创建"
}

# 配置防火墙（CentOS 使用 iptables）
setup_firewall() {
    info "配置防火墙..."
    
    # 安装 iptables
    if ! command -v iptables &> /dev/null; then
        dnf install -y iptables iptables-services
    fi
    
    # 开放端口
    iptables -A INPUT -p tcp --dport ${SS_PORT} -j ACCEPT
    iptables -A INPUT -p udp --dport ${SS_PORT} -j ACCEPT
    
    # 尝试保存规则
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/sysconfig/iptables
        info "防火墙规则已保存"
    else
        warn "iptables-save 不可用，防火墙规则重启后可能丢失"
        warn "请手动安装 iptables-services: dnf install iptables-services"
    fi
    
    info "防火墙已配置，开放端口: ${SS_PORT}"
}

# 启动服务
start_service() {
    info "启动 Gost 服务..."
    
    systemctl start gost
    systemctl enable gost
    
    sleep 2  # 等待服务启动
    
    if systemctl is-active --quiet gost; then
        info "Gost 服务启动成功"
    else
        error "Gost 服务启动失败"
        journalctl -u gost -n 10 --no-pager
        exit 1
    fi
}

# 保存配置信息到文件
save_config_to_file() {
    local config_file="/etc/gost/proxy_config.txt"
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    cat > "$config_file" << EOF
=== Gost 代理配置信息 ===
安装时间: $(date)
SS 服务器: ${SERVER_IP}
SS 端口: ${SS_PORT}
SS 用户名: ${SS_USERNAME}
SS 密码: ${SS_PASSWORD}
加密方式: AEAD_AES_128_GCM
二级代理: ${SOCKS5_SERVER}
SOCKS5 认证: $(if [[ -n "$SOCKS5_USERNAME" ]]; then echo "${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}"; else echo "无"; fi)

=== 客户端连接信息 ===
服务器: ${SERVER_IP}
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
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    echo -e "\n${GREEN}========== 配置完成 ==========${NC}"
    echo -e "SS 服务器:    ${SERVER_IP}"
    echo -e "SS 端口:      ${SS_PORT}"
    echo -e "SS 用户名:    ${SS_USERNAME}"
    echo -e "SS 密码:      ${SS_PASSWORD}"
    echo -e "加密方式:     AEAD_AES_128_GCM"
    echo -e "二级代理:     ${SOCKS5_SERVER}"
    if [[ -n "$SOCKS5_USERNAME" ]]; then
        echo -e "SOCKS5 认证:  ${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}"
    else
        echo -e "SOCKS5 认证:  无"
    fi
    echo -e "${GREEN}===============================${NC}"
    echo -e "\n${YELLOW}=== 客户端连接信息 ===${NC}"
    echo -e "服务器: ${SERVER_IP}"
    echo -e "端口: ${SS_PORT}"
    echo -e "密码: ${SS_PASSWORD}"
    echo -e "加密: aes-128-gcm"
    echo -e "${GREEN}===============================${NC}"
    echo -e "\n${YELLOW}=== 管理命令 ===${NC}"
    echo -e "启动:   systemctl start gost"
    echo -e "停止:   systemctl stop gost"
    echo -e "状态:   systemctl status gost"
    echo -e "日志:   journalctl -u gost -f"
    echo -e "${GREEN}===============================${NC}"
    echo -e "\n${RED}重要：请立即保存以上连接信息！${NC}"
    echo -e "${YELLOW}配置信息已保存到: /etc/gost/proxy_config.txt${NC}"
    echo -e "${GREEN}===============================${NC}"
}

# 主执行函数
main() {
    info "开始安装 Gost 二级代理..."
    check_root
    
    # 获取用户输入
    get_user_input
    
    install_dependencies
    install_gost
    create_config
    create_service
    setup_firewall
    start_service
    save_config_to_file
    show_info
    
    info "安装完成！"
}

# 执行主函数
main "$@"

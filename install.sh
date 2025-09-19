#!/bin/bash

# Gost 二级代理一键安装脚本
# 功能：自动安装 Gost，配置 SS -> SOCKS5 代理链，并设置系统服务

set -e  # 遇到错误立即退出

# 配置变量（请根据实际情况修改）
SS_PORT="8388"
SS_USERNAME="your_ss_username"
SS_PASSWORD="your_strong_ss_password"
SOCKS5_SERVER="your.socks5.server.com:1080"
SOCKS5_USERNAME="your_socks5_username"
SOCKS5_PASSWORD="your_socks5_password"
GOST_VERSION="2.11.5"  # 可以修改为需要的版本

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
    apt-get update
    apt-get install -y wget gunzip ufw
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

# 配置防火墙
setup_firewall() {
    info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw allow ${SS_PORT}/tcp
        ufw allow ${SS_PORT}/udp
        ufw reload
        info "防火墙已配置，开放端口: ${SS_PORT}"
    else
        warn "未找到 ufw，请手动配置防火墙开放端口: ${SS_PORT}"
    fi
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

# 显示配置信息
show_info() {
    echo -e "\n${GREEN}========== 配置完成 ==========${NC}"
    echo -e "SS 服务器:    $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
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
    echo -e "\n使用命令管理服务:"
    echo -e "启动:   systemctl start gost"
    echo -e "停止:   systemctl stop gost"
    echo -e "状态:   systemctl status gost"
    echo -e "日志:   journalctl -u gost -f"
    echo -e "${GREEN}===============================${NC}"
}

# 主执行函数
main() {
    info "开始安装 Gost 二级代理..."
    check_root
    
    # 询问用户是否要修改默认配置
    read -p "是否使用默认配置？(y/n) [默认y]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "输入 SS 端口 [8388]: " custom_port
        SS_PORT=${custom_port:-$SS_PORT}
        
        read -p "输入 SS 用户名 [your_ss_username]: " custom_user
        SS_USERNAME=${custom_user:-$SS_USERNAME}
        
        read -p "输入 SS 密码: " custom_pass
        SS_PASSWORD=${custom_pass:-$SS_PASSWORD}
        
        read -p "输入 SOCKS5 服务器地址 (IP:端口): " custom_socks
        SOCKS5_SERVER=${custom_socks:-$SOCKS5_SERVER}
        
        read -p "SOCKS5 需要认证吗？(y/n) [n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "输入 SOCKS5 用户名: " socks_user
            SOCKS5_USERNAME=${socks_user}
            read -p "输入 SOCKS5 密码: " socks_pass
            SOCKS5_PASSWORD=${socks_pass}
        else
            SOCKS5_USERNAME=""
            SOCKS5_PASSWORD=""
        fi
    fi
    
    install_dependencies
    install_gost
    create_config
    create_service
    setup_firewall
    start_service
    show_info
    
    info "安装完成！"
}

# 执行主函数
main "$@"

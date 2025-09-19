#!/bin/bash
set -e

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
    info "下载 Gost..."
    cd /tmp
    GOST_VERSION="2.11.5"
    
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

# 获取用户输入并创建YAML配置
create_yaml_config() {
    info "创建 YAML 配置文件..."
    
    mkdir -p /etc/gost/
    
    # 开始创建YAML配置
    cat > /etc/gost/config.yaml << EOF
services:
EOF

    # 获取代理配置
    PROXY_CONFIGS=()
    proxy_count=1
    
    while true; do
        echo -e "\n${YELLOW}配置第 ${proxy_count} 个代理:${NC}"
        
        # SS配置
        read -p "输入 SS 端口 [默认: 8$(printf "%03d" ${proxy_count})]: " ss_port
        SS_PORT=${ss_port:-"8$(printf "%03d" ${proxy_count})"}
        SS_PASSWORD=$(generate_random_password)
        
        # SOCKS5配置
        echo -e "\n${YELLOW}对应的SOCKS5代理配置:${NC}"
        read -p "输入 SOCKS5 服务器IP地址: " socks_ip
        read -p "输入 SOCKS5 服务器端口: " socks_port
        SOCKS5_SERVER="${socks_ip}:${socks_port}"
        
        SOCKS5_USERNAME=""
        SOCKS5_PASSWORD=""
        read -p "SOCKS5 需要认证吗？(y/n) [默认n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "输入 SOCKS5 用户名: " socks_user
            SOCKS5_USERNAME=${socks_user}
            read -p "输入 SOCKS5 密码: " socks_pass
            SOCKS5_PASSWORD=${socks_pass}
        fi
        
        # 添加到YAML配置
        cat >> /etc/gost/config.yaml << EOF
- name: ss-to-socks5-${proxy_count}
  addr: :${SS_PORT}
  handler:
    type: ss
    auth:
      username: aes-128-gcm
      password: ${SS_PASSWORD}
  listener:
    type: ss
  forwarder:
    nodes:
    - addr: ${SOCKS5_SERVER}
      connector:
        type: socks5
      dialer:
        type: tcp
EOF

        # 添加认证信息（如果需要）
        if [[ -n "$SOCKS5_USERNAME" && -n "$SOCKS5_PASSWORD" ]]; then
            cat >> /etc/gost/config.yaml << EOF
        auth:
          username: ${SOCKS5_USERNAME}
          password: ${SOCKS5_PASSWORD}
EOF
        fi

        # 保存配置信息
        CONFIG=("$SS_PORT" "$SS_PASSWORD" "$SOCKS5_SERVER" "$SOCKS5_USERNAME" "$SOCKS5_PASSWORD")
        PROXY_CONFIGS+=("${CONFIG[@]}")
        
        # 显示当前配置
        echo -e "\n${GREEN}已添加代理 ${proxy_count}:${NC}"
        echo "SS端口: $SS_PORT, 密码: $SS_PASSWORD"
        echo "SOCKS5: $SOCKS5_SERVER"
        if [[ -n "$SOCKS5_USERNAME" ]]; then
            echo "SOCKS5认证: ${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}"
        fi
        
        read -p "是否继续添加更多代理？(y/n) [默认n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            break
        fi
        
        ((proxy_count++))
    done
    
    if [ ${#PROXY_CONFIGS[@]} -eq 0 ]; then
        error "至少需要配置一个代理"
        exit 1
    fi
    
    info "YAML 配置文件已创建: /etc/gost/config.yaml"
    
    # 显示配置文件内容
    echo -e "\n${YELLOW}配置文件内容:${NC}"
    cat /etc/gost/config.yaml
    echo
}

# 创建Systemd服务
create_service() {
    info "创建 Systemd 服务..."
    
    cat > /etc/systemd/system/gost.service << EOF
[Unit]
Description=Gost Multiple SS to SOCKS5 Proxies (YAML Config)
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
    
    # 从YAML配置中提取端口
    ports=$(grep "addr: :" /etc/gost/config.yaml | awk -F':' '{print $3}' | tr -d ' ')
    
    for port in $ports; do
        if command -v ufw &> /dev/null; then
            ufw allow ${port}/tcp
            ufw allow ${port}/udp
        elif command -v iptables &> /dev/null; then
            iptables -A INPUT -p tcp --dport ${port} -j ACCEPT
            iptables -A INPUT -p udp --dport ${port} -j ACCEPT
        fi
        info "开放端口: ${port}"
    done
    
    if command -v ufw &> /dev/null; then
        ufw reload
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/sysconfig/iptables
    fi
    
    info "防火墙配置完成"
}

# 启动服务
start_service() {
    info "启动 Gost 服务..."
    
    # 测试配置文件
    info "测试配置文件..."
    if /usr/local/bin/gost -C /etc/gost/config.yaml -L &>/dev/null; then
        info "配置文件测试成功"
    else
        error "配置文件有错误，请检查YAML格式"
        exit 1
    fi
    
    systemctl stop gost 2>/dev/null || true
    systemctl start gost
    systemctl enable gost
    sleep 3
    
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
    
    # 从YAML提取配置信息
    mkdir -p /etc/gost/
    
    cat > "$config_file" << EOF
=== Gost 多代理配置信息 (YAML) ===
安装时间: $(date)
服务器IP: ${server_ip}
配置文件: /etc/gost/config.yaml

EOF

    # 提取端口和密码信息
    grep -A5 -B5 "addr: :" /etc/gost/config.yaml | while read -r line; do
        if [[ $line == *"addr: :"* ]]; then
            port=$(echo "$line" | awk -F':' '{print $3}' | tr -d ' ')
            echo "=== 代理端口: ${port} ===" >> "$config_file"
        elif [[ $line == *"password:"* ]]; then
            password=$(echo "$line" | awk '{print $2}')
            echo "SS密码: ${password}" >> "$config_file"
            echo "连接信息: ss://aes-128-gcm:${password}@${server_ip}:${port}" >> "$config_file"
            echo "" >> "$config_file"
        fi
    done

    cat >> "$config_file" << EOF
=== 管理命令 ===
启动: systemctl start gost
停止: systemctl stop gost
状态: systemctl status gost
日志: journalctl -u gost -f
重载配置: systemctl restart gost
检查配置: gost -C /etc/gost/config.yaml -L
EOF
    
    chmod 600 "$config_file"
    info "配置信息已保存到: $config_file"
}

# 显示配置信息
show_info() {
    local server_ip=$(curl -s ifconfig.me || hostname -I | awk '{print $1}' | head -n1)
    
    echo -e "\n${GREEN}========== 配置完成 ==========${NC}"
    echo -e "服务器IP: ${server_ip}"
    echo -e "配置文件: /etc/gost/config.yaml"
    echo -e "${GREEN}===============================${NC}"
    
    # 显示端口信息
    echo -e "\n${YELLOW}已配置的代理端口:${NC}"
    grep "addr: :" /etc/gost/config.yaml | awk -F':' '{print "端口: " $3}'
    
    echo -e "\n${YELLOW}连接示例:${NC}"
    grep -A1 "password:" /etc/gost/config.yaml | while read -r line; do
        if [[ $line == *"password:"* ]]; then
            password=$(echo "$line" | awk '{print $2}')
            port=$(grep -B4 "password: ${password}" /etc/gost/config.yaml | grep "addr: :" | awk -F':' '{print $3}' | tr -d ' ')
            echo "ss://aes-128-gcm:${password}@${server_ip}:${port}"
        fi
    done
    
    echo -e "\n${GREEN}===============================${NC}"
    echo -e "\n${RED}重要：请立即保存以上连接信息！${NC}"
    echo -e "${YELLOW}配置信息已保存到: /etc/gost/proxy_config.txt${NC}"
    echo -e "${GREEN}===============================${NC}"
}

# 主执行函数
main() {
    info "开始安装 Gost 多代理 (YAML配置)..."
    check_root
    install_dependencies
    install_gost
    create_yaml_config
    create_service
    setup_firewall
    start_service
    save_config_to_file
    show_info
    info "安装完成！"
}

main "$@"

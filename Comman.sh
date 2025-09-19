# 最终推荐的使用方式
sudo systemctl stop gost

# 设置你的SOCKS5代理信息
SOCKS5_IP="你的SOCKS5服务器IP"
SOCKS5_PORT="1080"
SOCKS5_USER="你的用户名"  # 如果没有认证就留空
SOCKS5_PASS="你的密码"    # 如果没有认证就留空

# 生成随机SS凭据
SS_USER="user_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c8)"
SS_PASS="$(head /dev/urandom | tr -dc A-Za-z0-9!@#$%^&* | head -c16)"
SS_PORT="8388"

# 创建服务文件
sudo tee /etc/systemd/system/gost.service > /dev/null << EOF
[Unit]
Description=GO Simple Tunnel (SS -> SOCKS5 Proxy Chain)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost -L=ss://${SS_USER}:${SS_PASS}@:${SS_PORT} -F=socks5://${SOCKS5_USER}:${SOCKS5_PASS}@${SOCKS5_IP}:${SOCKS5_PORT}
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 重新加载并启动
sudo systemctl daemon-reload
sudo systemctl start gost
sudo systemctl status gost

# 显示连接信息
echo "SS服务器: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
echo "SS端口: $SS_PORT"
echo "SS用户名: $SS_USER"
echo "SS密码: $SS_PASS"
echo "二级代理: ${SOCKS5_IP}:${SOCKS5_PORT}"

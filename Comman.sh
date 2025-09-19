sudo systemctl stop gost
SS_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 10)
SS_PORT="28318"

# 设置你的SOCKS5代理信息
SOCKS5_IP="1.1.33.36"
SOCKS5_PORT="10001"
SOCKS5_USER="xx"  # 如果没有认证就留空
SOCKS5_PASS="xx"    # 如果没有认证就留空
# 创建Systemd服务
sudo tee /etc/systemd/system/gost.service > /dev/null << EOF
[Unit]
Description=Gost SS to SOCKS5 Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost -L=ss://aes-128-gcm:${SS_PASSWORD}@:${SS_PORT} -F=socks5://${SOCKS5_USER}:${SOCKS5_PASS}@${SOCKS5_IP}:${SOCKS5_PORT}
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 重载并启动服务
sudo systemctl daemon-reload
sudo systemctl enable gost
sudo systemctl start gost

# 显示配置信息
echo "=========================================="
echo "SS代理配置信息："
echo "服务器: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
echo "端口: $SS_PORT"
echo "加密: aes-128-gcm"
echo "密码: $SS_PASSWORD"
echo "二级代理: ${SOCKS5_IP}:${SOCKS5_PORT}"
echo "=========================================="

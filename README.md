
使用方法

centos 下 单个直接安装

sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/uvbs/GostInstall/refs/heads/main/setup_gost_proxy_centos.sh)"

sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/uvbs/GostInstall/refs/heads/main/Comman.sh)"


因为到现在都没明白 gost 的配置文件，开始用多进程吧
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/uvbs/GostInstall/refs/heads/main/setup_gost_multi.sh)"
cat /etc/systemd/system/gost.service

=== 管理命令 ===
启动: systemctl start gost
停止: systemctl stop gost
状态: systemctl status gost
日志: journalctl -u gost -f
sudo systemctl daemon-reload

# 启动所有服务
for port in 58002 58003 58004 58005; do
    sudo systemctl start gost-$port
    sudo systemctl enable gost-$port
done

# 检查所有服务状态
for port in {58002..58021}; do
    echo "=== 端口 $port 状态 ==="
    sudo systemctl status gost-$port --no-pager -l
    echo
done

gost_3.2.6-nightly.20251011_linux_amd64v3.tar.gz


检查问题

保存脚本：

bash
nano setup_gost_proxy.sh
将上面的脚本内容粘贴进去，按 Ctrl+X，然后 Y 保存。

赋予执行权限：

bash
chmod +x setup_gost_proxy.sh
修改配置（可选）：
在脚本开头的配置变量部分修改你的设置，或者运行时会提示你输入。

执行脚本：

bash
sudo ./setup_gost_proxy.sh
脚本功能特点
✅ 自动检测 root 权限

✅ 交互式配置（可选）

✅ 自动安装依赖

✅ 自动下载安装指定版本的 Gost

✅ 生成正确的配置文件

✅ 创建 Systemd 服务

✅ 自动配置防火墙（如果使用 ufw）

✅ 启动服务并验证

✅ 显示完整的连接信息

✅ 彩色输出，易于阅读

✅ 错误处理和日志查看

注意事项
运行前请确保你已经准备好了第二级 SOCKS5 代理的详细信息。

脚本会自动开放防火墙端口，如果你的服务器使用其他防火墙工具（如 iptables、firewalld），可能需要手动配置。

如果 SOCKS5 代理不需要认证，在交互时选择 'n' 即可。

运行完成后，你的代理服务就已经搭建好了，可以直接使用客户端连接了！

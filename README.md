
使用方法

centos 下 直接安装

sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/uvbs/GostInstall/refs/heads/main/setup_gost_proxy_centos.sh)"

如果出现问题 


sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/uvbs/GostInstall/refs/heads/main/Comman.sh)"
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

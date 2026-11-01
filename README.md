# Hysteria 2 无域名端口跳跃一键脚本

无需域名，使用自签名证书，Hysteria 2 服务端监听 `443`，并通过 iptables 把 UDP `20000-30000` 端口范围转发到 `443`。

脚本会自动生成认证密码、Salamander 混淆密码和 v2rayN 可用的 Hysteria 2 分享链接。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/rainbowgag/hysteria2/main/hysteria2-porthop-setup.sh | sudo bash
```

如果已经是 root 用户，也可以直接执行：

```bash
curl -fsSL https://raw.githubusercontent.com/rainbowgag/hysteria2/main/hysteria2-porthop-setup.sh | bash
```

## 可选环境变量

```bash
HY2_IP=1.2.3.4 \
HY2_PASSWORD=你的密码 \
HY2_OBFS_PASSWORD=你的混淆密码 \
HY2_RANGE=20000-30000 \
HY2_LISTEN=443 \
bash hysteria2-porthop-setup.sh
```

- `HY2_IP`：服务器公网 IP，留空会自动检测。
- `HY2_PASSWORD`：Hysteria 认证密码，留空自动生成。
- `HY2_OBFS_PASSWORD`：Salamander 混淆密码，留空自动生成。
- `HY2_NAME`：节点名称，默认 `Hysteria2-PortHop`。
- `HY2_RANGE`：UDP 端口跳跃范围，默认 `20000-30000`。
- `HY2_LISTEN`：Hysteria 服务端监听端口，默认 `443`。

## v2rayN 链接说明

脚本输出的链接使用数字端口 `443` 作为节点端口，并通过 `mport` 参数携带端口跳跃范围。v2rayN 无法解析类似 `hysteria2://...:20000-30000` 的链接，因此必须使用这种格式。

安装完成后，脚本会同时输出 v2rayN 节点链接和 Clash 节点格式，并安装管理命令 `hy01`。

## 再次查看链接或删除节点

在服务器上运行：

```bash
hy01
```

然后按提示选择：

```text
1. 显示节点链接
2. 删除
```

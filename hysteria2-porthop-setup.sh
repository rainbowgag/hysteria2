#!/usr/bin/env bash
set -euo pipefail

# Hysteria 2 无域名 + UDP 端口跳跃(20000-30000 -> 443) 一键安装
# 用法:
#   bash hysteria2-porthop-setup.sh
# 可选环境变量:
#   HY2_IP         服务器公网 IP(留空则自动检测)
#   HY2_PASSWORD   Hysteria 认证密码(留空则自动生成)
#   HY2_OBFS_PASSWORD Salamander 混淆密码(留空则自动生成)
#   HY2_NAME       节点名称(默认 Hysteria2-PortHop)
#   HY2_RANGE      跳跃端口范围(默认 20000-30000)
#   HY2_LISTEN     服务端监听端口(默认 443)

if [[ ${EUID} -ne 0 ]]; then
  echo "请用 root 运行: sudo bash $0" >&2
  exit 1
fi

HY2_RANGE="${HY2_RANGE:-20000-30000}"
HY2_LISTEN="${HY2_LISTEN:-443}"
HY2_PASSWORD="${HY2_PASSWORD:-}"
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"
HY2_NAME="${HY2_NAME:-Hysteria2-PortHop}"
HY2_IPT_RANGE="${HY2_RANGE//-/:}"

if [[ -z "${HY2_PASSWORD}" ]]; then
  HY2_PASSWORD="$(openssl rand -hex 16)"
fi
if [[ -z "${HY2_OBFS_PASSWORD}" ]]; then
  HY2_OBFS_PASSWORD="$(openssl rand -hex 12)"
fi

echo "==> 更新软件源并安装依赖(curl/openssl/iptables)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget ca-certificates openssl iptables iptables-persistent iproute2

echo "==> 通过官方脚本安装 Hysteria 2"
if ! command -v hysteria >/dev/null 2>&1 || [[ ! -f /etc/systemd/system/hysteria-server.service ]]; then
  bash <(curl -fsSL https://get.hy2.sh/)
else
  echo "hysteria 已安装: $(command -v hysteria)"
fi

if [[ -z "${HY2_IP:-}" ]]; then
  HY2_IP="$(curl -4 -fsSL --max-time 15 https://api.ipify.org || true)"
  if [[ -z "${HY2_IP}" ]]; then
    HY2_IP="$(curl -4 -fsSL --max-time 15 https://ifconfig.me || true)"
  fi
fi

if [[ -z "${HY2_IP}" ]]; then
  echo "无法自动获取公网 IP，请用 HY2_IP=1.2.3.4 重新运行" >&2
  exit 1
fi

echo "==> 生成自签名证书(CN/IP=${HY2_IP})"
mkdir -p /etc/hysteria
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -days 3650 \
  -subj "/CN=${HY2_IP}" \
  -addext "subjectAltName=IP:${HY2_IP}"
chmod 600 /etc/hysteria/server.key
chmod 644 /etc/hysteria/server.crt

PIN_SHA256="$(openssl x509 -in /etc/hysteria/server.crt -noout -fingerprint -sha256 | awk -F= '/Fingerprint/{gsub(/:/, "", $2); print $2}')"

echo "==> 写入 /etc/hysteria/config.yaml"
cat >/etc/hysteria/config.yaml <<EOF
listen: :${HY2_LISTEN}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: "${HY2_PASSWORD}"

obfs:
  type: salamander
  salamander:
    password: "${HY2_OBFS_PASSWORD}"
EOF

if id hysteria >/dev/null 2>&1; then
  chown -R hysteria:hysteria /etc/hysteria
fi

echo "==> 配置 UDP 端口跳跃 NAT 规则"
# 先删掉同名旧规则(存在才删)，避免重复添加
iptables -t nat -C PREROUTING -p udp --dport "${HY2_IPT_RANGE}" -j REDIRECT --to-ports "${HY2_LISTEN}" 2>/dev/null \
  && iptables -t nat -D PREROUTING -p udp --dport "${HY2_IPT_RANGE}" -j REDIRECT --to-ports "${HY2_LISTEN}" \
  || true
iptables -t nat -A PREROUTING -p udp --dport "${HY2_IPT_RANGE}" -j REDIRECT --to-ports "${HY2_LISTEN}"

echo "==> 保存 iptables 规则(重启后自动恢复)"
netfilter-persistent save

echo "==> 启动并启用 Hysteria 服务"
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service
sleep 2
systemctl --no-pager --lines=20 status hysteria-server.service || true

LINK="hysteria2://${HY2_PASSWORD}@${HY2_IP}:${HY2_LISTEN}/?sni=${HY2_IP}&alpn=h3&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}&insecure=1&pinSHA256=${PIN_SHA256}&mport=${HY2_RANGE}#${HY2_NAME}"
CLASH_NODE="- {name: ${HY2_NAME}, server: ${HY2_IP}, port: ${HY2_LISTEN}, alpn: [h3], obfs: salamander, obfs-password: ${HY2_OBFS_PASSWORD}, password: ${HY2_PASSWORD}, skip-cert-verify: true, sni: ${HY2_IP}, type: hysteria2}"

echo "==> 保存节点信息并安装 hy01 管理命令"
mkdir -p /etc/hysteria
cat >/etc/hysteria/hy2-node.env <<EOF
HY2_IP="${HY2_IP}"
HY2_LISTEN="${HY2_LISTEN}"
HY2_RANGE="${HY2_RANGE}"
HY2_PASSWORD="${HY2_PASSWORD}"
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD}"
HY2_PIN="${PIN_SHA256}"
HY2_NAME="${HY2_NAME}"
HY2_IPT_RANGE="${HY2_IPT_RANGE}"
EOF
chmod 600 /etc/hysteria/hy2-node.env

cat >/usr/local/bin/hy01 <<'HY01'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请用 root 运行: sudo hy01" >&2
  exit 1
fi

STATE_FILE="/etc/hysteria/hy2-node.env"
if [[ ! -f "${STATE_FILE}" ]]; then
  echo "未找到 Hysteria2 节点信息: ${STATE_FILE}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${STATE_FILE}"

show_links() {
  local v2rayn_link clash_node
  v2rayn_link="hysteria2://${HY2_PASSWORD}@${HY2_IP}:${HY2_LISTEN}/?sni=${HY2_IP}&alpn=h3&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}&insecure=1&pinSHA256=${HY2_PIN}&mport=${HY2_RANGE}#${HY2_NAME}"
  clash_node="- {name: ${HY2_NAME}, server: ${HY2_IP}, port: ${HY2_LISTEN}, alpn: [h3], obfs: salamander, obfs-password: ${HY2_OBFS_PASSWORD}, password: ${HY2_PASSWORD}, skip-cert-verify: true, sni: ${HY2_IP}, type: hysteria2}"
  echo
  echo "v2rayN 节点链接:"
  echo "${v2rayn_link}"
  echo
  echo "Clash 节点:"
  echo "${clash_node}"
  echo
}

delete_node() {
  local ans
  read -r -p "确定删除 Hysteria2 节点并移除 hy01 命令? [y/N]: " ans
  if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
    echo "已取消"
    return 0
  fi
  systemctl disable --now hysteria-server.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/hysteria-server.service
  systemctl daemon-reload
  rm -f /etc/hysteria/server.crt /etc/hysteria/server.key /etc/hysteria/config.yaml /etc/hysteria/hy2-node.env
  if iptables -t nat -C PREROUTING -p udp --dport "${HY2_IPT_RANGE}" -j REDIRECT --to-ports "${HY2_LISTEN}" >/dev/null 2>&1; then
    iptables -t nat -D PREROUTING -p udp --dport "${HY2_IPT_RANGE}" -j REDIRECT --to-ports "${HY2_LISTEN}"
  fi
  netfilter-persistent save >/dev/null 2>&1 || true
  rm -f /usr/local/bin/hy01
  echo "已删除 Hysteria2 节点"
}

echo "Hysteria2 节点管理"
echo "1. 显示节点链接"
echo "2. 删除"
read -r -p "请选择 [1/2]: " choice
case "${choice}" in
  1) show_links ;;
  2) delete_node ;;
  *) echo "无效选择: ${choice}" >&2; exit 1 ;;
esac
HY01
chmod 700 /usr/local/bin/hy01

echo
echo "======================================================"
echo " 安装完成"
echo " 公网 IP : ${HY2_IP}"
echo " 监听端口: ${HY2_LISTEN}"
echo " 跳跃范围: ${HY2_RANGE}"
echo " 认证密码: ${HY2_PASSWORD}"
echo " 混淆密码: ${HY2_OBFS_PASSWORD}"
echo " 节点名称: ${HY2_NAME}"
echo " 配置路径: /etc/hysteria/config.yaml"
echo " v2rayN 分享链接:"
echo "${LINK}"
echo
echo " Clash 节点:"
echo "${CLASH_NODE}"
echo
echo " 输入 hy01 可再次查看链接或删除节点"
echo "======================================================"

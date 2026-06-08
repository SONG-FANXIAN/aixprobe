#!/bin/bash
# ============================================================
# AixProbe n3n 超级节点一键部署脚本（在 VPS 上运行）
# 适用: Ubuntu 22.04+ / Debian 12+
# 用法: chmod +x deploy_vps_supernode.sh && sudo ./deploy_vps_supernode.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ---------- 配置 ----------
N3N_PORT=7654
N3N_NETNAME="aixprobe-net"
N3N_KEY="MySecretKey123"           # 生产环境务必修改！
# -------------------------

echo "============================================"
echo "  AixProbe n3n Supernode 部署"
echo "============================================"
echo ""
warn "当前配置:"
echo "  端口:     ${N3N_PORT}/udp"
echo "  网络名:   ${N3N_NETNAME}"
echo "  密钥:     ${N3N_KEY}"
echo ""

# 交互式修改配置
read -p "修改以上配置? (y/n, 默认n): " CHANGE
if [ "$CHANGE" = "y" ]; then
    read -p "端口 (默认7654): " tmp; [ -n "$tmp" ] && N3N_PORT=$tmp
    read -p "网络名 (默认aixprobe-net): " tmp; [ -n "$tmp" ] && N3N_NETNAME=$tmp
    read -p "密钥 (默认MySecretKey123): " tmp; [ -n "$tmp" ] && N3N_KEY=$tmp
fi

echo ""
echo "最终配置:"
echo "  端口:     ${N3N_PORT}/udp"
echo "  网络名:   ${N3N_NETNAME}"
echo "  密钥:     ${N3N_KEY}"
echo ""

read -p "开始部署? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && echo "已取消" && exit 0

# ---------- Step 1: 安装依赖 ----------
log "Step 1/4: 安装编译依赖..."
apt update -qq
apt install -y -qq build-essential cmake git autoconf libtool pkg-config libssl-dev net-tools

# ---------- Step 2: 编译 n3n ----------
log "Step 2/4: 编译 n3n..."

N3N_DIR="/opt/n3n"
if [ -d "$N3N_DIR" ]; then
    warn "n3n 源码已存在，git pull 更新..."
    cd "$N3N_DIR"
    git pull
else
    git clone https://github.com/ntop/n3n.git "$N3N_DIR"
    cd "$N3N_DIR"
fi

./autogen.sh
./configure
make -j$(nproc)
make install
log "n3n 安装完成: $(which supernode)"

# ---------- Step 3: 创建 systemd 服务 ----------
log "Step 3/4: 配置 systemd 服务..."

cat > /etc/systemd/system/n3n-supernode.service << SERVICE_EOF
[Unit]
Description=n3n Supernode (AixProbe VPN)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/supernode -p ${N3N_PORT} -v
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable n3n-supernode
systemctl restart n3n-supernode

# 等一秒让服务启动
sleep 2

if systemctl is-active --quiet n3n-supernode; then
    log "n3n-supernode 服务运行中 ✓"
else
    err "n3n-supernode 启动失败，查看日志: journalctl -u n3n-supernode -n 20"
fi

# ---------- Step 4: 防火墙 ----------
log "Step 4/4: 配置防火墙..."

# ufw
if command -v ufw &>/dev/null; then
    ufw allow ${N3N_PORT}/udp 2>/dev/null
    log "ufw 已放行 UDP ${N3N_PORT}"
fi

# iptables（备用）
if command -v iptables &>/dev/null; then
    iptables -I INPUT -p udp --dport ${N3N_PORT} -j ACCEPT 2>/dev/null || true
fi

# ---------- 完成 ----------
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "未知")
echo ""
echo "============================================"
echo "  ✅ 部署完成！"
echo "============================================"
echo ""
echo "  超级节点地址:  ${PUBLIC_IP}:${N3N_PORT}"
echo "  网络名称:      ${N3N_NETNAME}"
echo "  加密密钥:      ${N3N_KEY}"
echo ""
echo "  ── 下一步 ──"
echo ""
echo "  在 AixProbe 上运行:"
echo "    n3n-edge -d n3n0 -a 10.0.0.2 \\"
echo "             -c ${N3N_NETNAME} -k ${N3N_KEY} \\"
echo "             -l ${PUBLIC_IP}:${N3N_PORT}"
echo ""
echo "  在 PC 上运行:"
echo "    edge -d n3n0 -a 10.0.0.1 \\"
echo "         -c ${N3N_NETNAME} -k ${N3N_KEY} \\"
echo "         -l ${PUBLIC_IP}:${N3N_PORT}"
echo ""
echo "  ⚠️ 务必在云厂商控制台「安全组」中放行 UDP ${N3N_PORT} 端口！"
echo "============================================"

# 保存配置留给 AixProbe 脚本用
cat > /opt/n3n/deploy_info.conf << CONF_EOF
N3N_PORT=${N3N_PORT}
N3N_NETNAME=${N3N_NETNAME}
N3N_KEY=${N3N_KEY}
PUBLIC_IP=${PUBLIC_IP}
CONF_EOF
log "部署信息已保存到 /opt/n3n/deploy_info.conf"

#!/bin/bash
# ============================================================
# PC端 n3n-edge 部署脚本（在 Windows WSL / Linux / Mac 上运行）
# 用法: chmod +x deploy_pc_n3n.sh && ./deploy_pc_n3n.sh
# ============================================================

set -e

# ---------- 配置（修改为你的 VPS 信息）----------
VPS_IP="你的VPS公网IP"              # 必填！部署VPS后获取
N3N_PORT="7654"
N3N_NETNAME="aixprobe-net"
N3N_KEY="MySecretKey123"            # 三端一致
PC_VIP="10.0.0.1"                  # PC 的虚拟 IP
# ------------------------------------------------

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "============================================"
echo "  PC 端 n3n-edge 部署"
echo "============================================"
echo ""
echo "[i] 当前配置:"
echo "    VPS:       ${VPS_IP}:${N3N_PORT}"
echo "    虚拟IP:    ${PC_VIP}"
echo "    网络名:    ${N3N_NETNAME}"
echo ""

# 交互式配置
read -p "修改配置? (y/n, 默认n): " CHANGE
if [ "$CHANGE" = "y" ]; then
    read -p "VPS公网IP: " tmp; [ -n "$tmp" ] && VPS_IP=$tmp
    read -p "端口 (默认7654): " tmp; [ -n "$tmp" ] && N3N_PORT=$tmp
    read -p "虚拟IP (默认10.0.0.1): " tmp; [ -n "$tmp" ] && PC_VIP=$tmp
    read -p "网络名 (默认aixprobe-net): " tmp; [ -n "$tmp" ] && N3N_NETNAME=$tmp
    read -p "密钥 (默认MySecretKey123): " tmp; [ -n "$tmp" ] && N3N_KEY=$tmp
fi

if [ "$VPS_IP" = "你的VPS公网IP" ]; then
    echo -e "${RED}[✗]${NC} 请先修改脚本中的 VPS_IP！"
    exit 1
fi

read -p "开始部署? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && echo "已取消" && exit 0

# ---------- Step 1: 检测系统 ----------
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    OS="linux"  # 假设 WSL
fi

log "检测到系统: ${OS}"

# ---------- Step 2: 安装 n3n ----------
log "Step 1/3: 安装 n3n..."

if [ "$OS" = "macos" ]; then
    # macOS: 用 Homebrew
    if command -v brew &>/dev/null; then
        brew install n3n
    else
        echo "请先安装 Homebrew: https://brew.sh"
        exit 1
    fi
else
    # Linux / WSL: 从源码编译
    if command -v edge &>/dev/null; then
        log "n3n-edge 已安装: $(which edge)"
    else
        log "编译安装 n3n..."
        sudo apt update -qq
        sudo apt install -y -qq build-essential cmake git autoconf libtool pkg-config libssl-dev

        N3N_DIR="/tmp/n3n-build"
        if [ ! -d "$N3N_DIR" ]; then
            git clone https://github.com/ntop/n3n.git "$N3N_DIR"
        fi
        cd "$N3N_DIR"
        ./autogen.sh
        ./configure
        make -j$(nproc)
        sudo make install
        log "n3n 安装完成"
    fi
fi

# ---------- Step 3: 启动 ----------
log "Step 2/3: 启动 n3n-edge..."

# 停掉旧进程
sudo killall edge 2>/dev/null || true
sleep 1

# 启动（Linux 需要 root 权限创建 TUN 设备）
sudo edge -d n3n0 \
          -a "${PC_VIP}" \
          -c "${N3N_NETNAME}" \
          -k "${N3N_KEY}" \
          -l "${VPS_IP}:${N3N_PORT}" &
EDGE_PID=$!
sleep 2

# 验证
if ip addr show n3n0 > /dev/null 2>&1 || ifconfig n3n0 > /dev/null 2>&1; then
    log "n3n0 虚拟网卡已创建"
else
    warn "n3n0 创建可能失败，手动检查: ip addr show n3n0"
fi

# ---------- Step 4: 测试连接 ----------
log "Step 3/3: 测试到 AixProbe 的连接..."

# 测试 ping AixProbe
AIXPROBE_VIP="10.0.0.2"
if ping -c 2 -W 2 "${AIXPROBE_VIP}" > /dev/null 2>&1; then
    log "ping ${AIXPROBE_VIP} 成功！"
else
    warn "ping 不通 AixProbe (${AIXPROBE_VIP})，请确认 AixProbe 端已部署"
fi

# 测试 HTTP
CURL_RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://${AIXPROBE_VIP}:8080/api/v1/system/status" 2>/dev/null || echo "000")
if [ "$CURL_RESULT" = "200" ]; then
    log "ailink API 访问成功！"
    curl -s "http://${AIXPROBE_VIP}:8080/api/v1/system/status" | head -5
else
    warn "ailink API 返回 ${CURL_RESULT}，可能 AixProbe 端 n3n 还没配好"
fi

# ---------- 完成 ----------
echo ""
echo "============================================"
echo "  ✅ PC 端 n3n 部署完成！"
echo "============================================"
echo ""
echo "  你的虚拟IP:  ${PC_VIP}"
echo "  AixProbe IP: 10.0.0.2"
echo ""
echo "  常用命令:"
echo "    curl http://10.0.0.2:8080/api/v1/system/status"
echo "    ssh root@10.0.0.2"
echo "    scp firmware.bin root@10.0.0.2:/mnt/UDISK/"
echo ""
echo "  停止 VPN:  sudo killall edge"
echo "============================================"

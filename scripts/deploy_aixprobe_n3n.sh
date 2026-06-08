#!/bin/sh
# ============================================================
# AixProbe n3n-edge 部署脚本（在 AixProbe 上运行）
# 用法: chmod +x deploy_aixprobe_n3n.sh && ./deploy_aixprobe_n3n.sh
# ============================================================

# ---------- 配置（修改为你的 VPS 信息）----------
VPS_IP="你的VPS公网IP"              # 必填！
N3N_PORT="7654"
N3N_NETNAME="aixprobe-net"
N3N_KEY="MySecretKey123"            # 和 VPS 端一致
AIXPROBE_VIP="10.0.0.2"            # AixProbe 的虚拟 IP
# ------------------------------------------------

echo "============================================"
echo "  AixProbe n3n-edge 部署"
echo "============================================"
echo ""

# 检查是否是 AixProbe 环境
if [ ! -f /usr/bin/n3n-edge ]; then
    echo "[✗] n3n-edge 未找到，请确认AixProbe固件版本"
    exit 1
fi

echo "[i] 当前配置:"
echo "    VPS:       ${VPS_IP}:${N3N_PORT}"
echo "    虚拟IP:    ${AIXPROBE_VIP}"
echo "    网络名:    ${N3N_NETNAME}"
echo ""

# 交互式配置
read -p "修改配置? (y/n, 默认n): " CHANGE
if [ "$CHANGE" = "y" ]; then
    read -p "VPS公网IP: " tmp; [ -n "$tmp" ] && VPS_IP=$tmp
    read -p "端口 (默认7654): " tmp; [ -n "$tmp" ] && N3N_PORT=$tmp
    read -p "虚拟IP (默认10.0.0.2): " tmp; [ -n "$tmp" ] && AIXPROBE_VIP=$tmp
    read -p "网络名 (默认aixprobe-net): " tmp; [ -n "$tmp" ] && N3N_NETNAME=$tmp
    read -p "密钥 (默认MySecretKey123): " tmp; [ -n "$tmp" ] && N3N_KEY=$tmp
fi

# 验证必填项
if [ "$VPS_IP" = "你的VPS公网IP" ]; then
    echo "[✗] 请先修改脚本中的 VPS_IP！"
    exit 1
fi

echo ""
read -p "开始部署? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && echo "已取消" && exit 0

# ---------- Step 1: 测试连接 ----------
echo "[1/3] 测试 VPS 连接..."
ping -c 2 -W 2 "$VPS_IP" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[!] ping 不通 VPS，请检查:"
    echo "    1. AixProbe WiFi 是否已连接"
    echo "    2. VPS 安全组是否放行 UDP ${N3N_PORT}"
    echo "    3. VPS 上 supernode 是否已启动"
    read -p "仍要继续? (y/n): " c; [ "$c" != "y" ] && exit 1
fi

# ---------- Step 2: 启动 n3n-edge ----------
echo "[2/3] 启动 n3n-edge..."

# 先停掉旧进程
killall n3n-edge 2>/dev/null
sleep 1

# 启动
n3n-edge -d n3n0 \
         -a "${AIXPROBE_VIP}" \
         -c "${N3N_NETNAME}" \
         -k "${N3N_KEY}" \
         -l "${VPS_IP}:${N3N_PORT}" &
EDGE_PID=$!
sleep 2

# 验证
if ip addr show n3n0 > /dev/null 2>&1; then
    echo "[✓] n3n0 虚拟网卡已创建"
    ip addr show n3n0 | grep "inet "
else
    echo "[✗] n3n0 创建失败"
    exit 1
fi

# ---------- Step 3: 配置开机自启 ----------
echo "[3/3] 配置开机自启..."

cat > /etc/init.d/S91n3n << INIT_EOF
#!/bin/sh
# n3n-edge 开机自启

case "\$1" in
    start)
        echo "Starting n3n-edge..."
        sleep 10  # 等 WiFi 先连上
        n3n-edge -d n3n0 \\
                 -a ${AIXPROBE_VIP} \\
                 -c ${N3N_NETNAME} \\
                 -k ${N3N_KEY} \\
                 -l ${VPS_IP}:${N3N_PORT} &
        echo "n3n-edge started (pid \$!)"
        ;;
    stop)
        killall n3n-edge 2>/dev/null
        echo "n3n-edge stopped"
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
esac
INIT_EOF

chmod +x /etc/init.d/S91n3n

# ---------- 完成 ----------
echo ""
echo "============================================"
echo "  ✅ AixProbe n3n 部署完成！"
echo "============================================"
echo ""
echo "  虚拟IP:  ${AIXPROBE_VIP}"
echo "  网络名:  ${N3N_NETNAME}"
echo ""
echo "  验证命令:"
echo "    ip addr show n3n0"
echo "    ping 10.0.0.1         (PC 的虚拟IP)"
echo ""
echo "  现在在 PC 上安装 n3n-edge 即可互联"
echo "============================================"

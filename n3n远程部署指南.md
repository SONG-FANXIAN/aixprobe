# n3n P2P VPN 远程部署指南

> 目标：在任何有网络的地方，像在局域网一样远程调试/烧录 AixProbe

```
┌──────────┐      互联网       ┌──────────────┐      互联网       ┌──────────┐
│  你的PC   │ ←──────────────→ │  VPS 超级节点  │ ←──────────────→ │ AixProbe │
│ 10.0.0.1 │                  │ 公网IP: 1.2.3.4│                  │ 10.0.0.2 │
└──────────┘                  └──────────────┘                  └──────────┘
     │                                                               │
     └────────── 虚拟局域网 10.0.0.x，互相 ping 通 ──────────────────┘
                    curl http://10.0.0.2:8080 ← 随时访问
```

---

## 第1步：准备 VPS 服务器（超级节点）

> 选最便宜的就行：阿里云/腾讯云/华为云 1核1G，约 30元/月  
> 系统选 **Ubuntu 22.04** 或 **Debian 12**

### 1.1 SSH 登录 VPS

```bash
ssh root@你的VPS公网IP
```

### 1.2 安装 n3n 超级节点

```bash
# 更新包列表
apt update

# 安装依赖
apt install -y build-essential cmake git autoconf libtool pkg-config libssl-dev

# 编译安装 n3n（v3 版本）
cd /opt
git clone https://github.com/ntop/n3n.git
cd n3n
./autogen.sh
./configure
make -j$(nproc)
make install

# 验证安装
supernode --version
```

### 1.3 启动超级节点

```bash
# 创建配置目录
mkdir -p /etc/n3n

# 直接启动（先测试）
supernode -p 7654 -v

# 看到 "supernode started on port 7654" 说明成功
# Ctrl+C 停掉，下一步配成服务
```

### 1.4 配置开机自启

```bash
cat > /etc/systemd/system/n3n-supernode.service << 'EOF'
[Unit]
Description=n3n Supernode
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/supernode -p 7654 -v
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n3n-supernode
systemctl start n3n-supernode
systemctl status n3n-supernode   # 确认 running
```

### 1.5 开放防火墙端口

```bash
# VPS 防火墙开放 UDP 7654
ufw allow 7654/udp
ufw status

# ⚠️ 云服务器还需要在「安全组」中放行 UDP 7654 端口
# 登录云厂商控制台 → 安全组 → 添加规则：
#   协议: UDP   端口: 7654   来源: 0.0.0.0/0
```

---

## 第2步：AixProbe 配置 n3n-edge

> AixProbe 已预装 `n3n-edge`，直接配置即可。

### 2.1 手动测试连接

```bash
# 登录 AixProbe（USB/ADB）
adb shell

# 启动 n3n-edge（替换为你的VPS IP）
n3n-edge -d n3n0 -a 10.0.0.2 -c aixprobe-net -k MySecretKey123 -l 你的VPS_IP:7654

# 参数说明：
#   -d n3n0          虚拟网卡名
#   -a 10.0.0.2      AixProbe 在虚拟网络中的 IP
#   -c aixprobe-net  网络名称（同一网络的设备用相同名称）
#   -k MySecretKey123 加密密钥（同一网络用相同密钥，请改掉！）
#   -l VPS_IP:7654   超级节点地址

# 验证
ip addr show n3n0        # 应该看到 10.0.0.2
ping 10.0.0.1            # ping 你的 PC（PC 配好之后才能通）
```

### 2.2 配置 WiFi + n3n 开机自启

```bash
# 创建自启动脚本
cat > /etc/init.d/S91n3n << 'EOF'
#!/bin/sh
# n3n-edge 启动脚本

case "$1" in
    start)
        echo "Starting n3n-edge..."
        # 等 WiFi 连上
        sleep 10
        # 启动 n3n
        n3n-edge -d n3n0 -a 10.0.0.2 \
                 -c aixprobe-net \
                 -k MySecretKey123 \
                 -l 你的VPS_IP:7654 &
        echo "n3n-edge started"
        ;;
    stop)
        killall n3n-edge 2>/dev/null
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
esac
EOF

chmod +x /etc/init.d/S91n3n
```

> ⚠️ 记得把 `你的VPS_IP` 和 `MySecretKey123` 换成你自己的值！

---

## 第3步：PC 安装 n3n-edge

### 3.1 Windows 安装

**方式A：WSL（推荐，最简单）**

```bash
# 在 WSL Ubuntu 中
sudo apt update && sudo apt install -y build-essential cmake git autoconf libtool
cd /opt
git clone https://github.com/ntop/n3n.git
cd n3n
./autogen.sh && ./configure && make -j$(nproc) && sudo make install

# 连接虚拟网络
sudo edge -d n3n0 -a 10.0.0.1 -c aixprobe-net -k MySecretKey123 -l 你的VPS_IP:7654
```

**方式B：原生 Windows**

```powershell
# 下载 n3n Windows 预编译版
# https://github.com/ntop/n3n/releases
# 解压后在 PowerShell 中运行：

.\edge.exe -d n3n0 -a 10.0.0.1 -c aixprobe-net -k MySecretKey123 -l 你的VPS_IP:7654
```

**方式C：macOS**

```bash
brew install n3n
sudo edge -d n3n0 -a 10.0.0.1 -c aixprobe-net -k MySecretKey123 -l 你的VPS_IP:7654
```

### 3.2 验证连接

```bash
# PC 上执行
ping 10.0.0.2          # 应该能 ping 通 AixProbe
curl http://10.0.0.2:8080/api/v1/system/status
# 看到 JSON 返回 → 远程连接成功！
```

---

## 第4步：远程使用

三端都连通之后，你在**任何地方、任何网络**都可以：

```bash
# ===== AixProbe 现在有了固定虚拟 IP: 10.0.0.2 =====

# 查看设备状态
curl http://10.0.0.2:8080/api/v1/system/status

# 连接 STM32
curl -X POST http://10.0.0.2:8080/api/v1/session/connect \
  -H "Content-Type: application/json" -d '{}'

# 暂停 + 烧录
curl -X POST http://10.0.0.2:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"halt"}'

# 上传固件
scp firmware.bin root@10.0.0.2:/mnt/UDISK/firmware.bin

# 烧录
curl -X POST http://10.0.0.2:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"flash_write","params":{"address":"0x08000000","filepath":"/mnt/UDISK/firmware.bin"}}'

# 复位运行
curl -X POST http://10.0.0.2:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"reset","params":{"type":"run"}}'

# SSH 登录
ssh root@10.0.0.2
```

---

## 第5步：MCP 远程 AI 调试

在 Claude Code 的 `.claude/settings.json` 中：

```json
{
  "mcpServers": {
    "aixprobe-remote": {
      "command": "ssh",
      "args": [
        "root@10.0.0.2",
        "/usr/bin/ailink",
        "--mcp-stdio"
      ]
    }
  }
}
```

> 前提是 PC 也连入了 n3n 虚拟网络（SSH 走虚拟 IP 10.0.0.2）

---

## 附录：安全加固

```bash
# 1. 修改默认密钥（三端一致）
#    把 MySecretKey123 换成一个强密码，如：
#    Xk9#mP2$vL7@qR4

# 2. 建议 ailink 启用 Token 认证
cat > /etc/ailink/ailink.conf << 'EOF'
bind_addr = 0.0.0.0
port = 8080
token = YourTokenHere123
log_level = 2
openocd_bin = openocd
EOF

# 之后 API 调用需要带 Token：
curl -H "Authorization: Bearer YourTokenHere123" \
     http://10.0.0.2:8080/api/v1/system/status
```

---

## 快速排错

| 问题 | 检查 |
|------|------|
| supernode 起不来 | `systemctl status n3n-supernode`，检查端口是否被占 |
| AixProbe 连不上 VPS | `ping 你的VPS_IP`；VPS 安全组是否放行 UDP 7654 |
| PC ping 不通 10.0.0.2 | 检查三端 `-c` 网络名和 `-k` 密钥是否一致 |
| curl 超时 | `ip addr show n3n0` 确认虚拟网卡 IP 正确 |
| WiFi 断了 n3n 也断 | 脚本已加 `Restart=always`，断了会自动重连 |

---

> **成本总结**：一台最便宜的 VPS（~30元/月）+ 零额外硬件 = 全球远程调试  
> **延迟参考**：同城 < 10ms，跨省 < 50ms，跨国 < 200ms

# AixProbe 嵌入式AI远程调试器 — 完整使用教程

> **适用固件**: v0.1.0 / Buildroot 2019.02.1 / Linux 5.4.61  
> **适用人群**: 嵌入式开发者、AI调试入门、已拿到AixProbe硬件的用户

---

## 目录

1. [硬件概览](#1-硬件概览)
2. [首次上电](#2-首次上电)
3. [连接设备](#3-连接设备)
4. [配置 WiFi](#4-配置-wifi)
5. [LED 指示灯说明](#5-led-指示灯说明)
6. [连接目标芯片](#6-连接目标芯片)
7. [AI 远程调试](#7-ai-远程调试)
8. [烧录固件](#8-烧录固件)
9. [串口终端](#9-串口终端)
10. [硬件底层工具](#10-硬件底层工具)
11. [MCP 集成 AI 客户端](#11-mcp-集成-ai-客户端)
12. [实战示例](#12-实战示例)
13. [故障排查](#13-故障排查)

---

## 1. 硬件概览

![接口布局](https://img-blog.csdnimg.cn/direct/aixprobe_interfaces.png)

AixProbe 提供 **9 组硬件接口**：

| 编号 | 接口 | 功能 | 日常用法 |
|------|------|------|----------|
| ① | 拨码开关 | IO 电平切换 (3.3V/2.5V/1.8V/1.2V) | 匹配目标芯片电压 |
| ② | 10Pin JTAG/SWD | 核心调试接口 | 接目标板的 SWDIO/SWCLK/GND |
| ③ | 双路串口 | 串口桥接 | 电脑 ↔ 目标板串口通信 |
| ④ | 自定义按键 | GPIO139, 用户可编程 | 自定义功能按键 |
| ⑤ | 4路 LED | 电源 + 就绪 + 2路自定义 | 查看设备状态 |
| ⑥ | USB Host | 外接 J-Link/ST-Link | 桥接模式，让旧调试器获得AI能力 |
| ⑦ | USB CH347F | 多协议转换芯片 | 调试+串口+SPI/I2C |
| ⑧ | ADB 接口 | Type-C, 调试 + 供电 | **连接电脑的主要接口** |
| ⑨ | 12V 电源 | 外部独立供电 | 给目标板供电 |

---

## 2. 首次上电

### 2.1 开箱即用

```
1. 用 Type-C 数据线连接 AixProbe ⑧ 到电脑
2. 4个 LED 依次闪烁后全部常亮 → 系统就绪
3. 电脑上打开终端，输入 adb shell 即可登录
```

### 2.2 验证连接

```bash
# 查看ADB设备
adb devices
# 预期输出:
# List of devices attached
# 0402101560    device

# 登录设备
adb shell

# 查看系统信息
cat /etc/os-release
# NAME=Buildroot
# VERSION=2019.02.1

# 查看IP地址
ip addr
```

---

## 3. 连接设备

AixProbe 支持 **3种连接方式**：

### 3.1 USB/ADB 连接（最常用）

```bash
# 无需任何配置，插上Type-C线即可
adb shell
```

适用于：首次配置、固件烧录、本地调试

### 3.2 WiFi 连接（远程调试必备）

前提：已完成 [第4章 WiFi配置](#4-配置-wifi)

```bash
# 获取设备IP
adb shell ip addr show wlan0 | grep "inet "

# 通过SSH连接
ssh root@192.168.x.x
```

适用于：远程AI调试、MCP集成、无线烧录

### 3.3 串口连接（备用）

```bash
# 波特率 115200
minicom -D /dev/ttyUSB0 -b 115200
# 或
picocom -b 115200 /dev/ttyUSB0
```

---

## 4. 配置 WiFi

### 4.1 编辑 WiFi 配置

```bash
# 登录设备
adb shell

# 编辑配置文件
vi /etc/wpa_supplicant.conf
```

修改为你自己的 WiFi：

```ini
ctrl_interface=/var/run/wpa_supplicant
ap_scan=1
update_config=1

network={
    ssid="你的WiFi名称"
    psk="你的WiFi密码"
}
```

### 4.2 重启 WiFi

```bash
# 重启wpa_supplicant
killall wpa_supplicant
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf

# 获取IP（DHCP）
udhcpc -i wlan0

# 验证连接
ip addr show wlan0
ping 8.8.8.8
```

### 4.3 开机自动连 WiFi

WiFi 启动脚本 `/etc/init.d/S39wifi` 已配置自启，只需保证配置文件正确即可。

---

## 5. LED 指示灯说明

AixProbe 有 **4 路 LED**，位置在板子边缘：

| LED | 丝印 | GPIO | 颜色 | 亮 = 含义 | 灭 = 含义 |
|-----|------|------|------|-----------|-----------|
| **电源** | PWR | 硬件 | 红 | 设备已供电 | 未上电 |
| **就绪** | RDY | 硬件 | 绿 | 系统启动完成 | 系统启动中 |
| **LED1** | L1 | GPIO133 | 蓝 | 初始化完成 / 用户自定义 | 初始化未完成 |
| **LED2** | L2 | GPIO134 | 蓝 | 初始化完成 / 用户自定义 | 初始化未完成 |

> 💡 **正常状态**: 上电后 4 灯全亮 = AixProbe 就绪。

### 启动时序

```
上电 → PWR亮 → 内核启动 → RDY亮 → init_start.sh执行:
  LED2灭 → LED1灭 → 初始化JTAG/按键 → LED1亮 + LED2亮 → 系统就绪
```

### 手动控制自定义 LED

LED1/LED2 是**低电平有效**（0=亮, 1=灭），可通过 sysfs 控制：

```bash
# 熄灭 LED1
echo 1 > /sys/class/gpio/gpio133/value

# 点亮 LED1
echo 0 > /sys/class/gpio/gpio133/value

# 闪烁效果（每秒切换一次）
while true; do
    echo 0 > /sys/class/gpio/gpio133/value
    sleep 0.5
    echo 1 > /sys/class/gpio/gpio133/value
    sleep 0.5
done
```

---

## 6. 连接目标芯片

### 6.1 物理接线

将 AixProbe 的 **10Pin SWD 接口 ②** 连接到目标板：

```
AixProbe SWD接口          目标板 (以STM32为例)
─────────────────         ─────────────────
  SWDIO       ──────────  SWDIO / PA13
  SWCLK       ──────────  SWCLK / PA14
  GND         ──────────  GND
  (可选) RST  ──────────  nRST
  (可选) 3.3V ──────────  VDD (如需供电)
```

### 6.2 配置目标芯片

编辑 `/etc/ailink/openocd_cmd` 指定你的目标芯片：

```bash
# 当前默认是 STM32F1
echo 'openocd -f interface/ch347.cfg -f target/stm32f1x.cfg -c "bindto 0.0.0.0" -c "gdb port 3333"' > /etc/ailink/openocd_cmd
```

**常用目标配置文件**（位于 `/usr/share/openocd/scripts/target/`）：

| 文件 | 芯片系列 |
|------|----------|
| `stm32f1x.cfg` | STM32F1xx (Cortex-M3) |
| `stm32f4x.cfg` | STM32F4xx (Cortex-M4) |
| `stm32f7x.cfg` | STM32F7xx (Cortex-M7) |
| `stm32h7x.cfg` | STM32H7xx (Cortex-M7) |
| `stm32l4x.cfg` | STM32L4xx (Cortex-M4) |
| `at91sam3XXX.cfg` | Atmel SAM3 (Cortex-M3) |
| `nrf52.cfg` | Nordic nRF52 (Cortex-M4) |
| `esp32.cfg` | ESP32 (Xtensa) |

### 6.3 电平匹配

**重要**: 确保拨码开关 ① 设置的电平与目标芯片一致。

```
目标芯片电压  →  拨码开关位置
  3.3V       →  3.3V
  2.5V       →  2.5V
  1.8V       →  1.8V
  1.2V       →  1.2V
```

### 6.4 连接与测试

```bash
# 方式一：通过 REST API 连接
adb shell wget -qO- --post-data='{}' http://localhost:8080/api/v1/session/connect

# 检查连接状态
adb shell wget -qO- http://localhost:8080/api/v1/system/status
# 看到 "openocd_running": true → 连接成功
```

---

## 7. AI 远程调试

### 7.1 调试服务器 `ailink`

AixProbe 的核心是一个叫 `ailink` 的 HTTP 服务器，开机自启在 **端口 8080**。

```
┌─────────────┐     HTTP/MCP      ┌─────────────┐     SWD/JTAG     ┌──────────┐
│  AI 客户端   │ ←──────────────→ │  AixProbe    │ ←──────────────→ │ 目标MCU   │
│ (Claude等)  │    WiFi/USB/ADB   │  (ailink)    │   CH347F芯片     │ (STM32等) │
└─────────────┘                   └─────────────┘                   └──────────┘
```

### 7.2 REST API 速查

所有 API 基地址: `http://<设备IP>:8080`

```bash
# ===== 系统 =====
GET  /api/v1/system/status          # 设备状态、内存、会话信息

# ===== 会话 =====
POST   /api/v1/session/connect      # 连接目标芯片（启动OpenOCD）
DELETE /api/v1/session/             # 断开连接

# ===== 调试命令 =====
GET  /api/v1/commands               # 获取所有命令列表
POST /api/v1/commands               # 执行调试命令

# ===== 固件 =====
POST /api/v1/upload                 # 上传固件文件

# ===== 串口 =====
POST /api/v1/channel/uart/open      # 打开串口
POST /api/v1/channel/uart/close     # 关闭串口
POST /api/v1/channel/uart/send      # 串口发送
GET  /api/v1/channel/uart/read      # 串口读取
```

### 7.3 17个调试命令详解

#### 连接控制

```bash
# 连接目标芯片
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "connect"}'

# 断开连接
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "disconnect"}'
```

#### 执行控制（CPU暂停/运行/单步）

```bash
# 暂停CPU
curl -X POST ... -d '{"command": "halt"}'

# 恢复运行
curl -X POST ... -d '{"command": "resume"}'

# 单步执行（执行一条指令后自动暂停）
curl -X POST ... -d '{"command": "step"}'

# 复位目标芯片
curl -X POST ... -d '{"command": "reset", "params": {"type": "halt"}}'
# type可选: "run"（复位后运行）、"halt"（复位后暂停）、"init"（复位后初始化）
```

#### 寄存器读写

```bash
# 读取寄存器（ARM Cortex-M 常用寄存器）
curl -X POST ... -d '{"command": "register_read", "params": {"name": "pc"}}'
curl -X POST ... -d '{"command": "register_read", "params": {"name": "sp"}}'
curl -X POST ... -d '{"command": "register_read", "params": {"name": "lr"}}'
curl -X POST ... -d '{"command": "register_read", "params": {"name": "r0"}}'
curl -X POST ... -d '{"command": "register_read", "params": {"name": "xPSR"}}'

# 写入寄存器
curl -X POST ... -d '{"command": "register_write", "params": {"name": "r0", "value": "0x12345678"}}'
```

#### 内存读写

```bash
# 读取内存（从0x08000000读取256字节）
curl -X POST ... -d '{"command": "memory_read", "params": {"address": "0x08000000", "size": 256}}'

# 写入内存
curl -X POST ... -d '{"command": "memory_write", "params": {"address": "0x20000000", "data": "DEADBEEF"}}'

# 导出内存镜像到文件
curl -X POST ... -d '{"command": "dump_image", "params": {"address": "0x08000000", "size": 65536, "filepath": "/mnt/UDISK/flash_dump.bin"}}'
```

#### 断点管理

```bash
# 设置硬件断点
curl -X POST ... -d '{"command": "breakpoint_set", "params": {"address": "0x08000100", "type": "hw"}}'

# 列出所有断点
curl -X POST ... -d '{"command": "breakpoint_list"}'

# 移除断点
curl -X POST ... -d '{"command": "breakpoint_remove", "params": {"address": "0x08000100"}}'
```

#### Flash 烧录

```bash
# 擦除Flash（擦除0x08000000开始的128KB）
curl -X POST ... -d '{"command": "flash_erase", "params": {"address": "0x08000000", "size": 131072}}'

# 烧录固件（文件需先上传至/mnt/UDISK/）
curl -X POST ... -d '{"command": "flash_write", "params": {"address": "0x08000000", "filepath": "/mnt/UDISK/firmware.bin"}}'
```

#### 高级命令

```bash
# 直接发送 OpenOCD TCL 命令
curl -X POST ... -d '{"command": "raw_command", "params": {"cmd": "arm semihosting enable"}}'
curl -X POST ... -d '{"command": "raw_command", "params": {"cmd": "flash banks"}}'
curl -X POST ... -d '{"command": "raw_command", "params": {"cmd": "mdw 0x08000000 16"}}'
```

---

## 8. 烧录固件

### 8.1 完整烧录流程

```bash
# 1. 将固件推送到设备
adb push firmware.bin /mnt/UDISK/
# 或通过scp
scp firmware.bin root@设备IP:/mnt/UDISK/

# 2. 连接目标芯片
curl -X POST http://设备IP:8080/api/v1/session/connect -H "Content-Type: application/json" -d '{}'

# 3. 暂停CPU
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "halt"}'

# 4. 擦除Flash
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "flash_erase", "params": {"address": "0x08000000", "size": 131072}}'

# 5. 烧录固件
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "flash_write", "params": {"address": "0x08000000", "filepath": "/mnt/UDISK/firmware.bin"}}'

# 6. 验证（读回前256字节检查）
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "memory_read", "params": {"address": "0x08000000", "size": 256}}'

# 7. 复位运行
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "reset", "params": {"type": "run"}}'

# 8. 断开连接
curl -X DELETE http://设备IP:8080/api/v1/session/
```

### 8.2 一键烧录脚本

保存为 `flash.py`：

```python
#!/usr/bin/env python3
"""AixProbe 一键烧录脚本"""
import requests, sys, os, subprocess

DEVICE_IP = "192.168.1.100"  # 改为你的设备IP
BASE = f"http://{DEVICE_IP}:8080"

def cmd(command, params=None):
    body = {"command": command}
    if params:
        body["params"] = params
    r = requests.post(f"{BASE}/api/v1/commands", json=body)
    return r.json()

def flash(firmware_path, address="0x08000000", erase_size=131072):
    # 上传固件
    print(f"[1/5] 上传固件: {firmware_path}")
    subprocess.run(["scp", firmware_path, f"root@{DEVICE_IP}:/mnt/UDISK/firmware.bin"], check=True)

    # 连接
    print("[2/5] 连接目标芯片...")
    r = requests.post(f"{BASE}/api/v1/session/connect", json={})
    print(f"  → {r.json()}")

    # 暂停+擦除+烧录
    print("[3/5] 擦除Flash...")
    cmd("halt")
    cmd("flash_erase", {"address": address, "size": erase_size})

    print("[4/5] 烧录固件...")
    cmd("flash_write", {"address": address, "filepath": "/mnt/UDISK/firmware.bin"})

    # 复位运行
    print("[5/5] 复位运行...")
    cmd("reset", {"type": "run"})

    print("✅ 烧录完成！")

if __name__ == "__main__":
    flash(sys.argv[1] if len(sys.argv) > 1 else "firmware.bin")
```

---

## 9. 串口终端

### 9.1 打开串口

```bash
# 打开串口 /dev/ttyS0，波特率115200
curl -X POST http://设备IP:8080/api/v1/channel/uart/open \
  -H "Content-Type: application/json" \
  -d '{"device": "/dev/ttyS0", "baud": 115200}'
```

### 9.2 发送数据

```bash
# 发送字符串
curl -X POST http://设备IP:8080/api/v1/channel/uart/send \
  -H "Content-Type: application/json" \
  -d '{"data": "hello world\r\n"}'

# 发送十六进制
curl -X POST http://设备IP:8080/api/v1/channel/uart/send \
  -H "Content-Type: application/json" \
  -d '{"data": "\\x41\\x54\\x2B\\x43\\x4D\\x47\\x53\\x3D"}'
```

### 9.3 读取数据

```bash
# 读取串口缓冲区
curl http://设备IP:8080/api/v1/channel/uart/read
```

### 9.4 关闭串口

```bash
curl -X POST http://设备IP:8080/api/v1/channel/uart/close \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 9.5 串口透传模式

```bash
# 在设备上直接用 minicom
adb shell minicom -D /dev/ttyS0 -b 115200
```

---

## 10. 硬件底层工具

AixProbe 内置了丰富的 Linux 嵌入式调试工具。

### 10.1 I2C 总线调试

```bash
# 扫描I2C-0总线上所有设备
i2cdetect -y 0

# 读取设备0x50的寄存器0x00
i2cget -y 0 0x50 0x00

# 写入设备0x50的寄存器0x00值为0xFF
i2cset -y 0 0x50 0x00 0xff

# 导出设备0x50的全部寄存器
i2cdump -y 0 0x50
```

### 10.2 SPI 总线调试

```bash
# 查询SPI当前配置
spi-config --device=/dev/spidev1.1 --query

# 设置SPI模式0
spi-config --device=/dev/spidev1.1 --mode=0

# 收发256字节数据（1MHz时钟）
spi-pipe --device=/dev/spidev1.1 --speed=1000000 --blocksize=256 --number=1

# SPI回环测试
spi_test --device=/dev/spidev1.1 --speed=1000000 --loop
```

### 10.3 GPIO 控制

```bash
# 读取按键状态
cat /sys/class/gpio/gpio139/value
# 0 = 按下, 1 = 松开

# 控制LED1闪烁
while true; do
    echo 0 > /sys/class/gpio/gpio133/value; sleep 0.2
    echo 1 > /sys/class/gpio/gpio133/value; sleep 0.2
done &

# 导出并使用新GPIO
echo 128 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio128/direction
echo 1 > /sys/class/gpio/gpio128/value    # JTAG_RST拉高
```

### 10.4 CAN 总线调试

```bash
# 配置CAN接口（500kbps）
ip link set can0 type can bitrate 500000
ip link set can0 up

# 发送CAN帧（ID=0x123, 数据=DEADBEEF）
cansend can0 123#DEADBEEF

# 监听CAN总线
candump can0

# 交互式监控
cansniffer can0

# CAN总线负载
canbusload can0@500000
```

### 10.5 Flash 存储操作

```bash
# 查看MTD分区信息
cat /proc/mtd

# 擦除MTD分区
flash_erase /dev/mtd4 0 0

# 备份Flash内容
nanddump /dev/mtd0 -f /mnt/UDISK/mtd0_backup.bin

# 写入Flash
nandwrite /dev/mtd4 /mnt/UDISK/new_data.bin
```

### 10.6 系统诊断

```bash
# CPU频率+使用率+温度监控（每500ms刷新）
cpu_monitor -s 500

# 内存压力测试（测试32MB，跑3轮）
memtester 32M 3

# 系统资源概览
top
free
df -h

# 查看内核日志
dmesg | tail -50

# 网络吞吐测试（服务端在AixProbe上）
iperf3 -s
# 客户端在PC上
iperf3 -c 设备IP
```

---

## 11. MCP 集成 AI 客户端

### 11.1 Claude Code 集成

在项目的 `.claude/settings.json` 中添加：

```json
{
  "mcpServers": {
    "aixprobe": {
      "command": "ssh",
      "args": [
        "root@192.168.1.100",
        "/usr/bin/ailink",
        "--mcp-stdio"
      ]
    }
  }
}
```

配置后在 Claude Code 中可以直接对话调试：

```
你: 连接目标芯片，暂停CPU，告诉我PC寄存器的值
Claude: [自动调用 ailink MCP 工具]
  → connect → halt → register_read("pc") → 返回 PC = 0x080001a4
```

### 11.2 Trae 集成

在 `.trae/settings.json` 中配置同上，AI 直接调用硬件调试能力。

### 11.3 自定义 AI Agent 集成

```python
"""将 AixProbe 集成到你的 AI Agent"""
import requests

class AixProbeClient:
    def __init__(self, host="192.168.1.100", port=8080):
        self.base = f"http://{host}:{port}"

    def connect(self):
        return requests.post(f"{self.base}/api/v1/session/connect", json={}).json()

    def disconnect(self):
        return requests.delete(f"{self.base}/api/v1/session/").json()

    def execute(self, command, params=None):
        body = {"command": command}
        if params:
            body["params"] = params
        return requests.post(f"{self.base}/api/v1/commands", json=body).json()

    def halt(self):     return self.execute("halt")
    def resume(self):   return self.execute("resume")
    def step(self):     return self.execute("step")
    def reg(self, name): return self.execute("register_read", {"name": name})
    def mem(self, addr, size): return self.execute("memory_read", {"address": addr, "size": size})
    def flash_write(self, addr, path): return self.execute("flash_write", {"address": addr, "filepath": path})

# 使用示例
aix = AixProbeClient("192.168.1.100")
aix.connect()
aix.halt()
print(f"PC = {aix.reg('pc')}")
print(f"SP = {aix.reg('sp')}")
aix.resume()
aix.disconnect()
```

### 11.4 可用 MCP 工具列表

当 AI 客户端连接后，`ailink` 自动暴露以下工具：

| 工具 | 参数 | 说明 |
|------|------|------|
| `system_status` | 无 | 系统信息和会话状态 |
| `connect` | 无 | 连接目标芯片 |
| `disconnect` | 无 | 断开目标芯片 |
| `halt` | 无 | CPU暂停 |
| `resume` | 无 | CPU恢复运行 |
| `step` | 无 | 单步执行 |
| `reset` | `type`: "run"/"halt"/"init" | 复位CPU |
| `memory_read` | `address`, `size` | 读取内存 |
| `memory_write` | `address`, `data` | 写入内存 |
| `register_read` | `name` | 读取寄存器 |
| `register_write` | `name`, `value` | 写入寄存器 |
| `breakpoint_set` | `address`, `type` | 设置断点 |
| `breakpoint_remove` | `address` | 移除断点 |
| `breakpoint_list` | 无 | 列出断点 |
| `flash_write` | `address`, `filepath` | 烧录固件 |
| `flash_erase` | `address`, `size` | 擦除Flash |
| `dump_image` | `address`, `size`, `filepath` | 导出内存镜像 |
| `raw_command` | `cmd` | 原始OpenOCD命令 |

---

## 12. 实战示例

### 12.1 HardFault 故障诊断

当目标芯片进入 HardFault 异常时的标准诊断流程：

```bash
# 1. 暂停CPU
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command": "halt"}'

# 2. 读取异常现场寄存器
curl ... -d '{"command": "register_read", "params": {"name": "pc"}}'
curl ... -d '{"command": "register_read", "params": {"name": "sp"}}'
curl ... -d '{"command": "register_read", "params": {"name": "lr"}}'

# 3. 读 Cortex-M 系统控制寄存器
curl ... -d '{"command": "register_read", "params": {"name": "cfsr"}}'
curl ... -d '{"command": "register_read", "params": {"name": "hfsr"}}'
curl ... -d '{"command": "register_read", "params": {"name": "mmar"}}'
curl ... -d '{"command": "register_read", "params": {"name": "bfar"}}'

# 4. 读取栈帧（从SP开始读64字节）
# SP值假设为 0x20000FD8
curl ... -d '{"command": "memory_read", "params": {"address": "0x20000FD8", "size": 64}}'

# 5. 分析: 根据栈帧还原异常前的 R0-R3, R12, LR, PC, xPSR
```

### 12.2 Python 自动化诊断脚本

```python
#!/usr/bin/env python3
"""HardFault 自动诊断"""
import requests, struct

BASE = "http://192.168.1.100:8080"

def cmd(command, params=None):
    body = {"command": command}
    if params: body["params"] = params
    return requests.post(f"{BASE}/api/v1/commands", json=body).json()

def hardfault_diagnose():
    print("=== HardFault 诊断 ===")

    # 暂停
    cmd("halt")

    # 读取关键寄存器
    regs = {}
    for r in ["pc", "sp", "lr", "cfsr", "hfsr", "mmar", "bfar"]:
        result = cmd("register_read", {"name": r})
        regs[r] = result
        print(f"  {r.upper():6s} = {result}")

    # 分析CFSR
    cfsr = int(regs.get("cfsr", "0"), 16) if isinstance(regs.get("cfsr"), str) else 0
    faults = []
    if cfsr & (1 << 25): faults.append("DIVBYZERO - 除零错误")
    if cfsr & (1 << 24): faults.append("UNALIGNED - 非对齐访问")
    if cfsr & (1 << 1):  faults.append("PRECISERR - 精确总线错误")
    if cfsr & (1 << 0):  faults.append("IACCVIOL - 指令访问违例")

    if faults:
        print(f"\n  可能原因: {', '.join(faults)}")
    else:
        print("\n  无明确CFSR标志，可能是软件触发的HardFault")

if __name__ == "__main__":
    hardfault_diagnose()
```

### 12.3 自动烧录 + 验证

```bash
#!/bin/bash
# flash_and_verify.sh - 烧录并验证固件

DEVICE_IP="192.168.1.100"
BIN_FILE="$1"

if [ ! -f "$BIN_FILE" ]; then
    echo "用法: $0 <firmware.bin>"
    exit 1
fi

SIZE=$(stat -c%s "$BIN_FILE")
echo "固件: $BIN_FILE ($SIZE bytes)"

# 上传
scp "$BIN_FILE" "root@${DEVICE_IP}:/mnt/UDISK/firmware.bin"

# 烧录
curl -s -X POST "http://${DEVICE_IP}:8080/api/v1/commands" \
  -H "Content-Type: application/json" \
  -d "{\"command\": \"flash_erase\", \"params\": {\"address\": \"0x08000000\", \"size\": $(( (SIZE / 4096 + 1) * 4096 ))}}"

curl -s -X POST "http://${DEVICE_IP}:8080/api/v1/commands" \
  -H "Content-Type: application/json" \
  -d "{\"command\": \"flash_write\", \"params\": {\"address\": \"0x08000000\", \"filepath\": \"/mnt/UDISK/firmware.bin\"}}"

# 验证: 从Flash读回并与本地文件比对
curl -s -X POST "http://${DEVICE_IP}:8080/api/v1/commands" \
  -H "Content-Type: application/json" \
  -d "{\"command\": \"dump_image\", \"params\": {\"address\": \"0x08000000\", \"size\": $SIZE, \"filepath\": \"/mnt/UDISK/verify.bin\"}}" > /dev/null

scp "root@${DEVICE_IP}:/mnt/UDISK/verify.bin" /tmp/verify.bin

if diff <(xxd "$BIN_FILE") <(xxd /tmp/verify.bin); then
    echo "✅ 烧录验证通过！"
else
    echo "❌ 验证失败，数据不一致！"
fi
```

---

## 13. 故障排查

### 13.1 设备无响应

| 症状 | 检查 | 解决 |
|------|------|------|
| PWR灯不亮 | Type-C线/电源 | 换线或检查USB口供电 |
| ADB找不到设备 | `adb devices` 为空 | 重插USB线，检查驱动 |
| 只有PWR灯亮 | 系统启动卡住 | 按复位键或重新上电 |

### 13.2 WiFi 连不上

```bash
# 查看WiFi状态
wpa_cli -i wlan0 status

# 扫描可用网络
wpa_cli -i wlan0 scan
wpa_cli -i wlan0 scan_results

# 手动连接
wpa_cli -i wlan0 add_network
wpa_cli -i wlan0 set_network 0 ssid '"你的WiFi名"'
wpa_cli -i wlan0 set_network 0 psk '"密码"'
wpa_cli -i wlan0 enable_network 0
```

### 13.3 连不上目标芯片

```bash
# 1. 检查ailink服务
ps | grep ailink        # 确认进程在运行

# 2. 检查API端口
netstat -tlnp | grep 8080   # 确认8080在监听

# 3. 检查openocd_cmd配置
cat /etc/ailink/openocd_cmd  # 确认目标芯片配置正确

# 4. 检查接线
# SWDIO ↔ 目标板 SWDIO
# SWCLK ↔ 目标板 SWCLK
# GND  ↔ 目标板 GND

# 5. 检查电平匹配
# 拨码开关电压 = 目标芯片工作电压

# 6. 手动测试OpenOCD
openocd -f interface/ch347.cfg -f target/stm32f1x.cfg -d
# 看日志中的错误信息
```

### 13.4 根分区空间不足

```bash
# 查看磁盘使用
df -h

# 清理临时文件
rm -rf /tmp/*
rm -rf /run/*

# 清理日志
dmesg -c > /dev/null

# 固件和日志放到UDISK
mv *.bin *.log /mnt/UDISK/
```

### 13.5 ailink API 返回 404

```bash
# 检查进程
ps | grep ailink

# 重启ailink
killall ailink
ailink -b 0.0.0.0 -p 8080 -d &

# 查看日志
ailink -b 0.0.0.0 -p 8080 -d 2>&1 | tail -20
```

---

## 附录A: 文件结构

```
/usr/bin/ailink              ← AI调试服务器主程序
/usr/bin/openocd             ← OpenOCD 调试器
/etc/ailink/
  ├── ailink.conf            ← 服务器配置
  ├── openocd_cmd            ← OpenOCD启动命令
  └── plugins/
      ├── arm/
      │   ├── stm32f1/       ← STM32F1插件 (.json + .so)
      │   └── stm32f4/       ← STM32F4插件 (.json + .so)
      └── riscv/
          └── ch32v003/      ← CH32V003插件 (.json + .so)
/usr/share/openocd/scripts/
  ├── interface/ch347.cfg    ← CH347 接口配置
  └── target/                ← 各芯片目标配置
/etc/init.d/
  ├── S70launcher            ← QT界面启动
  ├── S99myinit              ← 自定义初始化
  └── init_start.sh          ← GPIO/LED/JTAG初始化
/mnt/UDISK/                  ← 用户数据分区 (29MB可用)
```

## 附录B: 网络端口一览

| 端口 | 服务 | 何时可用 |
|------|------|----------|
| 22 | SSH | 始终 |
| 8080 | ailink HTTP API | 始终 |
| 3333 | OpenOCD GDB | 连接目标后 |
| 5037 | ADB | 始终 |

## 附录C: 存储布局

| 分区 | 容量 | 可用 | 用途 |
|------|------|------|------|
| 根文件系统 `/` | 42.6 MB | ~4 MB | 系统文件（只读） |
| 用户数据 `/mnt/UDISK` | 31.0 MB | 29.4 MB | 固件/日志存放 |
| 临时 `/tmp` | 53.6 MB | ~53 MB | 临时文件（重启丢失） |

---

> **项目信息**: AixProbe 开源项目 | 作者: zangshichang/guiwuz | CSDN 搜索「AixProbe专栏」  
> **文档版本**: v1.0 | **更新日期**: 2026-06-08

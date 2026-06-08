# AixProbe 嵌入式AI远程调试器 — AI项目集成参考

> **设备**: Allwinner V3s / ARMv7 | **系统**: Buildroot 2019.02.1 / Linux 5.4.61  
> **连接**: ADB (USB) → 设备串号 `0402101560` | **IP**: 需WiFi连接后获取

---

## 1. 核心调试服务器 `ailink` v0.1.0

| 属性 | 值 |
|------|-----|
| 进程 | `ailink` (开机自启) |
| HTTP 端口 | **8080** |
| 配置目录 | `/etc/ailink/` |
| 主配置文件 | `/etc/ailink/ailink.conf` |
| OpenOCD 启动命令 | `/etc/ailink/openocd_cmd` |

### 1.1 启动方式

```bash
# HTTP REST API 模式（默认，已在运行）
ailink -b 0.0.0.0 -p 8080

# MCP stdio 模式（供 Claude Code / Trae 等AI客户端调用）
ailink --mcp-stdio
```

### 1.2 MCP 集成命令（在AI客户端配置）

```json
{
  "mcpServers": {
    "aixprobe": {
      "command": "ssh",
      "args": ["root@<设备IP>", "/usr/bin/ailink", "--mcp-stdio"]
    }
  }
}
```

---

## 2. REST API 接口

基地址: `http://<设备IP>:8080`

### 2.1 系统状态

```
GET /api/v1/system/status
```

**响应示例**:
```json
{
  "version": "0.1.0",
  "uptime": 1111,
  "memory_total_kb": 109828,
  "memory_free_kb": 46168,
  "session_active": true,
  "session_id": "sess_1109",
  "openocd_running": true,
  "openocd_cmd": "openocd -f interface/ch347.cfg -f target/stm32f1x.cfg ..."
}
```

### 2.2 会话管理

```bash
# 连接目标MCU（启动OpenOCD）
POST /api/v1/session/connect
Body: {}  # 使用 /etc/ailink/openocd_cmd 中的配置

# 断开连接（停止OpenOCD）
DELETE /api/v1/session/
```

### 2.3 调试命令

```
GET  /api/v1/commands          → 获取所有可用命令列表
POST /api/v1/commands          → 执行调试命令
```

**可用命令列表** (17个):

```json
[
  "system_status",
  "connect",
  "disconnect",
  "halt",
  "resume",
  "step",
  "reset",
  "memory_read",
  "memory_write",
  "register_read",
  "register_write",
  "breakpoint_set",
  "breakpoint_remove",
  "breakpoint_list",
  "flash_write",
  "flash_erase",
  "dump_image",
  "raw_command"
]
```

### 2.4 固件上传

```
POST /api/v1/upload
Content-Type: multipart/form-data
```

### 2.5 串口通道

```
POST /api/v1/channel/uart/open   → 打开串口
POST /api/v1/channel/uart/close  → 关闭串口
POST /api/v1/channel/uart/send   → 发送数据
GET  /api/v1/channel/uart/read   → 读取数据
```

---

## 3. MCP 工具详细说明

以下工具通过 MCP 协议（`tools/list` / `tools/call`）暴露给 AI 客户端。

### 3.1 连接控制

| 工具 | 参数 | 说明 |
|------|------|------|
| `connect` | 无（使用配置文件） | 通过OpenOCD连接目标MCU |
| `disconnect` | 无 | 断开连接并停止OpenOCD |

### 3.2 执行控制

| 工具 | 参数 | 说明 |
|------|------|------|
| `halt` | 无 | 暂停CPU |
| `resume` | 无 | 恢复运行 |
| `step` | 无 | 单步执行 |
| `reset` | `type`: `"run"` / `"halt"` / `"init"` | 复位目标芯片 |

### 3.3 内存操作

| 工具 | 参数 | 说明 |
|------|------|------|
| `memory_read` | `address` (hex), `size` (bytes) | 读取内存 |
| `memory_write` | `address` (hex), `data` (hex bytes) | 写入内存 |
| `dump_image` | `address`, `size`, `filepath` | 导出内存镜像到文件 |

### 3.4 寄存器操作

| 工具 | 参数 | 说明 |
|------|------|------|
| `register_read` | `name` (如 `"pc"`, `"sp"`, `"r0"`) | 读取寄存器 |
| `register_write` | `name`, `value` | 写入寄存器 |

### 3.5 断点

| 工具 | 参数 | 说明 |
|------|------|------|
| `breakpoint_set` | `address` (hex), `type` (`"hw"`/`"sw"`) | 设置断点 |
| `breakpoint_remove` | `address` | 移除断点 |
| `breakpoint_list` | 无 | 列出所有断点 |

### 3.6 Flash 烧录

| 工具 | 参数 | 说明 |
|------|------|------|
| `flash_write` | `address`, `filepath` | 烧录固件到Flash |
| `flash_erase` | `address`, `size` | 擦除Flash区域 |

### 3.7 高级

| 工具 | 参数 | 说明 |
|------|------|------|
| `raw_command` | `cmd` (TCL字符串) | 发送原始OpenOCD TCL命令 |
| `system_status` | 无 | 获取设备状态 |

---

## 4. 支持的芯片插件

插件目录: `/etc/ailink/plugins/`

| 插件名 | 架构 | 芯片系列 | .so文件 |
|--------|------|----------|---------|
| `stm32f1` | ARM Cortex-M3 | STM32F1xx | `arm/stm32f1/stm32f1.so` |
| `stm32f4` | ARM Cortex-M4F | STM32F4xx | `arm/stm32f4/stm32f4.so` |
| `ch32v003` | RISC-V QINGKE-V2 | WCH CH32V003 | `riscv/ch32v003/ch32v003.so` |

### 插件JSON示例 (stm32f1.json)

```json
{
    "name": "stm32f1",
    "arch": "arm",
    "version": "1.0.0",
    "description": "STM32F1xx series (Cortex-M3)",
    "api_version": 1
}
```

---

## 5. OpenOCD 配置

### 5.1 当前配置 (`/etc/ailink/openocd_cmd`)

```bash
openocd -f interface/ch347.cfg -f target/stm32f1x.cfg -c "bindto 0.0.0.0" -c "gdb port 3333"
```

### 5.2 接口配置 (`/usr/share/openocd/scripts/interface/ch347.cfg`)

```tcl
adapter driver ch347
ch347 vid_pid 0x1a86 0x55de
adapter speed 15000
transport select swd
```

### 5.3 GDB 远程调试

OpenOCD 启动后在 **端口 3333** 提供 GDB 服务:
```bash
arm-none-eabi-gdb -ex "target remote <设备IP>:3333"
```

---

## 6. 硬件底层工具

### 6.1 I2C 工具

```bash
i2cdetect -y 0          # 扫描I2C总线设备
i2cdump  -y 0 0x50      # 导出设备寄存器
i2cget   -y 0 0x50 0x00 # 读取寄存器
i2cset   -y 0 0x50 0x00 0xff  # 写入寄存器
```

### 6.2 SPI 工具

```bash
spi-config --device=/dev/spidev1.1 --mode=0  # 配置SPI模式
spi-pipe  --device=/dev/spidev1.1 -s 1000000 -n 256  # 收发数据
spi_test  --device=/dev/spidev1.1 -s 1000000           # SPI测试
```

### 6.3 GPIO 控制

```bash
# sysfs接口
echo 134 > /sys/class/gpio/export        # 导出GPIO
echo out > /sys/class/gpio/gpio134/direction  # 设为输出
echo 1 > /sys/class/gpio/gpio134/value   # 输出高电平

# gpio_test工具
gpio_test -g PH1   # 读取IO状态
gpio_test -s PH1 1 # 设置IO功能
```

### 6.4 GPIO 引脚映射

| GPIO | 功能 | 说明 |
|------|------|------|
| GPIO128 | JTAG_RST | JTAG复位信号 |
| GPIO133 | LED1 | 自定义LED1 |
| GPIO134 | LED2 | 自定义LED2 |
| GPIO139 | USER_KEY | 用户按键（输入） |

### 6.5 串口终端

```bash
minicom -D /dev/ttyS0 -b 115200  # 打开串口终端
```

### 6.6 CAN 总线工具

```bash
cansend   can0 123#DEADBEEF       # 发送CAN帧
candump   can0                     # 监听CAN总线
cansniffer can0                    # 交互式CAN监控
canbusload can0@500000             # 总线负载监控
```

### 6.7 闪存工具

```bash
flash_erase /dev/mtd0 0 0          # 擦除Flash
nanddump  /dev/mtd0                # 导出NAND内容
nandwrite /dev/mtd0 firmware.bin   # 写入NAND
mtd_debug info /dev/mtd0           # MTD信息
```

### 6.8 系统诊断

```bash
cpu_monitor -s 500     # CPU频率/使用率/温度 (每500ms)
memtester 32M 1        # 内存压力测试 (测试32MB, 1轮)
top                    # 进程监控
free                   # 内存概况
dmesg                  # 内核日志
```

---

## 7. 存储布局

| 分区 | 总容量 | 可用 | 挂载点 | 说明 |
|------|--------|------|--------|------|
| ubi0_5 | 42.6 MB | ~4 MB | `/` | 根文件系统（只读） |
| UDISK | 31.0 MB | 29.4 MB | `/mnt/UDISK` | **用户数据区（可写）** |
| tmpfs | 53.6 MB | ~53 MB | `/run`, `/tmp` | 临时文件系统 |

> ⚠️ 固件文件、日志等请放到 `/mnt/UDISK/`，根分区仅剩约4MB。

---

## 8. 网络端口

| 端口 | 服务 | 说明 |
|------|------|------|
| 22 | SSH | 远程登录 |
| 8080 | ailink HTTP API | AI调试REST接口 |
| 3333 | OpenOCD GDB | GDB远程调试（连接目标后开启） |
| 5037 | ADB | Android Debug Bridge |

---

## 9. AI项目集成示例

### 9.1 查询设备状态 (curl/wget)

```bash
# PC端
curl http://<设备IP>:8080/api/v1/system/status

# 或通过ADB
adb shell wget -qO- http://localhost:8080/api/v1/system/status
```

### 9.2 连接目标芯片并读取寄存器 (Python)

```python
import requests

BASE = "http://<设备IP>:8080"

# 连接
r = requests.post(f"{BASE}/api/v1/session/connect", json={})
session = r.json()
print(f"已连接: {session['session_id']}")

# 暂停CPU
requests.post(f"{BASE}/api/v1/commands", json={
    "command": "halt"
})

# 读PC寄存器
r = requests.post(f"{BASE}/api/v1/commands", json={
    "command": "register_read",
    "params": {"name": "pc"}
})
print(f"PC = {r.json()}")

# 读内存
r = requests.post(f"{BASE}/api/v1/commands", json={
    "command": "memory_read",
    "params": {"address": "0x08000000", "size": 256}
})
print(f"Flash前256字节: {r.json()}")

# 断开
requests.delete(f"{BASE}/api/v1/session/")
```

### 9.3 MCP模式 (Claude Code配置)

在项目 `.claude/settings.json` 中添加:
```json
{
  "mcpServers": {
    "aixprobe": {
      "command": "ssh",
      "args": [
        "root@192.168.x.x",
        "/usr/bin/ailink",
        "--mcp-stdio"
      ]
    }
  }
}
```

### 9.4 烧录固件

```bash
# 通过API上传
curl -X POST http://<设备IP>:8080/api/v1/upload \
  -F "file=@firmware.bin"

# 或直接scp到UDISK然后flash_write命令烧录
scp firmware.bin root@<设备IP>:/mnt/UDISK/
```

### 9.5 HardFault 诊断流程

```
1. halt                              → 暂停CPU
2. register_read name="pc"           → 读取异常PC
3. register_read name="lr"           → 读取链接寄存器
4. register_read name="sp"           → 读取栈指针
5. memory_read address=SP size=64    → 读取栈帧
6. register_read name="cfsr"         → 读取Configurable Fault Status Register
7. register_read name="hfsr"         → 读取HardFault Status Register
8. raw_command cmd="arm semihosting" → 可选：检查semihosting状态
```

---

## 10. 故障排查

| 问题 | 检查方法 |
|------|----------|
| WiFi未连接 | `ip addr` 查看 wlan0 是否UP；`wpa_cli status` 查看连接状态 |
| OpenOCD启动失败 | `ps \| grep openocd`；检查 `/etc/ailink/openocd_cmd` |
| API无响应 | `netstat -tlnp \| grep 8080` 确认 ailink 在监听 |
| 芯片连接失败 | 检查目标板接线、SWD速率、电平匹配拨码开关 |
| 根分区空间不足 | `df -h`；清理 `/tmp` 或移动文件到 `/mnt/UDISK/` |

---

## 11. 硬件接口速查

| 接口 | 功能 |
|------|------|
| ① 拨码开关 | IO电平选择 (3.3V / 2.5V / 1.8V / 1.2V) |
| ② 10Pin JTAG/SWD | 核心调试接口 |
| ③ 双路串口 | 串口桥接 |
| ④ 自定义按键 | GPIO139, 可编程 |
| ⑤ 4路 LED | 电源/就绪 + 2路自定义(GPIO133/134) |
| ⑥ USB Host | 外接 J-Link/ST-Link 桥接 |
| ⑦ USB CH347F | 直连电脑，多协议转换 |
| ⑧ ADB接口 | Type-C，调试+供电 |
| ⑨ 12V电源 | 外部独立供电 |

---

> **项目地址**: CSDN 搜索「AixProbe专栏」| 作者: zangshichang/guiwuz  
> **更新时间**: 2026-06-07

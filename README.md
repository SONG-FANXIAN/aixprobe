# AixProbe 嵌入式AI远程调试器

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-ARMv7%20Linux-orange)
![Version](https://img.shields.io/badge/version-0.1.0-green)

首个开源 **嵌入式AI远程调试器**，通过 HTTP/MCP 协议让 AI（Claude Code 等）直接操作硬件，实现远程烧录、在线调试、AI 故障诊断。

```
你的PC/AI  ──HTTP/MCP──→  AixProbe  ──SWD/JTAG──→  目标芯片
 (任何地方)    Internet     arm-linux     CH347F      STM32/...
```

## 🚀 快速开始

### 1. 连接设备

```bash
# USB 连接 (Type-C)
adb devices          # 确认设备在线
adb shell            # 登录设备
```

### 2. 连接目标芯片

```bash
curl -X POST http://设备IP:8080/api/v1/session/connect \
  -H "Content-Type: application/json" -d '{}'
```

### 3. 查看状态

```bash
curl http://设备IP:8080/api/v1/system/status
```

### 4. 暂停 CPU + 读寄存器

```bash
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"halt"}'

curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"register_read","params":{"name":"pc"}}'
```

### 5. 烧录固件

```bash
# 推送固件
scp firmware.bin root@设备IP:/mnt/UDISK/

# 烧录
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"flash_write","params":{"address":"0x08000000","filepath":"/mnt/UDISK/firmware.bin"}}'

# 复位运行
curl -X POST http://设备IP:8080/api/v1/commands \
  -H "Content-Type: application/json" \
  -d '{"command":"reset","params":{"type":"run"}}'
```

## 🤖 AI 调试 (Claude Code MCP)

在 `.claude/settings.json` 中添加：

```json
{
  "mcpServers": {
    "aixprobe": {
      "command": "ssh",
      "args": ["root@设备IP", "/usr/bin/ailink", "--mcp-stdio"]
    }
  }
}
```

然后在 Claude Code 中自然对话：

> "连接目标芯片，读取 PC 寄存器和栈指针，帮我诊断 HardFault 的原因"

## 📡 远程调试

三种远程方案：

| 方案 | 成本 | 难度 | 适用 |
|------|------|------|------|
| 路由器端口转发 | 免费 | ⭐ | 有路由器权限 |
| n3n P2P VPN | VPS ~30元/月 | ⭐⭐ | 无公网IP |
| 4G + n3n | 4G模块 + VPS | ⭐⭐⭐ | 无WiFi环境 |

详见文档目录。

## 🛠️ 17个调试命令

| 类别 | 命令 | 说明 |
|------|------|------|
| 连接 | `connect` `disconnect` | 连接/断开目标MCU |
| 执行 | `halt` `resume` `step` `reset` | CPU控制 |
| 寄存器 | `register_read` `register_write` | 读写寄存器 |
| 内存 | `memory_read` `memory_write` | 读写内存 |
| 断点 | `breakpoint_set` `breakpoint_remove` `breakpoint_list` | 断点管理 |
| Flash | `flash_write` `flash_erase` `dump_image` | 烧录/导出 |
| 高级 | `raw_command` `system_status` | 原始命令/状态 |

## 📂 目录结构

```
aixprobe/
├── README.md                        ← 项目主页
├── AixProbe_完整使用教程.md          ← 本地USB入门教程
├── AixProbe_调试器参考文档.md        ← API/工具速查手册
├── 公网远程控制教程.md               ← 路由器端口转发（零成本）
├── 多人远程协作指南.md               ← 别人拿设备，你远程控
├── n3n远程部署指南.md                ← n3n VPN方案
├── firmware/                         ← 固件存放目录
│   └── README.md
└── scripts/                          ← 自动化脚本
    ├── flash_stm32.py                ← 一键烧录
    ├── deploy_vps_supernode.sh       ← VPS超节点部署
    ├── deploy_aixprobe_n3n.sh        ← AixProbe n3n部署
    └── deploy_pc_n3n.sh              ← PC n3n部署
```

## 💡 硬件接口

| 接口 | 功能 |
|------|------|
| ① 拨码开关 | IO电平切换 (3.3V/2.5V/1.8V/1.2V) |
| ② 10Pin SWD | 核心调试接口 |
| ③ 双路串口 | 串口桥接 |
| ④ 自定义按键 | 用户可编程 |
| ⑤ 4路LED | 状态指示 |
| ⑥ USB Host | 桥接J-Link/ST-Link |
| ⑦ USB CH347F | 多协议转换 |
| ⑧ ADB接口 | 调试+供电 |

## 🔧 技术栈

- **芯片**: Allwinner V3s (ARMv7, 1.2GHz)
- **系统**: Buildroot 2019.02.1 / Linux 5.4.61
- **调试引擎**: OpenOCD
- **调试接口**: CH347F (SWD/JTAG/SPI/I2C/UART)
- **AI服务器**: ailink v0.1.0 (C语言, HTTP + MCP)
- **插件架构**: .so 动态库 (支持 STM32F1/F4, CH32V003)

## 📖 文档索引

| 文档 | 内容 |
|------|------|
| [完整使用教程](AixProbe_完整使用教程.md) | 从开箱到烧录调试的全流程 |
| [API参考文档](AixProbe_调试器参考文档.md) | REST API 和 MCP 工具详细说明 |
| [公网远程控制](公网远程控制教程.md) | 路由器端口转发实现远程调试 |
| [多人远程协作](多人远程协作指南.md) | 一人拿设备、一人远程控 |
| [n3n VPN部署](n3n远程部署指南.md) | P2P VPN 任意地点访问 |

## 🤝 贡献

欢迎提交 Issue 和 Pull Request。

## 📄 License

MIT License

---

> **作者**: zangshichang/guiwuz | 项目地址: Gitee 搜索「AixProbe」

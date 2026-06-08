#!/usr/bin/env python3
"""
AixProbe 一键烧录脚本 (支持本地ADB和远程n3n)
用法:
  本地:  python flash_stm32.py firmware.bin
  远程:  python flash_stm32.py firmware.bin --host 10.0.0.2
"""

import subprocess
import sys
import argparse
import requests
import os

# ============ 配置 ============
DEFAULT_HOST = "localhost"       # 本地通过 ADB forward
DEFAULT_PORT = 8080
FLASH_ADDR   = "0x08000000"     # STM32F1 Flash 起始地址
FLASH_SIZE   = 131072           # 128KB（根据你的芯片调整）
UDISK_PATH   = "/mnt/UDISK/firmware.bin"
CHIP_TYPE    = "stm32f1"        # 芯片类型
# =============================


def green(s):  return f"\033[0;32m{s}\033[0m"
def yellow(s): return f"\033[1;33m{s}\033[0m"
def red(s):    return f"\033[0;31m{s}\033[0m"


def push_firmware(host, firmware_path):
    """推送固件到 AixProbe"""
    print(yellow(f"[1/6] 推送固件: {firmware_path}"))

    if host in ("localhost", "127.0.0.1"):
        # 本地 ADB 模式
        result = subprocess.run(
            ["adb", "push", firmware_path, UDISK_PATH],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(red(f"  ADB push 失败: {result.stderr}"))
            sys.exit(1)
        print(green(f"  ✓ 已推送到 {UDISK_PATH}"))
    else:
        # 远程 SCP 模式
        result = subprocess.run(
            ["scp", firmware_path, f"root@{host}:{UDISK_PATH}"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(red(f"  SCP 失败: {result.stderr}"))
            print(yellow("  提示: 确认 n3n 已连接 (ping 10.0.0.2)"))
            sys.exit(1)
        print(green(f"  ✓ 已推送到 root@{host}:{UDISK_PATH}"))


def cmd(host, command, params=None, timeout=30):
    """向 AixProbe 发送调试命令"""
    body = {"command": command}
    if params:
        body["params"] = params

    try:
        r = requests.post(
            f"http://{host}:{DEFAULT_PORT}/api/v1/commands",
            json=body,
            timeout=timeout
        )
        return r.json()
    except requests.exceptions.ConnectionError:
        print(red(f"  连接失败！AixProbe ({host}:{DEFAULT_PORT}) 不可达"))
        if host in ("localhost", "127.0.0.1"):
            print(yellow("  检查: adb devices 是否能看到设备"))
        else:
            print(yellow("  检查: n3n 是否已连接，ping 10.0.0.2"))
        sys.exit(1)
    except requests.exceptions.Timeout:
        print(red(f"  命令超时 ({timeout}s)"))
        return {"error": "timeout"}


def main():
    parser = argparse.ArgumentParser(description="AixProbe STM32F1 一键烧录")
    parser.add_argument("firmware", help="固件 .bin 文件路径")
    parser.add_argument("--host", default=DEFAULT_HOST,
                        help=f"AixProbe IP (默认: {DEFAULT_HOST}, 远程用 10.0.0.2)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"API 端口 (默认: {DEFAULT_PORT})")
    parser.add_argument("--addr", default=FLASH_ADDR,
                        help=f"Flash 起始地址 (默认: {FLASH_ADDR})")
    parser.add_argument("--size", type=int, default=FLASH_SIZE,
                        help=f"擦除大小 bytes (默认: {FLASH_SIZE})")
    parser.add_argument("--no-verify", action="store_true",
                        help="跳过验证")
    parser.add_argument("--no-run", action="store_true",
                        help="烧录后不运行")
    args = parser.parse_args()

    # 检查固件文件
    if not os.path.isfile(args.firmware):
        print(red(f"固件文件不存在: {args.firmware}"))
        sys.exit(1)

    fw_size = os.path.getsize(args.firmware)
    print("=" * 50)
    print(f"  AixProbe {CHIP_TYPE.upper()} 一键烧录")
    print("=" * 50)
    print(f"  固件:     {args.firmware} ({fw_size} bytes)")
    print(f"  目标:     {args.host}:{args.port}")
    print(f"  Flash:    {args.addr}")
    print(f"  擦除:     {args.size} bytes ({args.size // 1024} KB)")
    print("=" * 50)
    print()

    # 1. 推送固件
    push_firmware(args.host, args.firmware)

    # 2. 连接目标芯片
    print(yellow("[2/6] 连接目标芯片..."))
    r = requests.post(
        f"http://{args.host}:{DEFAULT_PORT}/api/v1/session/connect",
        json={}, timeout=10
    )
    session = r.json()
    print(green(f"  ✓ 会话: {session.get('session_id', '?')}"))
    print(f"     OpenOCD: {session.get('openocd_cmd', '?')}")

    # 3. 暂停 CPU
    print(yellow("[3/6] 暂停 CPU..."))
    result = cmd(args.host, "halt")
    print(green(f"  ✓ CPU 已暂停"))

    # 4. 擦除 Flash
    print(yellow(f"[4/6] 擦除 Flash ({args.addr}, {args.size} bytes)..."))
    result = cmd(args.host, "flash_erase",
                 {"address": args.addr, "size": args.size},
                 timeout=60)
    if "error" in str(result):
        print(yellow(f"  警告: {result}"))
    else:
        print(green(f"  ✓ Flash 已擦除"))

    # 5. 烧录
    print(yellow(f"[5/6] 烧录固件到 {args.addr}..."))
    result = cmd(args.host, "flash_write",
                 {"address": args.addr, "filepath": UDISK_PATH},
                 timeout=120)
    if "error" in str(result):
        print(red(f"  烧录失败: {result}"))
        sys.exit(1)
    print(green(f"  ✓ 烧录完成"))

    # 6. 验证 + 运行
    if not args.no_verify:
        print(yellow("  验证: 读回 Flash 前 256 字节..."))
        result = cmd(args.host, "memory_read",
                     {"address": args.addr, "size": 256})
        print(green(f"  ✓ 验证通过") if "error" not in str(result) else yellow("  ! 验证异常"))

    if not args.no_run:
        print(yellow("[6/6] 复位运行..."))
        result = cmd(args.host, "reset", {"type": "run"})
        print(green(f"  ✓ CPU 已复位运行"))

    print()
    print("=" * 50)
    print(green("  ✅ 烧录完成！目标芯片正在运行"))
    print("=" * 50)


if __name__ == "__main__":
    main()

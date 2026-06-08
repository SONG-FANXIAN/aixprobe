# 固件存放目录

把编译好的 `.bin` 固件文件放在这里，然后通过 ADB 推送到 AixProbe：

```bash
# 推送固件
adb push ./firmware/你的固件.bin /mnt/UDISK/firmware.bin

# 烧录（进入 adb shell 后）
wget -qO- --post-data='{"command":"halt"}' --header="Content-Type: application/json" http://localhost:8080/api/v1/commands
wget -qO- --post-data='{"command":"flash_erase","params":{"address":"0x08000000","size":131072}}' --header="Content-Type: application/json" http://localhost:8080/api/v1/commands
wget -qO- --post-data='{"command":"flash_write","params":{"address":"0x08000000","filepath":"/mnt/UDISK/firmware.bin"}}' --header="Content-Type: application/json" http://localhost:8080/api/v1/commands
wget -qO- --post-data='{"command":"reset","params":{"type":"run"}}' --header="Content-Type: application/json" http://localhost:8080/api/v1/commands
```

或使用 Python 脚本: `python flash_stm32.py ./firmware/你的固件.bin`

# Raspberry Pi 5 CPU Overclock
A CPU overclocking and stress testing script for Raspberry Pi 5
[简体中文](#简体中文) · [English](#english)

## 简体中文

树莓派 5 的交互式 CPU 超频和压力测试工具。脚本启动时可选简体中文或英文，支持设置 CPU 目标频率、查看实时状态、运行压测和移除超频设置。

**超频可能导致无法启动、系统崩溃或数据损坏。** 请先备份重要数据，再逐档测试。CPU 运行在 **2 GHz 及以上**时，建议配备散热片或外置风扇。2.85 GHz 和 2.9 GHz 为实验档，需要额外输入目标频率确认。压测通过也只能说明设备在本次测试条件下完成了测试。

### 运行环境

- 兼容性测试仅覆盖树莓派 5 上的 Ubuntu 24.04 LTS ARM64 和 Raspberry Pi OS。
- Bash 5+，使用 `sudo` 运行。启动分区须挂载到 `/boot/firmware`，且 `config.txt` 可读写。
- 压力测试需要 `stress-ng`。读取 PMIC 功率和输入电压需要 `vcgencmd` 返回有效的 ADC 数据。

### 快速开始

在 GitHub 打开 [pi5-cpu-overclock.sh](./pi5-cpu-overclock.sh)，将 Raw 版本保存到树莓派。进入文件所在目录后运行：

```bash
sudo bash pi5-cpu-overclock.sh
```

启动时按 `1` 选简体中文（默认），按 `2` 选 English。如需使用压测功能，先安装依赖：

```bash
sudo apt update
sudo apt install stress-ng
```

### 菜单

| 选项 | 操作 |
| --- | --- |
| `1`–`4` | 将 CPU 目标频率设为 2.4、2.6、2.7 或 2.8 GHz |
| `5` | 查看 CPU 频率和温度 |
| `6` | 运行 1–120 分钟压测，输入 `YES` 确认 |
| `7` | 移除脚本写入的超频设置 |
| `8`、`9` | 实验档 2.85 或 2.9 GHz，需额外确认 |
| `10` | 卸载当前脚本 |
| `0` | 退出 |

菜单中的频率是 `arm_freq` 目标值，重启后生效。实际频率会随负载、温度和固件策略变化。压测时，CPU 温度达到 80 °C、无法读取温度，或测得 5 V 输入低于 4.8 V，脚本会停止测试。输入电压保护依赖有效的 PMIC 读数。PMIC 功率为所测供电轨的估算值。

按 `Ctrl+C` 可中断压测。脚本会在正常结束、报错退出或处理到中断信号时清理本次生成的临时文件。

### 回滚与卸载

脚本在 `/boot/firmware/config.txt` 的专用区块中管理 `arm_freq`。每次改写前会在 `/var/backups/pi5-cpu-overclock/` 保存原配置，并显示备份路径。

- **撤销超频**：选 `7`，确认后重启。脚本只移除自己管理的区块，频率由剩余的固件配置决定。
- **无法启动**：在另一台电脑上打开启动介质的启动分区，编辑 `config.txt`，删除 `PI5_CPU_OVERCLOCK_MANAGED_START` 与 `PI5_CPU_OVERCLOCK_MANAGED_END` 之间的区块，连同两条标记行一起删除。
- **卸载**：从实际脚本文件运行并选 `10`。确认后，脚本移除管理区块并删除当前运行的脚本文件。配置备份仍可用于恢复。

### 开发与测试

[test-pi5-cpu-overclock.sh](./test-pi5-cpu-overclock.sh) 是开发用的回归测试。它使用临时配置和模拟硬件读数，覆盖语言选择、备份、写入失败、压测日志清理、回滚与卸载。

```bash
bash -n pi5-cpu-overclock.sh
bash test-pi5-cpu-overclock.sh
```

## English

An interactive CPU overclocking and stress-test tool for Raspberry Pi 5. Choose Simplified Chinese or English at startup, then set a CPU frequency target, inspect live readings, run a stress test, or roll back the managed settings.

**Overclocking can cause boot failures, crashes, or data loss.** Back up important data and test one step at a time. Use a heatsink or an external fan when running the CPU at **2 GHz or higher**. The 2.85 and 2.9 GHz experimental presets require you to type the target frequency for confirmation. A completed stress test reflects the conditions of that run.

### Requirements

- Compatibility testing covers Raspberry Pi 5 only, running Ubuntu 24.04 LTS ARM64 or Raspberry Pi OS.
- Bash 5+ and `sudo` access. The boot partition must be mounted at `/boot/firmware` with a readable and writable `config.txt`.
- Stress testing requires `stress-ng`. PMIC power and input-voltage readings require valid ADC data from `vcgencmd`.

### Quick start

Open [pi5-cpu-overclock.sh](./pi5-cpu-overclock.sh) on GitHub and save the Raw file to your Pi. Run this command from the folder containing the script:

```bash
sudo bash pi5-cpu-overclock.sh
```

Choose `2` for English or `1` for Simplified Chinese (the default). To use the stress-test option, install its dependency:

```bash
sudo apt update
sudo apt install stress-ng
```

### Menu

| Option | Action |
| --- | --- |
| `1`–`4` | Set the CPU target to 2.4, 2.6, 2.7, or 2.8 GHz |
| `5` | View CPU frequency and temperature |
| `6` | Run a 1–120 minute stress test. Type `YES` to confirm |
| `7` | Remove the script-managed overclock settings |
| `8`, `9` | Use the 2.85 or 2.9 GHz experimental preset with extra confirmation |
| `10` | Uninstall the current script |
| `0` | Exit |

The menu sets the `arm_freq` target, which takes effect after a reboot. Actual CPU frequency varies with load, temperature, and firmware behavior. A stress test stops at 80 °C, on a temperature read failure, or when the measured 5 V input drops below 4.8 V. The voltage cutoff requires a valid PMIC reading. Reported PMIC power estimates cover the measured rails.

Press `Ctrl+C` to interrupt a test. The script cleans up its temporary files on completion, error exit, or a handled interruption.

### Rollback and uninstall

The script manages `arm_freq` in a dedicated block in `/boot/firmware/config.txt`. Before each rewrite, it saves a copy under `/var/backups/pi5-cpu-overclock/` and prints its path.

- **Roll back**: Choose `7`, confirm, then reboot. Removing the managed block lets the remaining firmware settings determine the CPU frequency.
- **Recover from a boot failure**: Open the boot partition on another computer. In `config.txt`, remove the block between `PI5_CPU_OVERCLOCK_MANAGED_START` and `PI5_CPU_OVERCLOCK_MANAGED_END`, including both marker lines.
- **Uninstall**: Run the script file directly and choose `10`. On confirmation, it removes the managed block and deletes the running script file. The configuration backups are available for recovery.

### Development and tests

[test-pi5-cpu-overclock.sh](./test-pi5-cpu-overclock.sh) uses temporary config files and simulated hardware readings to check language selection, backups, write failures, stress-log cleanup, rollback, and uninstall.

```bash
bash -n pi5-cpu-overclock.sh
bash test-pi5-cpu-overclock.sh
```

## 许可证 / License

GPL-3.0

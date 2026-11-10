# Raspberry Pi 5 CPU Overclock

CPU frequency control and live stress-test monitoring for Raspberry Pi 5.

[English](#english) · [简体中文](#简体中文) · [Releases](https://github.com/hefan230/pi5-cpu-overclock/releases)

## English

[Requirements](#requirements) · [Setup](#setup) · [Menu](#menu) · [Stress-test safeguards](#stress-test-safeguards) · [Rollback and uninstall](#rollback-and-uninstall)

An interactive CPU overclocking and stress-test tool for Raspberry Pi 5. Choose Simplified Chinese or English at startup, then set a CPU frequency target, inspect live readings, run a stress test, or roll back the managed settings.

> **Overclocking can cause boot failures, crashes, or data loss.** Back up important data and test one step at a time. The **3.0 GHz** preset is experimental, and **3.4 GHz** is the highest custom target the script accepts. Boot and stability depend on the hardware, firmware, and cooling.
>
> **Cooling** · Use a heatsink or an external fan at **2 GHz or higher**. The script recommends a fan at targets of **2.6 GHz or higher**.

### Requirements

- Compatibility testing covers Raspberry Pi 5 only, running Ubuntu 24.04 LTS ARM64 or Raspberry Pi OS.
- Bash 5+ and `sudo` access. The boot partition must be mounted at `/boot/firmware` with a readable and writable `config.txt`.
- Stress testing requires `stress-ng`. PMIC power and input-voltage readings require valid ADC data from `vcgencmd`.

### Setup

Run these commands in a terminal or SSH session on the Pi.

#### 1. Install the stress-test dependency

```bash
sudo apt update
sudo apt install stress-ng
```

#### 2. Get and run the script

Choose either method. When downloading from [GitHub Releases](https://github.com/hefan230/pi5-cpu-overclock/releases), select a tag that contains the menu described here. `v1.0` has the older menu. If you already have the updated script file, start at step 2 of Option B.

**Option A · Download from GitHub and run**

Paste the entire block into the Pi terminal and enter the release tag when prompted. The script starts after the download succeeds. If `curl` is missing, run `sudo apt install curl` first.

```bash
read -r -p 'Enter the updated release tag: ' release_tag &&
  [ -n "$release_tag" ] &&
  mkdir -p ~/pi5-cpu-overclock &&
  cd ~/pi5-cpu-overclock &&
  curl --fail --location --output pi5-cpu-overclock.sh \
    "https://raw.githubusercontent.com/hefan230/pi5-cpu-overclock/${release_tag}/pi5-cpu-overclock.sh" &&
  sudo bash ./pi5-cpu-overclock.sh
```

**Option B · Save the script manually and run it**

1. Open the matching GitHub release, download **Source code (zip)**, and extract `pi5-cpu-overclock.sh`. You can also open the main script's **Raw** view at that tag and save it under the same name.
2. Put the file in your home directory (`~`) on the Pi, then run these commands in the Pi terminal.

```bash
cd ~
sudo bash ./pi5-cpu-overclock.sh
```

Choose `2` for English or `1` for Simplified Chinese (the default). In the main menu, choose `5` to view CPU frequency and temperature or `6` to set up a stress test.

### Menu

| Option | Action |
| --- | --- |
| `1` | **2.4 GHz** preset |
| `2` | **2.6 GHz** preset |
| `3` | **2.8 GHz** preset |
| `4` | **3.0 GHz** experimental preset. Confirm twice |
| `5` | View CPU frequency and temperature |
| `6` | Run a 1–120 minute stress test. Enter the duration, then confirm with `y` or `Y` |
| `7` | Remove the script-managed overclock settings |
| `8` | Set a custom target from 1 to 3.4 GHz inclusive, with up to three decimal places. Enter `0` to cancel. Writing requires two confirmations |
| `10` | Uninstall the current script |
| `0` | Exit |

Each confirmation accepts a single `y` or `Y`. Press Enter or enter anything else to cancel. Custom targets use GHz. For example, entering `2.625` writes `arm_freq=2625`. Changes apply after reboot, and actual CPU frequency varies with load, temperature, and firmware behavior.

### Stress-test safeguards

A stress test stops at 80 °C, on a temperature read failure, or when the measured 5 V input drops below 4.8 V. The voltage cutoff requires a valid PMIC reading. Reported PMIC power estimates cover the measured rails.

Press `Ctrl+C` to interrupt a test. The script cleans up its temporary files on completion, error exit, or a handled interruption.

### Rollback and uninstall

The script manages `arm_freq` in a dedicated block in `/boot/firmware/config.txt`. Before each rewrite, it saves a copy under `/var/backups/pi5-cpu-overclock/` and prints its path.

- **Roll back**: Choose `7`, confirm, then reboot. Removing the managed block lets the remaining firmware settings determine the CPU frequency.
- **Recover from a boot failure**: Open the boot partition on another computer. In `config.txt`, remove the block between `PI5_CPU_OVERCLOCK_MANAGED_START` and `PI5_CPU_OVERCLOCK_MANAGED_END`, including both marker lines.
- **Uninstall**: Run the script file directly and choose `10`. On confirmation, it removes the managed block and deletes the running script file. The configuration backups are available for recovery.

### Development and tests

Use `test-pi5-cpu-overclock.sh` from the same release. It uses temporary config files and simulated hardware readings to check frequency bounds, both confirmations, backups, write failures, stress-log cleanup, rollback, and uninstall.

```bash
bash -n pi5-cpu-overclock.sh
bash test-pi5-cpu-overclock.sh
```

## 简体中文

[运行环境](#运行环境) · [部署步骤](#部署步骤) · [菜单](#菜单) · [压测保护](#压测保护) · [回滚与卸载](#回滚与卸载)

树莓派 5 的交互式 CPU 超频和压力测试工具。脚本启动时可选简体中文或英文，支持设置 CPU 目标频率、查看实时状态、运行压测和移除超频设置。

> **超频可能导致无法启动、系统崩溃或数据损坏。** 请先备份重要数据，再逐档测试。**3.0 GHz** 预设是实验档，**3.4 GHz** 是脚本接受的自定义目标上限。能否启动并稳定运行取决于硬件、固件和散热。
>
> **散热** · CPU 运行在 **2 GHz 及以上**时，建议配备散热片或外置风扇。目标频率为 **2.6 GHz 及以上**时，脚本会提示安装风扇。

### 运行环境

- 兼容性测试仅覆盖树莓派 5 上的 Ubuntu 24.04 LTS ARM64 和 Raspberry Pi OS。
- Bash 5+，使用 `sudo` 运行。启动分区须挂载到 `/boot/firmware`，且 `config.txt` 可读写。
- 压力测试需要 `stress-ng`。读取 PMIC 功率和输入电压需要 `vcgencmd` 返回有效的 ADC 数据。

### 部署步骤

在树莓派的终端或 SSH 会话中执行以下命令。

#### 1. 安装压力测试依赖

```bash
sudo apt update
sudo apt install stress-ng
```

#### 2. 获取并运行脚本

以下两种方式任选一种。通过 [GitHub Releases](https://github.com/hefan230/pi5-cpu-overclock/releases) 获取脚本时，请选择包含本版菜单的发布标签。`v1.0` 对应旧版菜单。如果手头已有新版脚本，直接从方式 B 的第 2 步开始。

**方式 A · 从 GitHub 下载并运行**

把下面整段命令复制到树莓派终端，按提示输入发布标签。下载成功后会自动运行脚本。如果系统缺少 `curl`，先执行 `sudo apt install curl`。

```bash
read -r -p '请输入新版发布标签：' release_tag &&
  [ -n "$release_tag" ] &&
  mkdir -p ~/pi5-cpu-overclock &&
  cd ~/pi5-cpu-overclock &&
  curl --fail --location --output pi5-cpu-overclock.sh \
    "https://raw.githubusercontent.com/hefan230/pi5-cpu-overclock/${release_tag}/pi5-cpu-overclock.sh" &&
  sudo bash ./pi5-cpu-overclock.sh
```

**方式 B · 手动保存后运行**

1. 在 GitHub Releases 打开对应发布版，下载 **Source code (zip)**，解压后取出 `pi5-cpu-overclock.sh`。也可以打开该标签下主脚本的 **Raw** 页面，将原文保存为同名文件。
2. 将文件放到树莓派当前登录用户的主目录（`~`），然后在树莓派终端运行下面的命令。

```bash
cd ~
sudo bash ./pi5-cpu-overclock.sh
```

启动时按 `1` 选简体中文（默认），按 `2` 选 English。进入主菜单后可按 `5` 查看 CPU 频率和温度，或按 `6` 开始设置压力测试。

### 菜单

| 选项 | 操作 |
| --- | --- |
| `1` | **2.4 GHz** 预设 |
| `2` | **2.6 GHz** 预设 |
| `3` | **2.8 GHz** 预设 |
| `4` | **3.0 GHz** 实验档，需确认两次 |
| `5` | 查看 CPU 频率和温度 |
| `6` | 运行 1–120 分钟压测。输入时长后，用 `y` 或 `Y` 确认启动 |
| `7` | 移除脚本写入的超频设置 |
| `8` | 自定义 1–3.4 GHz（含端点），最多三位小数。输入 `0` 取消，写入前需确认两次 |
| `10` | 卸载当前脚本 |
| `0` | 退出 |

每次确认均接受单字母 `y` 或 `Y`，直接回车或输入其他内容会取消。自定义频率以 GHz 输入，例如 `2.625`，对应写入 `arm_freq=2625`。配置重启后生效，实际频率会随负载、温度和固件策略变化。

### 压测保护

压测时，CPU 温度达到 80 °C、无法读取温度，或测得 5 V 输入低于 4.8 V，脚本会停止测试。输入电压保护依赖有效的 PMIC 读数。PMIC 功率为所测供电轨的估算值。

按 `Ctrl+C` 可中断压测。脚本会在正常结束、报错退出或处理到中断信号时清理本次生成的临时文件。

### 回滚与卸载

脚本在 `/boot/firmware/config.txt` 的专用区块中管理 `arm_freq`。每次改写前会在 `/var/backups/pi5-cpu-overclock/` 保存原配置，并显示备份路径。

- **撤销超频**：选 `7`，确认后重启。脚本只移除自己管理的区块，频率由剩余的固件配置决定。
- **无法启动**：在另一台电脑上打开启动介质的启动分区，编辑 `config.txt`，删除 `PI5_CPU_OVERCLOCK_MANAGED_START` 与 `PI5_CPU_OVERCLOCK_MANAGED_END` 之间的区块，连同两条标记行一起删除。
- **卸载**：从实际脚本文件运行并选 `10`。确认后，脚本移除管理区块并删除当前运行的脚本文件。配置备份仍可用于恢复。

### 开发与测试

同版本的 `test-pi5-cpu-overclock.sh` 使用临时配置和模拟硬件读数，覆盖频率边界、两次确认、备份、写入失败、压测日志清理、回滚与卸载。

```bash
bash -n pi5-cpu-overclock.sh
bash test-pi5-cpu-overclock.sh
```

## 许可证 / License

待定 / Pending.


GPL-3.0

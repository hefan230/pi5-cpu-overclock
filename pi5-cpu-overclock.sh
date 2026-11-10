#!/usr/bin/env bash
# Raspberry Pi 5 CPU overclock and stress monitor (Bash 5+).
# Targets Raspberry Pi OS (Bookworm and later) and Ubuntu 24.04 LTS ARM64 for Pi.
set -euo pipefail
set +m  # The background setsid process must not already be a process group leader.

readonly CONFIG='/boot/firmware/config.txt'
readonly BACKUP_DIR='/var/backups/pi5-cpu-overclock'
readonly LOCK_PATH='/run/pi5-cpu-overclock.lock'
readonly START_MARK='# >>> PI5_CPU_OVERCLOCK_MANAGED_START >>>'
readonly END_MARK='# <<< PI5_CPU_OVERCLOCK_MANAGED_END <<<'
readonly TEMP_LIMIT_MILLIC=80000
readonly MIN_INPUT_VOLTS=4.8
readonly MAX_STRESS_MINUTES=120

language=zh
red='\033[0;31m' green='\033[0;32m' yellow='\033[0;33m' cyan='\033[0;36m' reset='\033[0m'

print_message() {
  local color=$1 format=$2
  [[ "$language" == zh ]] || format=$3
  shift 3
  [[ -t 1 ]] || color=''
  printf '%b' "$color"
  # The format strings are literals supplied by this script. Values use separate arguments.
  # shellcheck disable=SC2059
  printf "$format" "$@"
  printf '%b' "${color:+$reset}"
}

say()  { print_message '' "$@"; printf '\n'; }
info() { print_message "$cyan" "$@"; printf '\n'; }
ok()   { print_message "$green" "$@"; printf '\n'; }
warn() { { print_message "$yellow" "$@"; printf '\n'; } >&2; }
die()  { { print_message "$red" '错误：' 'Error: '; say "$@"; } >&2; exit 1; }

prompt() {
  local reply_var=$1
  shift
  print_message '' "$@" >&2
  IFS= read -r "$reply_var"
}

choose_language() {
  local choice
  printf '%s\n' '请选择语言 / Choose a language' '  1) 简体中文' '  2) English'
  while prompt choice '请选择 / Select [1/2, 1]: ' '请选择 / Select [1/2, 1]: '; do
    case "$choice" in
      ''|1) language=zh; return 0 ;;
      2) language=en; return 0 ;;
      *) printf '%s\n' '请输入 1 或 2 / Enter 1 or 2.' >&2 ;;
    esac
  done
  return 1
}

confirm() {
  local answer
  prompt answer "$@" && [[ "$answer" == [yY] ]]
}

cancelled() { say '已取消。' 'Cancelled.'; }

check_platform() {
  (( EUID == 0 )) || die '请使用 sudo bash pi5-cpu-overclock.sh 运行。' \
    'Run this script with sudo bash pi5-cpu-overclock.sh.'
  local cmd model model_path='/proc/device-tree/model'
  for cmd in awk cat chmod cmp cp flock install mktemp mountpoint mv rm sleep sync timeout tr; do
    command -v "$cmd" >/dev/null 2>&1 || die '缺少必要命令：%s' 'Required command missing: %s' "$cmd"
  done
  if [[ ! -r "$model_path" ]]; then
    model_path='/sys/firmware/devicetree/base/model'
  fi
  model=$(tr -d '\0' 2>/dev/null < "$model_path") ||
    die '无法识别树莓派硬件型号。' 'Could not identify the Raspberry Pi model.'
  [[ "$model" == *'Raspberry Pi 5'* ]] ||
    die '当前设备不是 Raspberry Pi 5：%s' 'This device is not a Raspberry Pi 5: %s' "$model"
  mountpoint -q -- "${CONFIG%/*}" ||
    die '启动分区未挂载：%s' 'The boot partition is not mounted at %s.' "${CONFIG%/*}"
  [[ -f "$CONFIG" && ! -L "$CONFIG" && -r "$CONFIG" && -w "$CONFIG" ]] ||
    die '启动配置必须是可读写的普通文件：%s' 'The boot config must be a readable, writable regular file: %s' "$CONFIG"
}

# A shared parser keeps status, replacement and removal in agreement. Only the
# exact block layouts written by this script (including older versions) are owned.
managed_config() {
  local mode=$1 file=$2 freq=${3:-}
  awk -v mode="$mode" -v b="$START_MARK" -v e="$END_MARK" -v target="$freq" '
    {
      line=$0
      cr=sub(/\r$/, "", line)
      if (NR==1) eol=(cr ? "\r\n" : "\n")

      if (line==b) {
        if (seen++) exit 2
        state=1
      } else if (line==e) {
        if (state!=4) exit 2
        state=0
        after=1
      } else if (state) {
        if (state==1 && line=="[all]") state=2
        else if ((state==1 || state==2) && line=="[pi5]") state=3
        else if (state==3 && line ~ /^arm_freq=[0-9]+$/) {
          current=substr(line,10)
          state=4
        } else exit 2
      } else {
        # Removing a filter could change the meaning of settings that follow it.
        if (line=="[all]") after=0
        if (after && line !~ /^[[:space:]]*(#|$)/) exit 2
        if (mode=="rewrite") print
      }
    }
    END {
      if (state) exit 2
      if (mode=="inspect" && current!="") print current
      if (mode=="rewrite" && target!="") {
        if (eol=="") eol="\n"
        printf "%s%s[all]%s[pi5]%sarm_freq=%s%s%s%s", b,eol,eol,eol,target,eol,e,eol
      }
    }
  ' "$file"
}

config_error() {
  die '无法安全处理启动配置。请检查管理区块是否完整、唯一、只含脚本写入的内容，并在后续设置前用 [all] 重置筛选条件。' \
    'Could not safely process the boot config. Check that the managed block is intact, unique, and unmodified, and that any later settings start after an [all] reset.'
}

show_status() {
  local policy='/sys/devices/system/cpu/cpu0/cpufreq' k temp freq
  printf '\n'
  info '====== Raspberry Pi 5 CPU 状态 ======' '====== Raspberry Pi 5 CPU status ======'
  if ! freq=$(managed_config inspect "$CONFIG"); then
    warn '无法识别有效的超频管理区块。' 'Could not read a valid managed overclock block.'
  elif [[ -n "$freq" ]]; then
    say '脚本设定最高频率：%s MHz（重启后生效）' 'Configured maximum: %s MHz (applies after reboot)' "$freq"
  else
    say '脚本频率设置：无（采用其他固件配置或默认设置）' 'No script-managed frequency (other firmware settings or defaults apply).'
  fi
  if [[ -r "$policy/scaling_max_freq" ]] && k=$(<"$policy/scaling_max_freq") && [[ "$k" =~ ^[0-9]+$ ]]; then
    say '系统报告最高频率：%s MHz' 'System-reported maximum: %s MHz' "$((10#$k / 1000))"
  fi
  if [[ -r "$policy/scaling_cur_freq" ]] && k=$(<"$policy/scaling_cur_freq") && [[ "$k" =~ ^[0-9]+$ ]]; then
    say '实时 CPU 频率：%s MHz' 'Current CPU frequency: %s MHz' "$((10#$k / 1000))"
  fi
  if temp=$(read_cpu_temperature); then
    say '实时 CPU 温度：%s °C' 'Current CPU temperature: %s °C' "$(celsius "$temp")"
  else
    warn 'CPU 温度传感器不可用。' 'CPU temperature sensor unavailable.'
  fi
  if command -v vcgencmd >/dev/null 2>&1; then
    timeout 2s vcgencmd get_throttled 2>/dev/null || true
  fi
  say 'CPU 频率会随负载变化，实际频率可能低于目标值。' \
    'CPU frequency varies with load and may fall below the configured target.'
}

check_conflicting_settings() {
  local found
  found=$(awk -v b="$START_MARK" -v e="$END_MARK" '
    { sub(/\r$/, "") }
    $0==b {inside=1; next} $0==e {inside=0; next}
    !inside && /^[[:space:]]*(arm_freq|force_turbo|over_voltage|over_voltage_delta|arm_boost)[[:space:]]*=/ {
      print NR ":" $0
    }
  ' "$CONFIG")
  if [[ -n "$found" ]]; then
    warn '请检查这些现有 CPU 或电压设置是否会与本次设置冲突：' \
      'Check these existing CPU or voltage settings for conflicts:'
    printf '%s\n' "$found" >&2
  fi
}

ACTIVE_STRESS_PID=''
ACTIVE_STRESS_LOG=''
CONFIG_TMP=''
PENDING_BACKUP=''

remove_temp_file() {
  local -n path=$1
  [[ -n "$path" ]] || return 0
  if ! rm -f -- "$path"; then
    warn '无法清理临时文件：%s' 'Could not clean up temporary file: %s' "$path"
    return 1
  fi
  path=''
}

stop_stress() {
  local pid=$ACTIVE_STRESS_PID i
  [[ -n "$pid" ]] || return 0
  # Also check the process group if the leader exits before its workers.
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for ((i=0; i<10; i++)); do
    if ! kill -0 -- "-$pid" 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done
  if ((i == 10)); then
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  ACTIVE_STRESS_PID=''
}

cleanup() {
  local status=$1
  trap '' INT TERM HUP
  stop_stress
  remove_temp_file ACTIVE_STRESS_LOG || { ((status)) || status=1; }
  remove_temp_file CONFIG_TMP || { ((status)) || status=1; }
  remove_temp_file PENDING_BACKUP || { ((status)) || status=1; }
  exit "$status"
}

interrupted() {
  if [[ -n "$ACTIVE_STRESS_PID" ]]; then
    printf '\n' >&2
    warn '收到中断信号，正在停止压力测试……' 'Interrupted. Stopping the stress test…'
  fi
  exit "$1"
}

rewrite_managed_block() {
  local freq=${1:-} backup
  install -d -m 0700 -- "$BACKUP_DIR" ||
    die '无法创建备份目录：%s' 'Could not create the backup directory: %s' "$BACKUP_DIR"
  PENDING_BACKUP=$(mktemp "$BACKUP_DIR/config-XXXXXXXX.txt") ||
    die '无法创建配置备份。' 'Could not create a config backup.'
  cp -- "$CONFIG" "$PENDING_BACKUP" ||
    die '备份失败，启动配置未更改。' 'Backup failed. The boot config was left unchanged.'

  CONFIG_TMP=$(mktemp "${CONFIG%/*}/.pi5-oc.XXXXXX") ||
    die '启动分区无法创建临时文件。' 'Could not create a temporary file on the boot partition.'
  managed_config rewrite "$PENDING_BACKUP" "$freq" > "$CONFIG_TMP" || config_error
  chmod --reference="$CONFIG" -- "$CONFIG_TMP" ||
    die '无法保留启动配置的文件权限。' 'Could not preserve the boot config permissions.'
  sync -f "$PENDING_BACKUP" ||
    die '无法将备份同步到磁盘。' 'Could not flush the backup to disk.'
  cmp -s -- "$CONFIG" "$PENDING_BACKUP" ||
    die '启动配置在写入前发生变化，请重试。' 'The boot config changed before it could be updated. Try again.'

  backup=$PENDING_BACKUP
  PENDING_BACKUP=''
  ok '配置备份：%s' 'Config backup: %s' "$backup"
  mv -fT -- "$CONFIG_TMP" "$CONFIG" ||
    die '无法替换启动配置，已保留备份。' 'Could not replace the boot config. The backup was retained.'
  CONFIG_TMP=''
  sync -f "$CONFIG" ||
    die '启动配置已替换，但无法确认已同步到磁盘。' 'The boot config was replaced, but the disk flush could not be verified.'
  if [[ -n "$freq" ]]; then
    ok '已设置 CPU 目标频率：%s MHz（重启后生效）' 'CPU target set to %s MHz (applies after reboot).' "$freq"
  else
    ok '已移除脚本管理的超频区块（重启后生效）。' \
      'Removed the script-managed overclock block (applies after reboot).'
  fi
}

ask_reboot() {
  if confirm '现在重启生效？[y/N]：' 'Reboot now to apply changes? [y/N]: '; then
    say '正在重启……' 'Rebooting…'
    if ! systemctl reboot; then
      warn '重启失败。可稍后执行 sudo reboot。' 'Reboot failed. You can run sudo reboot later.'
    fi
  else
    say '可稍后执行 sudo reboot 使更改生效。' 'Run sudo reboot later to apply changes.'
  fi
}

set_frequency() {
  local freq=$1 answer
  managed_config inspect "$CONFIG" >/dev/null || config_error
  printf '\n'
  info '准备设置 CPU arm_freq=%s MHz' 'Preparing to set CPU arm_freq=%s MHz' "$freq"
  if ((freq >= 2850)); then
    warn '2.85/2.9 GHz 属于高风险实验档位，可能无法启动、死机或损坏数据。' \
      '2.85/2.9 GHz are high-risk experimental settings. Boot failure, crashes, and data loss are possible.'
    warn '超频时，树莓派固件可能自动提高电压。' 'Raspberry Pi firmware may raise the voltage when overclocked.'
    warn '请先备份重要数据，并确保能从其他设备修复 config.txt。' \
      'Back up important data and make sure you can repair config.txt from another device.'
    if ! prompt answer '请输入 %s 确认，其余输入将取消：' 'Type %s to confirm, or anything else to cancel: ' "$freq" ||
      [[ "$answer" != "$freq" ]]; then
      cancelled
      return 0
    fi
  elif ((freq >= 2700)); then
    warn '进阶超频可能不稳定。请逐档测试并监控温度。' \
      'Advanced overclocks can be unstable. Test each step and monitor the temperature.'
  fi
  if ! confirm '确定修改启动配置？[y/N]：' 'Update the boot config? [y/N]: '; then
    cancelled
    return 0
  fi
  check_conflicting_settings
  rewrite_managed_block "$freq"
  ask_reboot
}

remove_config() {
  local freq
  freq=$(managed_config inspect "$CONFIG") || config_error
  if [[ -z "$freq" ]]; then
    say '没有需要移除的超频管理区块。' 'There is no script-managed overclock block to remove.'
  elif confirm '移除脚本管理的超频区块？[y/N]：' 'Remove the script-managed overclock block? [y/N]: '; then
    rewrite_managed_block
    ask_reboot
  else
    cancelled
  fi
}

uninstall() {
  local script_path=$1 freq
  [[ "$script_path" == /* ]] || script_path="$PWD/$script_path"
  [[ -f "$script_path" && ! -L "$script_path" && ! "$script_path" -ef "$CONFIG" ]] ||
    die '请直接运行脚本文件后再卸载：%s' 'Run the script file directly before uninstalling: %s' "$script_path"
  warn '卸载会移除超频管理区块并删除当前脚本：%s' \
    'Uninstall removes the managed overclock block and deletes this script: %s' "$script_path"
  say '配置备份保存在：%s' 'Config backups are kept in: %s' "$BACKUP_DIR"
  confirm '确认卸载？[y/N]：' 'Uninstall? [y/N]: ' || { cancelled; return 1; }
  freq=$(managed_config inspect "$CONFIG") || config_error

  if [[ -n "$freq" ]]; then
    rewrite_managed_block
  fi
  rm -- "$script_path" ||
    die '无法删除脚本文件，可重试卸载：%s' 'Could not delete the script file. You can retry uninstall: %s' "$script_path"
  ok '卸载完成。' 'Uninstall complete.'
  if [[ -n "$freq" ]]; then
    ask_reboot
  fi
}

read_cpu_temperature() {
  # Prefer a named CPU thermal zone, then the common Pi 5 zone0.
  local zone typ v
  for zone in /sys/class/thermal/thermal_zone*; do
    [[ -r "$zone/type" && -r "$zone/temp" ]] || continue
    typ=$(<"$zone/type") || continue
    if [[ "$typ" == *cpu* || "$typ" == *CPU* ]]; then
      v=$(<"$zone/temp") || continue
      [[ "$v" =~ ^[1-9][0-9]*$ ]] && { printf '%s\n' "$v"; return 0; }
    fi
  done
  zone='/sys/class/thermal/thermal_zone0/temp'
  [[ -r "$zone" ]] || return 1
  v=$(<"$zone") || return 1
  [[ "$v" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$v"
}

celsius() { LC_ALL=C awk -v t="$1" 'BEGIN {printf "%.1f", t/1000}'; }

# Core rail power uses VDD_CORE_A * VDD_CORE_V. The rail sum is an estimate.
pmic_snapshot() {
  local raw
  raw=$(timeout 2s vcgencmd pmic_read_adc 2>/dev/null) || return 1
  printf '%s\n' "$raw" | LC_ALL=C awk -v na="$1" '
    NF>=2 && $1 ~ /_A$/ && $2 ~ /^current\([0-9]+\)=/ {
      rail=$1; sub(/_A$/, "", rail)
      x=$2; sub(/^.*=/,"",x); sub(/A$/, "", x)
      if (x ~ /^[0-9]+(\.[0-9]+)?$/) current[rail]=x+0
    }
    NF>=2 && $1 ~ /_V$/ && $2 ~ /^volt\([0-9]+\)=/ {
      rail=$1; sub(/_V$/, "", rail)
      x=$2; sub(/^.*=/,"",x); sub(/V$/, "", x)
      if (x ~ /^[0-9]+(\.[0-9]+)?$/) volt[rail]=x
    }
    END {
      count=0; sum=0
      for (rail in current) if (rail in volt) {count++; sum+=current[rail]*volt[rail]}
      core=("VDD_CORE" in current && "VDD_CORE" in volt) ? sprintf("%.2f",current["VDD_CORE"]*volt["VDD_CORE"]) : na
      rails=(count>0) ? sprintf("%.2f",sum) : na
      in5v=("EXT5V" in volt) ? volt["EXT5V"] : na
      printf "%s|%s|%s\n",core,rails,in5v
    }
  '
}

ask_stress_minutes() {
  local input
  while prompt input '压测时长（1-%s 分钟，输入 0 取消）：' \
    'Stress-test duration (1-%s minutes, 0 to cancel): ' "$MAX_STRESS_MINUTES"; do
    [[ "$input" != 0 ]] || return 1
    if [[ ! "$input" =~ ^[1-9][0-9]{0,2}$ ]]; then
      warn '请输入不带空格的整数分钟数，例如 5、10 或 30。' \
        'Enter a whole number of minutes without spaces, such as 5, 10, or 30.'
    elif ((input > MAX_STRESS_MINUTES)); then
      warn '最长压测时长为 %s 分钟。' 'The maximum test duration is %s minutes.' "$MAX_STRESS_MINUTES"
    else
      printf -v "$1" '%s' "$input"
      return 0
    fi
  done
  return 1
}

stress_test() {
  local cmd minutes seconds cores answer temp_raw
  for cmd in stress-ng setsid nproc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn '缺少 %s。安装命令：sudo apt install stress-ng util-linux coreutils' \
        'Missing %s. Install it with sudo apt install stress-ng util-linux coreutils.' "$cmd"
      return 0
    fi
  done
  if ! ask_stress_minutes minutes; then
    cancelled
    return 0
  fi
  seconds=$((minutes * 60))
  cores=$(nproc)
  printf '\n'
  info '即将使用 %s 个逻辑核心压测 %s 分钟（%s 秒）。' \
    'Ready to stress %s logical CPUs for %s minutes (%s seconds).' "$cores" "$minutes" "$seconds"
  warn '监控 CPU 温度、频率、PMIC 核心供电轨功率和 5V 输入电压。' \
    'Monitoring CPU temperature, frequency, PMIC core rail power, and 5V input voltage.'
  warn '温度达到 80°C、读温失败或测得输入电压低于 4.8V 时，压测会提前停止。' \
    'The test stops at 80°C, on a temperature read failure, or when measured input drops below 4.8V.'
  warn 'PMIC 读数仅反映所测供电轨功率。超频仍有硬件不稳定和数据损坏风险。' \
    'PMIC readings cover the measured rails. Overclocking still risks instability and data loss.'
  if ! command -v vcgencmd >/dev/null 2>&1; then
    warn '缺少 vcgencmd。功率和输入电压不可用，电压保护未启用。' \
      'vcgencmd is missing. Power and input voltage readings are unavailable, and voltage protection is inactive.'
  fi
  if ! temp_raw=$(read_cpu_temperature); then
    warn '无法读取可信的 CPU 温度，已拒绝开始压测。' \
      'Could not read a reliable CPU temperature. The stress test was blocked.'
    return 0
  fi
  if ((temp_raw >= TEMP_LIMIT_MILLIC)); then
    warn 'CPU 温度已达到或超过 80°C，已拒绝开始压测。' \
      'The CPU is already at or above 80°C. The stress test was blocked.'
    return 0
  fi
  if ! prompt answer '输入 YES 开始 %s 分钟 CPU 满载压测：' \
    'Type YES to start the %s-minute CPU stress test: ' "$minutes" || [[ "$answer" != YES ]]; then
    cancelled
    return 0
  fi

  local start_secs elapsed max_temp=0 cur_freq freq_str temp_str
  local snapshot core_w rails_w ext_v rc=0 stopped=0 na
  local freq_path='/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'
  na=$(print_message '' '不可用' 'N/A')
  ACTIVE_STRESS_LOG=$(mktemp /tmp/pi5-stress-ng.XXXXXX) ||
    die '无法创建临时压测日志。' 'Could not create a temporary stress-test log.'
  setsid stress-ng --cpu "$cores" --timeout "${seconds}s" --metrics-brief > "$ACTIVE_STRESS_LOG" 2>&1 &
  ACTIVE_STRESS_PID=$!
  start_secs=$SECONDS

  while kill -0 "$ACTIVE_STRESS_PID" 2>/dev/null; do
    elapsed=$((SECONDS - start_secs))
    ((elapsed > seconds)) && elapsed=$seconds

    if ! temp_raw=$(read_cpu_temperature); then
      warn 'CPU 温度传感器读取失败，已停止压测。' 'CPU temperature read failed. Stopping the stress test.'
      stopped=1
      stop_stress
      break
    fi
    ((temp_raw > max_temp)) && max_temp=$temp_raw
    temp_str=$(celsius "$temp_raw")
    if ((temp_raw >= TEMP_LIMIT_MILLIC)); then
      warn 'CPU 温度达到 %s °C，已触发 80°C 保护阈值。' \
        'CPU temperature reached %s °C, triggering the 80°C cutoff.' "$temp_str"
      stopped=1
      stop_stress
      break
    fi

    freq_str=$na
    if [[ -r "$freq_path" ]] && cur_freq=$(<"$freq_path") && [[ "$cur_freq" =~ ^[0-9]+$ ]]; then
      freq_str=$(LC_ALL=C awk -v f="$cur_freq" 'BEGIN {printf "%.3f", f/1000000}')
    fi
    snapshot=$(pmic_snapshot "$na") || snapshot="$na|$na|$na"
    IFS='|' read -r core_w rails_w ext_v <<< "$snapshot"

    if [[ -t 1 ]]; then printf '\033[2J\033[H'; fi
    info '====== Raspberry Pi 5 CPU 压力测试 ======' '====== Raspberry Pi 5 CPU stress test ======'
    say '测试进度：      %02d:%02d / %02d:00' 'Progress:           %02d:%02d / %02d:00' \
      "$((elapsed/60))" "$((elapsed%60))" "$minutes"
    say 'CPU 当前频率：  %s GHz' 'CPU frequency:      %s GHz' "$freq_str"
    say 'CPU 实时温度：  %s °C' 'CPU temperature:    %s °C' "$temp_str"
    say '核心供电轨功率：%s W [VDD_CORE]' 'Core rail power:    %s W [VDD_CORE]' "$core_w"
    say 'PMIC 轨功率和： %s W [估算]' 'PMIC rail sum:      %s W [estimate]' "$rails_w"
    say '5V 输入电压：   %s V' '5V input:           %s V' "$ext_v"
    say '本次最高温度：  %s °C' 'Peak temperature:   %s °C' "$(celsius "$max_temp")"
    say '保护阈值：80°C / 4.8V。按 Ctrl+C 停止测试。' \
      'Cutoffs: 80°C / 4.8V. Press Ctrl+C to stop.'

    if [[ "$ext_v" =~ ^[0-9]+(\.[0-9]+)?$ ]] &&
      LC_ALL=C awk -v v="$ext_v" -v min="$MIN_INPUT_VOLTS" 'BEGIN {exit !(v < min)}'; then
      warn '5V 输入电压为 %s V，已触发 %s V 低压保护。' \
        '5V input dropped to %s V, triggering the %s V cutoff.' "$ext_v" "$MIN_INPUT_VOLTS"
      stopped=1
      stop_stress
      break
    fi
    sleep 1
  done

  printf '\n'
  if (( ! stopped )); then
    wait "$ACTIVE_STRESS_PID" || rc=$?
    if kill -0 -- "-$ACTIVE_STRESS_PID" 2>/dev/null; then
      stop_stress
    else
      ACTIVE_STRESS_PID=''
    fi
    if ((rc == 0)); then
      ok '压力测试已正常结束。' 'Stress test completed.'
    else
      warn '压力测试异常退出（stress-ng 状态码：%s）。' 'Stress test failed (stress-ng exit status: %s).' "$rc"
    fi
  fi
  if ((max_temp > 0)); then
    say '本次最高 CPU 温度：%s °C' 'Peak CPU temperature: %s °C' "$(celsius "$max_temp")"
  fi
  say '====== stress-ng 运行结果 ======' '====== stress-ng results ======'
  cat -- "$ACTIVE_STRESS_LOG"
  remove_temp_file ACTIVE_STRESS_LOG
  printf '\n'
}

main() {
  local script_path=$1 choice lock_fd
  choose_language || return 0
  check_platform
  exec {lock_fd}>>"$LOCK_PATH" ||
    die '无法打开运行锁：%s' 'Could not open the session lock: %s' "$LOCK_PATH"
  flock -n "$lock_fd" ||
    die '无法取得运行锁，请检查是否已有脚本实例在运行。' \
      'Could not acquire the session lock. Check for another running instance.'

  trap 'cleanup "$?"' EXIT
  trap 'interrupted 130' INT
  trap 'interrupted 143' TERM
  trap 'interrupted 129' HUP
  while true; do
    printf '\n'
    info '====== Raspberry Pi 5 CPU 超频与压力测试 ======' '====== Raspberry Pi 5 CPU overclock and stress test ======'
    say '启动配置管理项：CPU arm_freq' 'Managed boot setting: CPU arm_freq'
    say '  1) 2.4 GHz  默认频率' '  1) 2.4 GHz  Default frequency'
    say '  2) 2.6 GHz  轻度超频' '  2) 2.6 GHz  Mild overclock'
    say '  3) 2.7 GHz  进阶超频' '  3) 2.7 GHz  Advanced overclock'
    say '  4) 2.8 GHz  高风险超频' '  4) 2.8 GHz  High-risk overclock'
    say '  5) 查看 CPU 频率和温度' '  5) View CPU frequency and temperature'
    say '  6) 自定义时长压测与实时监控' '  6) Run a monitored stress test'
    say '  7) 移除超频设置' '  7) Remove managed overclock settings'
    say '  8) 2.85 GHz 实验超频（需二次确认）' '  8) 2.85 GHz Experimental (requires extra confirmation)'
    say '  9) 2.9 GHz  实验超频（需二次确认）' '  9) 2.9 GHz  Experimental (requires extra confirmation)'
    say ' 10) 一键卸载脚本' ' 10) Uninstall this script'
    say '  0) 退出' '  0) Exit'

    if ! prompt choice '请选择 [0-10]：' 'Select [0-10]: '; then
      printf '\n'
      return 0
    fi
    case "$choice" in
      1) set_frequency 2400 ;;
      2) set_frequency 2600 ;;
      3) set_frequency 2700 ;;
      4) set_frequency 2800 ;;
      5) show_status ;;
      6) stress_test ;;
      7) remove_config ;;
      8) set_frequency 2850 ;;
      9) set_frequency 2900 ;;
      10) if uninstall "$script_path"; then return 0; fi ;;
      0) say '已退出。' 'Exited.'; return 0 ;;
      *) warn '无效选项，请输入 0-10。' 'Invalid option. Enter a number from 0 to 10.' ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "${BASH_SOURCE[0]}"
fi

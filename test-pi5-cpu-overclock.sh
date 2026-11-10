#!/usr/bin/env bash
# Run with: bash test-pi5-cpu-overclock.sh
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
script="$test_dir/script copy.sh"
config="$test_dir/config.txt"
backup_dir="$test_dir/backups"
mkdir -- "$backup_dir"
cleanup_test() {
  local status=$?
  if ((status)) && [[ -f "$test_dir/output.txt" ]]; then
    cat -- "$test_dir/output.txt"
  fi
  rm -f -- "$script" "$test_dir"/*.txt "$test_dir"/.pi5-oc.* "$test_dir"/stress.* "$backup_dir"/config-*.txt
  rmdir -- "$backup_dir" "$test_dir"
}
trap cleanup_test EXIT
shopt -s nullglob

# Exercise the real menu and file operations against disposable copies.
sed -e "s|'/boot/firmware/config.txt'|\"\$test_dir/config.txt\"|" \
    -e "s|'/var/backups/pi5-cpu-overclock'|\"\$test_dir/backups\"|" \
    -e "s|'/run/pi5-cpu-overclock.lock'|\"\$test_dir/lock.txt\"|" \
    -e 's|mktemp /tmp/pi5-stress-ng[.]XXXXXX|mktemp "$test_dir/stress.XXXXXX"|' \
    "$project_dir/pi5-cpu-overclock.sh" > "$script"

run_script() (
  local scenario=${1:-normal} parent_pid=$BASHPID
  # shellcheck disable=SC1090
  source "$script"
  check_platform() { :; }
  flock() { :; }
  sync() { :; }
  if [[ "$OSTYPE" == msys || "$OSTYPE" == cygwin ]]; then
    # Match Linux file handling when using Git Bash for the test.
    install() { mkdir -p -- "$5"; }
    chmod() { :; }
    awk() { command awk -v BINMODE=3 "$@"; }
  fi
  read_cpu_temperature() { printf '45000\n'; }
  setsid() { "$@"; }
  stress-ng() {
    printf 'mock stress metrics\n'
    case "$scenario" in
      stress_failure) return 2 ;;
      interrupted)
        sleep 0.2
        kill -TERM "$parent_pid"
        sleep 1
        ;;
    esac
  }
  if [[ "$scenario" == backup_failure ]]; then
    cp() { printf 'partial backup\n' > "$3"; return 1; }
  elif [[ "$scenario" == replace_failure ]]; then
    mv() { return 1; }
  fi
  main "$script"
)

run() { run_script "${2:-normal}" > "$test_dir/output.txt" 2>&1 <<< "$1"; }
expect_exit() {
  local status=0
  set +e
  run "$2" "${3:-normal}"
  status=$?
  set -e
  [[ "$status" == "$1" ]]
}
contains() { grep -Fq -- "$1" "$test_dir/output.txt"; }
no_temps() {
  local files=("$test_dir"/.pi5-oc.* "$test_dir"/stress.*)
  (( ${#files[@]} == 0 ))
}

printf '# custom firmware config\r\n[none]\r\narm_freq=1234\r\n' > "$test_dir/baseline.txt"
cp -- "$test_dir/baseline.txt" "$config"
run $'invalid\n2\n5\n0'
contains 'Enter 1 or 2'
contains 'No script-managed frequency'
run $'1\n0'
contains '一键卸载脚本'

run $'2\n8\nincorrect\n0'
contains 'Cancelled.'
cmp -- "$config" "$test_dir/baseline.txt"

run $'2\n2\ny\nn\n5\n0'
contains 'Configured maximum: 2600 MHz'
grep -Fq 'arm_freq=2600' "$config"
grep -Fq '[all]' "$config"
backups=("$backup_dir"/config-*.txt)
(( ${#backups[@]} == 1 ))
cmp -- "$test_dir/baseline.txt" "${backups[0]}"
cp -- "$config" "$test_dir/applied.txt"
run $'2\n2\ny\nn\n0'
cmp -- "$config" "$test_dir/applied.txt"
no_temps

expect_exit 1 $'2\n3\ny\nn' backup_failure
contains 'Backup failed'
cmp -- "$config" "$test_dir/applied.txt"
backups=("$backup_dir"/config-*.txt)
(( ${#backups[@]} == 2 ))
no_temps

expect_exit 1 $'2\n3\ny\nn' replace_failure
contains 'Could not replace the boot config.'
cmp -- "$config" "$test_dir/applied.txt"
backups=("$backup_dir"/config-*.txt)
(( ${#backups[@]} == 3 ))
no_temps

run $'2\n6\n121\n1\nYES\n0'
contains 'The maximum test duration is 120 minutes.'
contains 'Stress test completed.'
contains 'mock stress metrics'
no_temps
run $'2\n6\n1\nYES\n0' stress_failure
contains 'stress-ng exit status: 2'
no_temps
expect_exit 143 $'2\n6\n1\nYES\n0' interrupted
contains 'Interrupted. Stopping the stress test'
no_temps

run $'2\n7\ny\nn\n0'
contains 'Removed the script-managed overclock block'
cmp -- "$config" "$test_dir/baseline.txt"
[[ -f "$script" ]]

# An orphan marker must prevent both config changes and deletion of the script.
printf '%s\n' '# <<< PI5_CPU_OVERCLOCK_MANAGED_END <<<' >> "$config"
cp -- "$config" "$test_dir/malformed.txt"
expect_exit 1 $'2\n10\ny'
contains 'Could not safely process the boot config.'
cmp -- "$config" "$test_dir/malformed.txt"
[[ -f "$script" ]]
no_temps

# Uninstall accepts the old block format and preserves config after an [all] reset.
cp -- "$test_dir/baseline.txt" "$config"
printf '%s\r\n' '# >>> PI5_CPU_OVERCLOCK_MANAGED_START >>>' '[pi5]' 'arm_freq=2800' \
  '# <<< PI5_CPU_OVERCLOCK_MANAGED_END <<<' '[all]' 'dtparam=audio=on' >> "$config"
run $'2\n10\nn\n0'
contains 'Cancelled.'
[[ -f "$script" ]]
run $'2\n10\ny\nn'
contains 'Uninstall complete.'
[[ ! -e "$script" ]]
printf '%s\r\n' '[all]' 'dtparam=audio=on' >> "$test_dir/baseline.txt"
cmp -- "$config" "$test_dir/baseline.txt"
no_temps

printf '%s\n' 'Menu, config backup and restore, stress log cleanup, and uninstall checks passed.'

#!/usr/bin/env bash
# ============================================================
# flash_board.sh -- program the FPGA board through Vivado
#
# Usage:
#   bash flash_board.sh                      # default exp7 bit
#   bash flash_board.sh /path/to/other.bit   # custom bit file
#
# Works in Git Bash (cygpath) and WSL (wslpath).
# Programming logic lives in flash_board.tcl (same folder).
# Vivado console output is saved to flash_board.log.
#
# 2026-09-15: run through a generated ASCII .bat instead of
# `powershell.exe -Command "..." > log`.  Under WSL the old form
# returned exit code 1 and left flash_board.log empty (the Windows
# process output is lost when bash redirects its stdout to a file),
# and launching it from a cwd whose path contains Chinese characters
# failed silently as well.  Driving cmd.exe with a .bat that does its
# own redirection avoids both pitfalls; every path inside the .bat is
# ASCII (flash_board.tcl is copied into the Windows temp directory).
# ============================================================
set -u

DEFAULT_BIT="C:/vivado_prj/exp7/soc_verify/soc_bram/run_vivado/project/loongson.runs/impl_1/soc_lite_top.bit"
VIV_APP="C:/Application/Xilinx/Vivado/2019.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/flash_board.log"

BIT_FILE="${1:-$DEFAULT_BIT}"

# Convert a POSIX path to a Windows path.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  elif command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# Convert a Windows path to a POSIX path.
unixpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  elif command -v wslpath >/dev/null 2>&1; then
    wslpath -u "$1"
  else
    printf '%s' "$1"
  fi
}

# Git Bash (MSYS) rewrites a lone /c into a path, so it needs //c.
if command -v cygpath >/dev/null 2>&1; then
  CMD_SWITCH="//c"
else
  CMD_SWITCH="/c"
fi

if [ ! -f "$BIT_FILE" ]; then
  echo "ERROR: bit file not found: $BIT_FILE"
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/flash_board.tcl" ]; then
  echo "ERROR: flash_board.tcl missing next to this script"
  exit 1
fi

# NB: wslpath -w rewrites the drive colon of an already-Windows-style path
# ("C:/...") into a fullwidth colon (U+FF1A), which cmd.exe cannot resolve.
# Convert the separators ourselves so the drive colon stays ASCII.
BIT_WIN="$(winpath "$BIT_FILE")"
VIV_WIN="$(printf '%s' "$VIV_APP/settings64.bat" | sed 's|/|\\|g')"

case "$BIT_WIN" in
  *" "*) echo "ERROR: bit file path must not contain spaces: $BIT_WIN"; exit 1 ;;
esac

# Windows temp directory (ASCII): holds the generated .bat, a copy of
# flash_board.tcl and the Vivado log written on the Windows side.
WTMP_WIN="$(powershell.exe -NoProfile -Command 'Write-Output $env:TEMP' 2>/dev/null | tr -d '\r\n')"
[ -n "$WTMP_WIN" ] || WTMP_WIN='C:\Windows\Temp'
WTMP_DIR="$(unixpath "$WTMP_WIN")"

BAT_LOCAL="$WTMP_DIR/flash_board_run.bat"
TCL_TMP="$WTMP_DIR/flash_board.tcl"
LOG_TMP="$WTMP_DIR/flash_board.log"
cp -f "$SCRIPT_DIR/flash_board.tcl" "$TCL_TMP"

{
  printf '@echo off\r\n'
  printf 'cd /d C:\\\r\n'
  printf 'call "%s" >nul 2>&1\r\n' "$VIV_WIN"
  printf 'set BIT_FILE=%s\r\n' "$BIT_WIN"
  printf 'vivado -mode batch -nolog -nojournal -source "%s" > "%s" 2>&1\r\n' "$(winpath "$TCL_TMP")" "$(winpath "$LOG_TMP")"
} > "$BAT_LOCAL"

echo "=============================================="
echo "bit file : $BIT_FILE"
echo "log      : $LOG"
echo "Flashing now -- keep the board powered and the"
echo "JTAG/USB cable connected, then wait ~20-40 s..."
echo "=============================================="

cmd.exe "$CMD_SWITCH" "$(winpath "$BAT_LOCAL")"
RC=$?
cp -f "$LOG_TMP" "$LOG" 2>/dev/null || true

echo "----------------------------------------------"
if [ "$RC" -ne 0 ] || ! grep -q "=== PROGRAM DONE ===" "$LOG"; then
  echo "FLASH FAILED (exit code $RC). Last log lines:"
  tail -n 25 "$LOG"
  echo "Common causes:"
  echo "  - board not powered / JTAG-USB cable unplugged"
  echo "  - Vivado GUI Hardware Manager holds the target"
  exit 1
fi

echo "FLASH OK: PROGRAM DONE."
echo "Board check: 7-seg display stops at 0x14000014,"
echo "both green LEDs on  ==> all 20 test points PASS."
echo "Full log: $LOG"
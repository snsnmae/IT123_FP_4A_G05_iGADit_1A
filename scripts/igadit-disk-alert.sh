#!/bin/bash
# =============================================================================
# igadit-disk-alert.sh — iGADit Storage Threshold Monitoring & Alert Script
# IT 123: System Administration and Maintenance | Option 1A
#
# Purpose:
#   Checks disk usage across all physical partitions using df. Warns clearly
#   and logs when usage exceeds a configurable threshold (default 80%).
#   Exits with status 3 on alert so automated schedulers/cron can catch it.
#   Lists the top 5 largest directories in the app and files in storage/.
#
# Authors:
#   Orillana, Angel A.        (Project Lead)
#   Bataller, Kristine Mae B. (System Administrator)
#   Avila, Clarissa A.        (Documentation & Presentation Lead)
#
# Usage:
#   sudo ./igadit-disk-alert.sh [--help] [THRESHOLD_PERCENT]
#
# Arguments:
#   --help             Display this usage message and exit.
#   THRESHOLD_PERCENT  Optional integer (1-99). Default is 80.
#
# Examples:
#   sudo ./igadit-disk-alert.sh
#   sudo ./igadit-disk-alert.sh 85
#   sudo ./igadit-disk-alert.sh --help
#
# AI Disclosure:
#   This script was developed with the assistance of an AI coding tool.
#   All team members have reviewed and can explain every command line.
#
# Exit Status:
#   0  All partitions below threshold (normal).
#   1  Privilege check failed: Not executed as root.
#   2  Missing configuration file (/etc/igadit/igadit.conf).
#   3  Alert triggered: One or more partitions exceeded the threshold.
#   4  Invalid threshold argument supplied.
# =============================================================================

set -e

CONFIG_FILE="/etc/igadit/igadit.conf"

# --- Usage Function ----------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo $0 [--help] [THRESHOLD_PERCENT]

Description:
  Monitors mounted storage partitions. Warns on terminal and appends to alert log
  if any partition utilization meets or exceeds the threshold.

Options:
  --help             Show this help message and exit.

Arguments:
  THRESHOLD_PERCENT  Integer between 1 and 99. Default is 80.

Examples:
  sudo $0
  sudo $0 90
  sudo $0 --help

Exit Statuses:
  0  All clear
  1  Must run as root
  2  Config missing
  3  Threshold exceeded (Alert triggered)
  4  Invalid parameter
EOF
}

if [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# --- Privilege Check ---------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must run as root. Current UID is $(id -u)." >&2
    echo "       Run with: sudo $0" >&2
    exit 1
fi

# --- Configuration Validation ------------------------------------------------
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Configuration file not found at ${CONFIG_FILE}" >&2
    exit 2
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

CURRENT_THRESHOLD="${DISK_THRESHOLD:-80}"

# Positional Parameter Check with Regex Validation (Skill M11 & M13)
if [ -n "$1" ]; then
    if [[ "$1" =~ ^[1-9][0-9]?$ ]]; then
        CURRENT_THRESHOLD="$1"
    else
        echo "ERROR: Threshold must be an integer between 1 and 99. Got: '$1'" >&2
        exit 4
    fi
fi

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
touch "${ALERT_LOG}" 2>/dev/null || true

echo "=========================================================="
echo "  iGADit — Disk Utilization & Threshold Monitor"
echo "  IT 123 Final Project | Option 1A"
echo "  Threshold : ${CURRENT_THRESHOLD}%"
echo "  Timestamp : ${TIMESTAMP}"
echo "=========================================================="
echo ""

ALERT_FOUND=0

echo "--- Partition Status (df -h) ---"
printf "  %-25s %6s %6s %6s %7s  %s\n" "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted on"
echo "  ------------------------------------------------------------------"

# Process substitution avoids the subshell pipe bug (Skill M11)
while IFS= read -r LINE; do
    FS_NAME=$(echo "${LINE}" | awk '{print $1}')
    FS_SIZE=$(echo "${LINE}" | awk '{print $2}')
    FS_USED=$(echo "${LINE}" | awk '{print $3}')
    FS_AVAIL=$(echo "${LINE}" | awk '{print $4}')
    FS_PCT=$(echo "${LINE}" | awk '{print $5}' | tr -d '%')
    FS_MOUNT=$(echo "${LINE}" | awk '{print $6}')

    printf "  %-25s %6s %6s %6s %6s%%  %s\n" "${FS_NAME}" "${FS_SIZE}" "${FS_USED}" "${FS_AVAIL}" "${FS_PCT}" "${FS_MOUNT}"

    # Threshold comparison
    if [ "${FS_PCT}" -ge "${CURRENT_THRESHOLD}" ] 2>/dev/null; then
        echo ""
        echo "  **********************************************************"
        echo "  [WARNING] Mount '${FS_MOUNT}' is at ${FS_PCT}% capacity!"
        echo "            Threshold configured at ${CURRENT_THRESHOLD}%."
        echo "  **********************************************************"
        echo ""
        echo "[${TIMESTAMP}] WARNING: Mount '${FS_MOUNT}' is at ${FS_PCT}% (Threshold: ${CURRENT_THRESHOLD}%)" >> "${ALERT_LOG}"
        ALERT_FOUND=1
    fi
done < <(df -h --output=source,size,used,avail,pcent,target | grep -E "^/dev/" | grep -vE "^/dev/loop")

echo ""

# --- Top 5 Largest Subdirectories in Application -----------------------------
echo "--- Top 5 Largest Directories in ${APP_DIR} ---"
if [ -d "${APP_DIR}" ]; then
    du -sh "${APP_DIR}"/*/ 2>/dev/null | sort -rh | head -n 5 | awk '{printf "  %8s  %s\n", $1, $2}'
else
    echo "  [NOTICE] App folder '${APP_DIR}' not found."
fi
echo ""

# --- Top 5 Largest Files in storage/ (Skill M07/M11) --------------------------
echo "--- Top 5 Largest Files in ${APP_DIR}/storage ---"
if [ -d "${APP_DIR}/storage" ]; then
    find "${APP_DIR}/storage" -type f -exec du -sh {} + 2>/dev/null | sort -rh | head -n 5 | awk '{printf "  %8s  %s\n", $1, $2}'
else
    echo "  [NOTICE] Storage directory not found."
fi
echo ""

# --- Final Assessment & Exit Status (Section 5.1 & Table 3) ------------------
echo "=========================================================="
if [ "${ALERT_FOUND}" -eq 1 ]; then
    echo "  STATUS: THRESHOLD EXCEEDED (Alert triggered)"
    echo "  Alert log: ${ALERT_LOG}"
    echo "=========================================================="
    exit 3
else
    echo "  STATUS: ALL NORMAL (All partitions below ${CURRENT_THRESHOLD}%)"
    echo "=========================================================="
    exit 0
fi

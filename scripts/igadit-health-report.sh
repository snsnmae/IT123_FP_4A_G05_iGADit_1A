#!/bin/bash
# =============================================================================
# igadit-health-report.sh — iGADit Health & Performance Inspection Script
# IT 123: System Administration and Maintenance | Option 1A
#
# Purpose:
#   Reports system and service health in one readable report. Checks CPU load,
#   RAM usage, disk partition status, systemd service states (Apache2, MySQL),
#   HTTP endpoint responsiveness, and active human accounts on the server.
#
# Authors:
#   Orillana, Angel A.        (Project Lead)
#   Bataller, Kristine Mae B. (System Administrator)
#   Avila, Clarissa A.        (Documentation & Presentation Lead)
#
# Usage:
#   sudo ./igadit-health-report.sh [--help]
#
# Examples:
#   sudo ./igadit-health-report.sh
#   sudo ./igadit-health-report.sh --help
#
# AI Disclosure:
#   This script was developed with the assistance of an AI coding tool.
#   All team members have reviewed and can explain every command line.
#
# Exit Status:
#   0  All checks healthy.
#   1  Privilege check failed: Not executed as root.
#   2  Missing configuration file (/etc/igadit/igadit.conf).
#   3  One or more service or resource checks failed.
# =============================================================================

set -e

CONFIG_FILE="/etc/igadit/igadit.conf"

# --- Usage Function ----------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo $0 [--help]

Description:
  Generates a comprehensive diagnostic report verifying the operational
  status of Apache, MySQL, system memory, disk partitions, and Laravel HTTP response.

Options:
  --help   Display this help message and exit.

Examples:
  sudo $0
  sudo $0 --help

Exit Statuses:
  0  All checks passed (HEALTHY)
  1  Must run as root
  2  Config missing
  3  One or more failures detected (NEEDS ATTENTION)
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

FAIL_COUNT=0

echo "=========================================================="
echo "  iGADit — Server Health & Service Status Report"
echo "  IT 123 Final Project | Option 1A"
echo "  Generated: $(date)"
echo "=========================================================="
echo ""

# --- 1. Systemd Service Checks (Skill M13: for loop) -------------------------
echo "--- Core Services Status ---"
for SERVICE in apache2 mysql; do
    if [ "$(systemctl is-active "${SERVICE}" 2>/dev/null)" = "active" ]; then
        echo "  [OK]   Service '${SERVICE}' is ACTIVE (running)."
    else
        echo "  [FAIL] Service '${SERVICE}' is INACTIVE."
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done
echo ""

# --- 2. Resource Checks: Disk Usage (Skill M15: df) --------------------------
echo "--- Storage & Disk Partitions (df -h) ---"
df -h --output=source,size,used,avail,pcent,target | grep -E "^(Filesystem|/dev/)" | awk '
    NR==1 { printf "  %-22s %6s %6s %6s %6s %s\n", $1, $2, $3, $4, $5, $6 }
    NR>1  { printf "  %-22s %6s %6s %6s %6s %s\n", $1, $2, $3, $4, $5, $6 }
'

ROOT_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "${ROOT_PCT}" -ge 80 ]; then
    echo "  [WARN] Root partition usage is high: ${ROOT_PCT}% (Threshold: 80%)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo "  [OK]   Root partition usage is normal: ${ROOT_PCT}%"
fi
echo ""

# --- 3. Resource Checks: Memory Usage (Skill M15: free) ----------------------
echo "--- Memory & Swap Usage (free -h) ---"
free -h | awk '
    /^Mem:/  { printf "  Physical RAM : %s total | %s used | %s free | %s cached\n", $2, $3, $4, $6 }
    /^Swap:/ { printf "  Swap Space   : %s total | %s used | %s free\n", $2, $3, $4 }
'

RAM_PCT=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "${RAM_PCT}" -ge 90 ]; then
    echo "  [WARN] RAM utilization high: ${RAM_PCT}% (Threshold: 90%)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo "  [OK]   RAM utilization normal: ${RAM_PCT}%"
fi
echo ""

# --- 4. CPU & Load Average (Skill M15: top/uptime) ---------------------------
echo "--- Processor & CPU Load ---"
LOAD_VAL=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
echo "  CPU Cores       : $(nproc)"
echo "  1-Min Load Avg  : ${LOAD_VAL}"
echo "  System Uptime   : $(uptime -p 2>/dev/null || uptime)"
echo ""

# --- 5. Application HTTP Response (Skill M13: case statement) ----------------
echo "--- Application Endpoint Check ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost || echo "000")

case "${HTTP_STATUS}" in
    200|302)
        echo "  [OK]   iGADit web app returned HTTP ${HTTP_STATUS} (OK/Redirect)."
        ;;
    000)
        echo "  [FAIL] Web server connection timed out or refused."
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ;;
    *)
        echo "  [FAIL] Web server returned unexpected HTTP status: ${HTTP_STATUS}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ;;
esac
echo ""

# --- 6. User Account Auditing (Skill M08/M09) --------------------------------
echo "--- Human Accounts with Interactive Shells (/etc/passwd) ---"
grep -E ":/bin/(bash|sh|zsh)$" /etc/passwd | awk -F: '{printf "  UID: %-5s User: %s\n", $3, $1}'
echo ""

# --- Summary & Exit Code -----------------------------------------------------
echo "=========================================================="
if [ "${FAIL_COUNT}" -eq 0 ]; then
    echo "  OVERALL SYSTEM STATUS: HEALTHY (All checks passed)"
    echo "=========================================================="
    exit 0
else
    echo "  OVERALL SYSTEM STATUS: NEEDS ATTENTION (${FAIL_COUNT} issue(s) detected)"
    echo "=========================================================="
    exit 3
fi

#!/bin/bash
# =============================================================================
# igadit-log-summary.sh — iGADit Log Extraction & Summary Report Script
# IT 123: System Administration and Maintenance | Option 1A
#
# Purpose:
#   Extracts important operational and security events from the Apache
#   access/error logs and the Laravel application log. Compiles error counts,
#   top requested endpoints, top client IP addresses, and recent exceptions
#   into a dated summary report file.
#
# Authors:
#   Orillana, Angel A.        (Project Lead)
#   Bataller, Kristine Mae B. (System Administrator)
#   Avila, Clarissa A.        (Documentation & Presentation Lead)
#
# Usage:
#   sudo ./igadit-log-summary.sh [--help] [OUTPUT_DIR]
#
# Arguments:
#   --help      Display this usage message and exit.
#   OUTPUT_DIR  Optional target folder for report files.
#
# Examples:
#   sudo ./igadit-log-summary.sh
#   sudo ./igadit-log-summary.sh /var/log/reports
#   sudo ./igadit-log-summary.sh --help
#
# AI Disclosure:
#   This script was developed with the assistance of an AI coding tool.
#   All team members have reviewed and can explain every command line.
#
# Exit Status:
#   0  Success: Log summary report generated.
#   1  Privilege check failed: Not executed as root.
#   2  Missing configuration file (/etc/igadit/igadit.conf).
#   3  Report generation or I/O failure.
# =============================================================================

set -e

CONFIG_FILE="/etc/igadit/igadit.conf"

# --- Usage Function ----------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo $0 [--help] [OUTPUT_DIR]

Description:
  Parses Apache access, Apache error, and Laravel logs to compile
  statistics and recent error records into a dated report file.

Options:
  --help      Show this help message and exit.

Arguments:
  OUTPUT_DIR  Optional directory to save the report (default from config).

Examples:
  sudo $0
  sudo $0 /var/log/igadit-reports
  sudo $0 --help

Exit Statuses:
  0  Success
  1  Must run as root
  2  Config missing
  3  Write/Execution error
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

TARGET_DIR="${REPORT_DIR:-/var/log/igadit-reports}"
if [ -n "$1" ]; then
    TARGET_DIR="$1"
fi

mkdir -p "${TARGET_DIR}" || {
    echo "ERROR: Cannot create output directory ${TARGET_DIR}" >&2
    exit 3
}

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_FILE="${TARGET_DIR}/log-summary-${TIMESTAMP}.txt"

APACHE_ACCESS="/var/log/apache2/${APP_NAME}-access.log"
APACHE_ERROR="/var/log/apache2/${APP_NAME}-error.log"
LARAVEL_LOG="${APP_DIR}/storage/logs/laravel.log"

# Custom logging helper using tee (Skill M11: pipes and redirection)
log_out() {
    echo "$@" | tee -a "${REPORT_FILE}"
}

echo "" > "${REPORT_FILE}"
log_out "=========================================================="
log_out "  iGADit — Operational & Error Log Summary Report"
log_out "  Generated : $(date)"
log_out "  Output    : ${REPORT_FILE}"
log_out "=========================================================="
log_out ""

# --- Apache Access Log Analysis (Skill M11: grep, awk, sort, uniq) -----------
log_out "--- Apache Web Traffic Summary ---"
log_out "Source: ${APACHE_ACCESS}"

if [ -f "${APACHE_ACCESS}" ] && [ -s "${APACHE_ACCESS}" ]; then
    TOTAL_REQUESTS=$(wc -l < "${APACHE_ACCESS}")
    # Regex matching HTTP status codes (Skill M11)
    CODE_4XX=$(grep -cE ' (4[0-9]{2}) ' "${APACHE_ACCESS}" 2>/dev/null || echo 0)
    CODE_5XX=$(grep -cE ' (5[0-9]{2}) ' "${APACHE_ACCESS}" 2>/dev/null || echo 0)

    log_out "  Total HTTP Requests : ${TOTAL_REQUESTS}"
    log_out "  Client Errors (4xx) : ${CODE_4XX}"
    log_out "  Server Errors (5xx) : ${CODE_5XX}"
    log_out ""

    log_out "  Top 5 Requested Endpoints:"
    awk '{print $7}' "${APACHE_ACCESS}" | sort | uniq -c | sort -rn | head -5 | while read -r COUNT URL; do
        log_out "    ${COUNT} hits  ${URL}"
    done

    log_out ""
    log_out "  Top 5 Client IP Addresses:"
    awk '{print $1}' "${APACHE_ACCESS}" | sort | uniq -c | sort -rn | head -5 | while read -r COUNT IP; do
        log_out "    ${COUNT} reqs  ${IP}"
    done
else
    log_out "  [NOTICE] No access log entries recorded yet."
fi
log_out ""

# --- Apache Error Log Analysis -----------------------------------------------
log_out "--- Apache Error Log Summary ---"
log_out "Source: ${APACHE_ERROR}"

if [ -f "${APACHE_ERROR}" ] && [ -s "${APACHE_ERROR}" ]; then
    ERR_TOTAL=$(wc -l < "${APACHE_ERROR}")
    log_out "  Total Apache Error Lines: ${ERR_TOTAL}"
    log_out "  Most Recent Apache Errors:"
    tail -n 5 "${APACHE_ERROR}" | while read -r LINE; do
        log_out "    ${LINE}"
    done
else
    log_out "  [OK] No Apache server errors reported."
fi
log_out ""

# --- Laravel Application Log Analysis ----------------------------------------
log_out "--- Laravel Application Errors & Exceptions ---"
log_out "Source: ${LARAVEL_LOG}"

if [ -f "${LARAVEL_LOG}" ] && [ -s "${LARAVEL_LOG}" ]; then
    LARAVEL_ERRORS=$(grep -acE '\.ERROR:' "${LARAVEL_LOG}" 2>/dev/null || echo 0)
    LARAVEL_WARNINGS=$(grep -acE '\.WARNING:' "${LARAVEL_LOG}" 2>/dev/null || echo 0)

    log_out "  Application ERROR count   : ${LARAVEL_ERRORS}"
    log_out "  Application WARNING count : ${LARAVEL_WARNINGS}"
    log_out ""

    if [ "${LARAVEL_ERRORS}" -gt 0 ]; then
        log_out "  5 Most Recent Application Errors:"
        grep -aE '\.ERROR:' "${LARAVEL_LOG}" | tail -n 5 | while read -r LINE; do
            log_out "    ${LINE:0:110}..."
        done
    else
        log_out "  [OK] Zero application errors found in log."
    fi
else
    log_out "  [NOTICE] Laravel log file empty or not yet generated."
fi

log_out ""
log_out "=========================================================="
log_out "  Summary report complete. Saved to: ${REPORT_FILE}"
log_out "=========================================================="
exit 0

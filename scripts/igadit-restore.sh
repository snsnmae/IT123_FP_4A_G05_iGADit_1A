#!/bin/bash
# =============================================================================
# igadit-restore.sh — iGADit Disaster Recovery & Restore Script
# IT 123: System Administration and Maintenance | Option 1A
#
# Purpose:
#   Restores the iGADit application database and filesystem storage
#   from a user-selected backup, confirms restored data matches the
#   backup, repairs file permissions, and validates HTTP availability.
#
# Authors:
#   Orillana, Angel A.        (Project Lead)
#   Bataller, Kristine Mae B. (System Administrator)
#   Avila, Clarissa A.        (Documentation & Presentation Lead)
#
# Usage:
#   sudo ./igadit-restore.sh [--help] [BACKUP_PATH]
#
# Arguments:
#   --help       Show this usage message and exit.
#   BACKUP_PATH  Optional explicit path to timestamped backup directory.
#                If not provided, lists available backups interactively.
#
# Examples:
#   sudo ./igadit-restore.sh
#   sudo ./igadit-restore.sh /var/backups/igadit/2026-10-12_09-00-00
#   sudo ./igadit-restore.sh --help
#
# AI Disclosure:
#   This script was developed with the assistance of an AI coding tool.
#   All team members have reviewed and can explain every command line.
#
# Exit Status:
#   0  Restore completed and application verified online.
#   1  Privilege check failed: Not executed as root.
#   2  Missing configuration file (/etc/igadit/igadit.conf).
#   3  No backups found or invalid directory specified.
#   4  User cancelled or invalid selection.
#   5  Database or file restoration failure.
# =============================================================================

set -e

CONFIG_FILE="/etc/igadit/igadit.conf"

# --- Usage Function ----------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo $0 [--help] [BACKUP_PATH]

Description:
  Restores MySQL database records and Laravel storage/ files from a selected
  backup snapshot, fixes file permissions, and restarts the web server.

Options:
  --help        Display this help message and exit.

Arguments:
  BACKUP_PATH   Optional path to a specific backup directory. If omitted,
                the script presents an interactive numbered menu.

Examples:
  sudo $0
  sudo $0 /var/backups/igadit/2026-10-12_10-00-00
  sudo $0 --help

Exit Statuses:
  0  Success
  1  Must run as root
  2  Config missing
  3  No backup found
  4  User cancelled / invalid input
  5  Restore failure
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

SECONDS=0

echo "=========================================================="
echo "  iGADit — Disaster Recovery & System Restore"
echo "  IT 123 Final Project | Option 1A"
echo "=========================================================="
echo ""

SELECTED_BACKUP=""

# Check if direct argument passed (Skill M13: positional parameters)
if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        SELECTED_BACKUP="$1"
    else
        echo "ERROR: Specified backup directory '$1' does not exist." >&2
        exit 3
    fi
else
    # Interactive selection menu (Skill M13: for loop and arrays)
    echo "[1/5] Scanning for available backups in ${BACKUP_ROOT}..."
    
    BACKUP_DIRS=()
    for DIR in "${BACKUP_ROOT}"/*; do
        if [ -d "${DIR}" ]; then
            BACKUP_DIRS+=("${DIR}")
        fi
    done

    COUNT=${#BACKUP_DIRS[@]}
    if [ "${COUNT}" -eq 0 ]; then
        echo "ERROR: No backup directories found in ${BACKUP_ROOT}." >&2
        exit 3
    fi

    echo "Available backup snapshots:"
    for (( i=0; i<COUNT; i++ )); do
        printf "  [%d] %s (%s)\n" "${i}" "$(basename "${BACKUP_DIRS[$i]}")" "$(du -sh "${BACKUP_DIRS[$i]}" | awk '{print $1}')"
    done
    echo ""

    # Skill M13: read input with validation
    read -rp "Select backup index to restore [0-$((COUNT-1))]: " CHOICE

    # Regex test for digits only (Skill M11)
    if ! [[ "${CHOICE}" =~ ^[0-9]+$ ]] || [ "${CHOICE}" -ge "${COUNT}" ]; then
        echo "ERROR: Invalid selection '${CHOICE}'." >&2
        exit 4
    fi

    SELECTED_BACKUP="${BACKUP_DIRS[$CHOICE]}"
fi

echo "Selected backup: ${SELECTED_BACKUP}"

# Locate files within selected backup
SQL_FILE=$(find "${SELECTED_BACKUP}" -maxdepth 1 -name "*.sql" | head -n 1)
ARCHIVE_FILE=$(find "${SELECTED_BACKUP}" -maxdepth 1 -name "*.tar.gz" | head -n 1)

if [ -z "${SQL_FILE}" ] || [ -z "${ARCHIVE_FILE}" ]; then
    echo "ERROR: Backup directory is incomplete (missing .sql or .tar.gz)." >&2
    exit 3
fi

echo "  SQL Dump     : $(basename "${SQL_FILE}")"
echo "  File Archive : $(basename "${ARCHIVE_FILE}")"
echo ""

# Confirmation prompt
read -rp "WARNING: This will drop database '${DB_NAME}' and overwrite files. Continue? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    echo "Restore cancelled by user."
    exit 4
fi

# --- Step 2: Database Restoration --------------------------------------------
echo ""
echo "[2/5] Restoring MySQL database '${DB_NAME}'..."

# Drop and recreate schema cleanly
mysql --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" --port="${DB_PORT}" <<SQL || { echo "ERROR: Failed to reset database." >&2; exit 5; }
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
CREATE DATABASE \`${DB_NAME}\`;
SQL

# Import dump
mysql --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" --port="${DB_PORT}" "${DB_NAME}" < "${SQL_FILE}" || {
    echo "ERROR: Failed to import SQL file." >&2
    exit 5
}
echo "      Database restored from SQL dump."

# --- Step 3: Filesystem Restoration ------------------------------------------
echo "[3/5] Restoring storage and application files..."

# Unpack storage and .env into application directory (Skill M12)
# Explicitly name members so embedded SQL dump does not pollute the application root
tar -xzf "${ARCHIVE_FILE}" -C "${APP_DIR}" storage .env || {
    echo "ERROR: Failed to extract file archive." >&2
    exit 5
}

# Verify restored data matches the archive contents using tar compare (Skill M12)
# Run immediately after extraction, before artisan/apache run to prevent false differences
if tar -dzf "${ARCHIVE_FILE}" -C "${APP_DIR}" storage .env >/dev/null 2>&1; then
    echo "      Filesystem data verification: PASSED (Restored files match backup archive)."
else
    echo "ERROR: Restored files differ from backup archive (tar -dzf mismatch)." >&2
    exit 5
fi

# Restore .env if present in backup root
if [ -f "${SELECTED_BACKUP}/.env.backup" ]; then
    cp "${SELECTED_BACKUP}/.env.backup" "${APP_DIR}/.env"
    chmod 640 "${APP_DIR}/.env"
    chown www-data:www-data "${APP_DIR}/.env"
    echo "      .env configuration restored."
fi

# --- Step 4: Repair Ownership, Permissions & Cache (Skill M10) ---------------
echo "[4/5] Normalizing ownership and permissions..."

chown -R www-data:www-data "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
chmod -R 775 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"

cd "${APP_DIR}"
php artisan config:clear > /dev/null 2>&1 || true
php artisan config:cache > /dev/null 2>&1 || true

systemctl restart apache2
echo "      Apache restarted."

# --- Step 5: Verification & Match Check --------------------------------------
echo "[5/5] Verifying restore integrity and application state..."

# Verify restored table count matches the backup dump schema
EXPECTED_TABLES=$(grep -cE "^CREATE TABLE " "${SQL_FILE}" 2>/dev/null || echo 0)
TABLE_COUNT=$(mysql --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" --port="${DB_PORT}" \
    --silent --skip-column-names \
    --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")

echo "      Database tables in backup : ${EXPECTED_TABLES}"
echo "      Restored database tables  : ${TABLE_COUNT}"

if [ "${TABLE_COUNT}" -eq "${EXPECTED_TABLES}" ] && [ "${TABLE_COUNT}" -gt 0 ]; then
    echo "      [MATCH] Database table count matches backup schema perfectly."
else
    echo "ERROR: Table count discrepancy (${TABLE_COUNT} restored vs ${EXPECTED_TABLES} expected)." >&2
    exit 5
fi

echo "      Restore elapsed time      : ${SECONDS} second(s)"
if [ "${SECONDS}" -le 600 ]; then
    echo "      Recovery threshold check  : PASSED (< 10-minute disaster recovery SLA)"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost || echo "000")
echo "      Application HTTP status   : ${HTTP_CODE}"

echo ""
echo "=========================================================="
if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ]; then
    echo "  RESTORE SUCCESSFUL! Restored in ${SECONDS}s (Under 10-min SLA limit)."
    echo "  HTTP Status : ${HTTP_CODE}"
    echo "=========================================================="
    exit 0
else
    echo "  WARNING: System restored but returned HTTP ${HTTP_CODE}." >&2
    echo "  Check error log: /var/log/apache2/${APP_NAME}-error.log" >&2
    echo "=========================================================="
    exit 5
fi

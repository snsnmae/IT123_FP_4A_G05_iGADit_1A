#!/bin/bash
# =============================================================================
# igadit-backup.sh — iGADit Backup & Verification Script
# IT 123: System Administration and Maintenance | Option 1A
#
# Purpose:
#   Archives and compresses application files (specifically the Laravel
#   storage/ directory) and performs a full MySQL database dump into
#   a dated backup file. Verifies the archive's completeness and readability.
#
# Authors:
#   Orillana, Angel A.        (Project Lead)
#   Bataller, Kristine Mae B. (System Administrator)
#   Avila, Clarissa A.        (Documentation & Presentation Lead)
#
# Usage:
#   sudo ./igadit-backup.sh [--help] [DESTINATION_DIR]
#
# Arguments:
#   --help           Show this usage message and exit.
#   DESTINATION_DIR  Optional target folder for backup. Defaults to BACKUP_ROOT.
#
# Examples:
#   sudo ./igadit-backup.sh
#   sudo ./igadit-backup.sh /srv/backups
#   sudo ./igadit-backup.sh --help
#
# AI Disclosure:
#   This script was developed with the assistance of an AI coding tool.
#   All team members have reviewed and can explain every command line.
#
# Exit Status:
#   0  Backup created and verified successfully.
#   1  Privilege check failed: Not executed as root.
#   2  Missing configuration file (/etc/igadit/igadit.conf).
#   3  Database dump, archive creation, or integrity verification failed.
# =============================================================================

set -e

CONFIG_FILE="/etc/igadit/igadit.conf"

# --- Usage Function (Section 5.1 & Skill M13) --------------------------------
usage() {
    cat <<EOF
Usage: sudo $0 [--help] [DESTINATION_DIR]

Description:
  Creates a timestamped backup containing the MySQL database dump,
  the Laravel storage directory, and the .env file. Verifies archive integrity.

Options:
  --help           Display this help message and exit.

Arguments:
  DESTINATION_DIR  Target directory to store backups (default from config).

Examples:
  sudo $0
  sudo $0 /srv/backups
  sudo $0 --help

Exit Statuses:
  0  Success
  1  Must run as root
  2  Config file missing
  3  Backup or verification error
EOF
}

if [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# --- Privilege Check (Skill M08/M09) -----------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must run as root. Current UID is $(id -u)." >&2
    echo "       Run with: sudo $0" >&2
    exit 1
fi

# --- Configuration Validation ------------------------------------------------
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Missing configuration file at ${CONFIG_FILE}" >&2
    exit 2
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Optional destination argument (Skill M13: positional parameters)
TARGET_BASE="${BACKUP_ROOT}"
if [ -n "$1" ]; then
    TARGET_BASE="$1"
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="${TARGET_BASE}/${TIMESTAMP}"

echo "=========================================================="
echo "  iGADit — Application & Database Backup"
echo "  IT 123 Final Project | Option 1A"
echo "  Timestamp: ${TIMESTAMP}"
echo "=========================================================="
echo ""

# --- Step 1: Create Backup Directory -----------------------------------------
echo "[1/4] Preparing backup target directory..."
mkdir -p "${BACKUP_DIR}" || {
    echo "ERROR: Could not create directory ${BACKUP_DIR}" >&2
    exit 3
}
chmod 700 "${BACKUP_DIR}"
echo "      Target directory: ${BACKUP_DIR}"

# --- Step 2: Database Dump (Skill M04: chaining && and ||) -------------------
echo "[2/4] Exporting MySQL database '${DB_NAME}'..."
SQL_DUMP="${BACKUP_DIR}/${DB_NAME}_db_${TIMESTAMP}.sql"

mysqldump --user="${DB_USER}" \
          --password="${DB_PASS}" \
          --host="${DB_HOST}" \
          --port="${DB_PORT}" \
          --single-transaction \
          --no-tablespaces \
          --routines \
          --triggers \
          "${DB_NAME}" > "${SQL_DUMP}" \
          && echo "      mysqldump completed successfully." \
          || { echo "ERROR: mysqldump execution failed." >&2; exit 3; }

# Verify SQL dump is non-empty
if [ ! -s "${SQL_DUMP}" ]; then
    echo "ERROR: Database dump file is empty!" >&2
    exit 3
fi

# --- Step 3: Archive Storage & Configuration (Skill M12) ---------------------
echo "[3/4] Archiving Laravel storage and configuration..."
ARCHIVE_FILE="${BACKUP_DIR}/igadit_files_${TIMESTAMP}.tar.gz"

# Back up .env securely inside the backup bundle
cp "${APP_DIR}/.env" "${BACKUP_DIR}/.env.backup" 2>/dev/null || true
chmod 600 "${BACKUP_DIR}/.env.backup" 2>/dev/null || true

tar -czf "${ARCHIVE_FILE}" -C "${APP_DIR}" storage .env -C "${BACKUP_DIR}" "$(basename "${SQL_DUMP}")" \
    && echo "      Tarball created: ${ARCHIVE_FILE}" \
    || { echo "ERROR: tar failed to create archive." >&2; exit 3; }

# --- Step 4: Verification (Module 12: tar compare / list check) -------------
echo "[4/4] Verifying backup archive integrity..."

# Use tar -tzf and regex pattern to verify all critical components (Skill M11 & M12)
if tar -tzf "${ARCHIVE_FILE}" >/dev/null 2>&1 && tar -tzf "${ARCHIVE_FILE}" | grep -qE "^storage/" && \
   tar -tzf "${ARCHIVE_FILE}" | grep -qE "^\.env$" && \
   tar -tzf "${ARCHIVE_FILE}" | grep -qE "\.sql$"; then
    echo "      Archive verification: PASSED (storage/, .env, and SQL dump detected)."
else
    echo "ERROR: Archive verification FAILED. Archive content corrupted." >&2
    exit 3
fi

echo ""
echo "=========================================================="
echo "  BACKUP COMPLETED & VERIFIED"
echo "  Location: ${BACKUP_DIR}"
echo "----------------------------------------------------------"
for ITEM in "${BACKUP_DIR}"/*; do
    printf "  %-35s %s\n" "$(basename "${ITEM}")" "$(du -sh "${ITEM}" | awk '{print $1}')"
done
echo "=========================================================="
exit 0

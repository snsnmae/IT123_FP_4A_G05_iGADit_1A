#!/bin/bash
# =============================================================================
# igadit-install.sh — iGADit Platform Installation & Deployment Script
# IT 123: System Administration and Maintenance | Option 1A
#
# Purpose:
#   Prepares a clean Ubuntu 24.04 LTS server and deploys the iGADit
#   web application. Installs Apache 2, PHP 8.2 with required modules,
#   MySQL Server, and Composer. Clones or unpacks the application,
#   configures Apache VirtualHost, creates the MySQL database/user,
#   runs Laravel migrations and seeders, sets ownership and permissions,
#   and performs an HTTP verification test.
#
# Authors:
#   Orillana, Angel A.        (Project Lead)
#   Bataller, Kristine Mae B. (System Administrator)
#   Avila, Clarissa A.        (Documentation & Presentation Lead)
#
# Usage:
#   sudo ./igadit-install.sh [--help] [SOURCE_PATH]
#
# Arguments:
#   --help       Display this usage message and exit.
#   SOURCE_PATH  Optional local tarball or directory containing iGADit code.
#                If omitted, clones from GitHub (requires internet).
#
# Example:
#   sudo ./igadit-install.sh
#   sudo ./igadit-install.sh /home/igadit/igadit-offline.tar.gz
#
# AI Disclosure:
#   This script was developed with the assistance of an AI coding tool.
#   All team members have reviewed and can explain every command line.
#
# Exit Status:
#   0  Success: Platform installed and application responds HTTP 200/302.
#   1  Privilege check failed: Not executed as root.
#   2  Missing configuration file (/etc/igadit/igadit.conf).
#   3  Installation or dependency error occurred.
# =============================================================================

set -e

CONFIG_FILE="/etc/igadit/igadit.conf"

# --- Usage Function (Section 5.1: Usage with --help & Example) ---------------
usage() {
    cat <<EOF
Usage: sudo $0 [--help] [SOURCE_PATH]

Description:
  Installs the Apache, PHP 8.2, and MySQL platform on Ubuntu Server 24.04 LTS,
  sets up the database, and deploys the iGADit Laravel application.

Options:
  --help        Show this help message and exit.

Arguments:
  SOURCE_PATH   Optional path to offline archive or pre-cloned directory.
                If omitted, the script clones from GitHub repository.

Examples:
  sudo $0
  sudo $0 /home/igadit/igadit-bundle.tar.gz
  sudo $0 --help

Exit Statuses:
  0  Success
  1  Root privileges required
  2  Config file missing
  3  Installation step failed
EOF
}

# Check for --help option (Skill M13: positional parameter $1)
if [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# --- Privilege Check (Section 5.1 & Skill M08/M09) --------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must be run as root. Current UID is $(id -u)." >&2
    echo "       Please execute with sudo: sudo $0" >&2
    exit 1
fi

# --- Configuration Validation (Section 5.1: no hardcoded secrets) ------------
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Configuration file not found at ${CONFIG_FILE}" >&2
    echo "       Setup /etc/igadit/igadit.conf with chmod 600 before running." >&2
    exit 2
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

OPTIONAL_SOURCE="$1"

echo "=========================================================="
echo "  iGADit — Server Provisioning & Deployment Script"
echo "  IT 123 Final Project | Option 1A"
echo "=========================================================="
echo ""

# --- Step 1: Platform Installation (Apache, PHP 8.2, MySQL) ------------------
echo "[1/7] Installing server platform packages..."

# Using an array of required platform packages (Skill M04)
CORE_PACKAGES=(
    apache2
    "php${PHP_VER}"
    "php${PHP_VER}-cli"
    "php${PHP_VER}-mysql"
    "php${PHP_VER}-xml"
    "php${PHP_VER}-mbstring"
    "php${PHP_VER}-zip"
    "php${PHP_VER}-bcmath"
    "php${PHP_VER}-curl"
    "libapache2-mod-php${PHP_VER}"
    mysql-server
    git
    curl
    unzip
)

# Check if apt cache is available or if offline
if apt-get update -y > /dev/null 2>&1; then
    echo "      Package lists updated."
else
    echo "      [NOTE] Operating offline or cached packages only."
fi

apt-get install -y "${CORE_PACKAGES[@]}" || {
    echo "ERROR: Failed to install platform packages." >&2
    exit 3
}

# Install or verify Composer
if ! command -v composer &> /dev/null; then
    echo "      Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || {
        echo "ERROR: Composer installation failed." >&2
        exit 3
    }
fi
echo "      Platform packages installed successfully."

# --- Step 2: Deploy Application Source Files ---------------------------------
echo "[2/7] Deploying application source files..."

mkdir -p "$(dirname "${APP_DIR}")"

if [ -n "${OPTIONAL_SOURCE}" ] && [ -f "${OPTIONAL_SOURCE}" ]; then
    echo "      Extracting offline source bundle: ${OPTIONAL_SOURCE}..."
    mkdir -p "${APP_DIR}"
    tar -xzf "${OPTIONAL_SOURCE}" -C "${APP_DIR}" || {
        echo "ERROR: Failed to extract ${OPTIONAL_SOURCE}" >&2
        exit 3
    }
elif [ -d "${APP_DIR}/.git" ]; then
    echo "      Existing Git directory found. Updating repo..."
    git -C "${APP_DIR}" pull || true
else
    echo "      Cloning fresh repository from ${REPO_URL}..."
    git clone "${REPO_URL}" "${APP_DIR}" || {
        echo "ERROR: Git clone failed. If offline, pass an archive path as \$1." >&2
        exit 3
    }
fi
echo "      Source files ready in ${APP_DIR}."

# --- Step 3: Configure Apache VirtualHost ------------------------------------
echo "[3/7] Setting up Apache VirtualHost configuration..."

VHOST_FILE="/etc/apache2/sites-available/${APP_NAME}.conf"
cat > "${VHOST_FILE}" <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot ${APP_DIR}/public

    <Directory ${APP_DIR}/public>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${APP_NAME}-error.log
    CustomLog \${APACHE_LOG_DIR}/${APP_NAME}-access.log combined
</VirtualHost>
EOF

a2enmod rewrite > /dev/null 2>&1
a2ensite "${APP_NAME}.conf" > /dev/null 2>&1
a2dissite 000-default.conf > /dev/null 2>&1
echo "      Apache VirtualHost enabled."

# --- Step 4: Create MySQL Database & User (Skill M08/M09) --------------------
echo "[4/7] Provisioning MySQL database and user credentials..."

systemctl start mysql

mysql -u root <<SQL || { echo "ERROR: MySQL setup failed." >&2; exit 3; }
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "      Database '${DB_NAME}' and user '${DB_USER}' ready."

# --- Step 5: Configure Laravel (.env, dependencies, migrations) --------------
echo "[5/7] Initializing Laravel environment..."
cd "${APP_DIR}"

if [ ! -f "${APP_DIR}/.env" ]; then
    if [ -f "${APP_DIR}/.env.example" ]; then
        cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
    else
        touch "${APP_DIR}/.env"
    fi
fi

# Configure database variables in .env (Skill M04: quoting and sed replacement)
sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" "${APP_DIR}/.env"
sed -i "s|^DB_HOST=.*|DB_HOST=${DB_HOST}|" "${APP_DIR}/.env"
sed -i "s|^DB_PORT=.*|DB_PORT=${DB_PORT}|" "${APP_DIR}/.env"
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" "${APP_DIR}/.env"
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" "${APP_DIR}/.env"
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=\"${DB_PASS}\"|" "${APP_DIR}/.env"

# Clear any stale cached provider manifests from host
rm -f "${APP_DIR}/bootstrap/cache/packages.php" "${APP_DIR}/bootstrap/cache/services.php"

# Run Composer dependencies (if vendor doesn't exist)
if [ ! -d "${APP_DIR}/vendor" ]; then
    composer install --no-dev --optimize-autoloader --no-interaction || true
fi

# Clear any cached configuration or packages
php artisan package:discover --ansi || true

# Artisan setup: Only generate key if APP_KEY is empty to prevent data encryption loss (SafeEncrypted models)
if grep -qE "^APP_KEY=base64:.+" "${APP_DIR}/.env" 2>/dev/null; then
    echo "      Existing APP_KEY preserved (prevents data encryption loss)."
else
    php artisan key:generate --force || true
fi
php artisan migrate --force || {
    echo "ERROR: Database migrations failed." >&2
    exit 3
}
php artisan db:seed --force || true
php artisan storage:link || true
php artisan config:cache || true

echo "      Laravel configuration completed."

# --- Step 6: Set Ownership & Permissions (Skill M10) ------------------------
echo "[6/7] Applying least-privilege permissions..."

chown -R www-data:www-data "${APP_DIR}"
chmod -R 755 "${APP_DIR}"

# Writable directories for web daemon
chmod -R 775 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
chown -R www-data:www-data "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"

# Protect .env so normal users cannot inspect credentials
chmod 640 "${APP_DIR}/.env"
chown www-data:www-data "${APP_DIR}/.env"

systemctl restart apache2
echo "      Apache and directory permissions configured."

# --- Step 7: Check That Application Responds (Section 3.1 Step 5) ------------
echo "[7/7] Verifying application response..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost || echo "000")

echo ""
echo "=========================================================="
if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ]; then
    echo "  INSTALLATION SUCCESSFUL!"
    echo "  HTTP Status : ${HTTP_CODE}"
    echo "  App Location: http://localhost"
    echo "=========================================================="
    exit 0
else
    echo "  INSTALLATION FAILED OR APPLICATION UNRESPONSIVE" >&2
    echo "  HTTP Status : ${HTTP_CODE}" >&2
    echo "  Review log  : /var/log/apache2/${APP_NAME}-error.log" >&2
    echo "=========================================================="
    exit 3
fi

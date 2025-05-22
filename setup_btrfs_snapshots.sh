#!/bin/bash

# ==============================================================================
# Comprehensive Btrfs Snapshot Setup Script for Arch Linux
# ==============================================================================
#
# IMPORTANT:
# 1. READ THIS ENTIRE SCRIPT CAREFULLY BEFORE RUNNING.
# 2. RUN THIS SCRIPT AS ROOT (e.g., sudo bash this_script.sh).
# 3. ENSURE YOU HAVE BACKUPS OF YOUR SYSTEM AND DATA.
# 4. This script is for Arch Linux with Btrfs root and GRUB.
# 5. It assumes a common Btrfs layout (e.g., '@' mounted as '/').
# 6. An internet connection is required.
#
# This script automates:
# - Installation of btrfs-progs, git, base-devel, and timeshift.
# - Creation of /.snapshots subvolume.
# - Creation of snapshot creation script.
# - Creation of systemd service for boot snapshots.
# - Installation of grub-btrfs from AUR.
# - Configuration and enabling of grub-btrfsd path/service.
# - Creation of snapshot management script.
# - Creation of systemd service and timer for snapshot cleanup.
# - Conditional enabling of custom automation OR guidance for Timeshift.
# - Initial GRUB configuration update.
#
# ==============================================================================

# --- Configuration (Match these with your preferences if needed) ---
SNAPSHOT_SUBVOLUME_PATH="/.snapshots"
SNAPSHOT_CREATION_SCRIPT_PATH="/usr/local/bin/create-btrfs-boot-snapshot.sh"
SNAPSHOT_CREATION_SERVICE_PATH="/etc/systemd/system/btrfs-boot-snapshot.service"
SNAPSHOT_MANAGEMENT_SCRIPT_PATH="/usr/local/bin/manage-btrfs-snapshots.sh"
SNAPSHOT_CLEANUP_SERVICE_PATH="/etc/systemd/system/btrfs-snapshot-cleanup.service"
SNAPSHOT_CLEANUP_TIMER_PATH="/etc/systemd/system/btrfs-snapshot-cleanup.timer"

# Snapshot manager selection
SNAPSHOT_MANAGER="auto" # Options: "timeshift", "btrfs-assistant", "custom", "auto"

# For snapshot creation script
SOURCE_SUBVOLUME_FOR_SNAPSHOT="/" # Assumes '/' is the Btrfs subvolume to snapshot (e.g. '@')
SNAPSHOT_PREFIX_IN_SCRIPT="boot_auto_snap"

# For snapshot management script
SNAPSHOT_PREFIX_FOR_MANAGEMENT="boot_auto_snap_" # Must match creation script's prefix + underscore if applicable
KEEP_LATEST_N_SNAPSHOTS=7

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_warning() {
    echo "[WARNING] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

confirm_action() {
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# --- Pre-flight Checks ---
log_info "Starting Btrfs snapshot setup script..."

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
  log_error "This script must be run as root. Please use sudo."
  exit 1
fi

# Check for SUDO_USER
if [ -z "${SUDO_USER}" ] || [ "${SUDO_USER}" == "root" ]; then
    log_error "This script needs to be run with sudo by a non-root user to build AUR packages."
    log_error "If you are running from a root shell, please 'su - <username>' then run with 'sudo'."
    exit 1
fi
ORIGINAL_USER="${SUDO_USER}"
ORIGINAL_UID=$(id -u "${ORIGINAL_USER}")
ORIGINAL_GID=$(id -g "${ORIGINAL_USER}")

# Check for Btrfs root
if ! findmnt -n -o FSTYPE --target / | grep -q "btrfs"; then
    log_error "Root filesystem is not Btrfs. This script is for Btrfs systems only."
    exit 1
fi

# Check for GRUB
if [ ! -d "/boot/grub" ] || ! command -v grub-mkconfig &> /dev/null; then
    log_error "GRUB bootloader not detected or grub-mkconfig not found. This script requires GRUB."
    exit 1
fi

log_info "Pre-flight checks passed."
if ! confirm_action "Do you want to proceed with the setup? This will modify your system."; then
    log_info "Setup aborted by user."
    exit 0
fi

# --- 1. Install Prerequisites ---
log_info "Installing prerequisite packages (btrfs-progs, git, base-devel, timeshift)..."
# Attempt to install
    log_warning "Pacman command for prerequisites encountered issues. Continuing, but Timeshift might not be installed."
    # We don't exit here, as other parts might still be useful, and Timeshift presence is checked later.
fi


# --- 2. Create Snapshot Subvolume ---
log_info "Setting up snapshot subvolume at ${SNAPSHOT_SUBVOLUME_PATH}..."
if btrfs subvolume show "${SNAPSHOT_SUBVOLUME_PATH}" >/dev/null 2>&1; then
    log_info "${SNAPSHOT_SUBVOLUME_PATH} already exists and is a subvolume."
else
    if [ -d "${SNAPSHOT_SUBVOLUME_PATH}" ]; then
        log_warning "${SNAPSHOT_SUBVOLUME_PATH} exists as a regular directory."
        if confirm_action "Do you want to attempt to remove it and create a subvolume? (Ensure it's empty or backed up)"; then
            if ! rm -rf "${SNAPSHOT_SUBVOLUME_PATH}"; then
                 log_error "Failed to remove existing directory ${SNAPSHOT_SUBVOLUME_PATH}. Please handle manually."
                 exit 1
            fi
        else
            log_error "Cannot proceed with ${SNAPSHOT_SUBVOLUME_PATH} as a regular directory. Please handle manually."
            exit 1
        fi
    fi
    log_info "Creating Btrfs subvolume at ${SNAPSHOT_SUBVOLUME_PATH}..."
    if btrfs subvolume create "${SNAPSHOT_SUBVOLUME_PATH}"; then
        log_info "Subvolume ${SNAPSHOT_SUBVOLUME_PATH} created successfully."
    else
        log_error "Failed to create subvolume ${SNAPSHOT_SUBVOLUME_PATH}."
        exit 1
    fi
fi

# --- 3. Create Snapshot Creation Script ---
log_info "Creating snapshot creation script at ${SNAPSHOT_CREATION_SCRIPT_PATH}..."
mkdir -p "$(dirname "${SNAPSHOT_CREATION_SCRIPT_PATH}")"
cat << EOF > "${SNAPSHOT_CREATION_SCRIPT_PATH}"
#!/bin/bash
# Script to create a read-only Btrfs snapshot of the root subvolume on boot.

# --- Configuration ---
SOURCE_SUBVOLUME="${SOURCE_SUBVOLUME_FOR_SNAPSHOT}"
SNAPSHOT_DIR="${SNAPSHOT_SUBVOLUME_PATH}"
SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX_IN_SCRIPT}"
# --- End Configuration ---

if [[ "\$(id -u)" -ne 0 ]]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

if ! findmnt -n -o FSTYPE --target "\${SOURCE_SUBVOLUME}" | grep -q "btrfs"; then
    echo "Error: Source \${SOURCE_SUBVOLUME} is not on a Btrfs filesystem." >&2
    exit 1
fi

if ! btrfs subvolume show "\${SNAPSHOT_DIR}" >/dev/null 2>&1 && ! [ -d "\${SNAPSHOT_DIR}" ]; then
    echo "Error: Snapshot directory \${SNAPSHOT_DIR} does not exist or is not accessible." >&2
    exit 1
fi
if ! findmnt -n -o FSTYPE --target "\${SNAPSHOT_DIR}" | grep -q "btrfs"; then
    echo "Error: Snapshot directory \${SNAPSHOT_DIR} is not on a Btrfs filesystem." >&2
    exit 1
fi

TIMESTAMP=\$(date +"%Y-%m-%d_%H%M%S")
SNAPSHOT_NAME="\${SNAPSHOT_PREFIX}_\${TIMESTAMP}"
SNAPSHOT_PATH="\${SNAPSHOT_DIR}/\${SNAPSHOT_NAME}"

echo "Attempting to create Btrfs snapshot:"
echo "  Source: \${SOURCE_SUBVOLUME}"
echo "  Destination: \${SNAPSHOT_PATH}"

if btrfs subvolume snapshot -r "\${SOURCE_SUBVOLUME}" "\${SNAPSHOT_PATH}"; then
  echo "Successfully created read-only snapshot: \${SNAPSHOT_PATH}"
  sync
else
  echo "Error: Failed to create snapshot \${SNAPSHOT_PATH}." >&2
  exit 1
fi
exit 0
EOF

if chmod +x "${SNAPSHOT_CREATION_SCRIPT_PATH}"; then
    log_info "Snapshot creation script created and made executable."
else
    log_error "Failed to make snapshot creation script executable."
    exit 1
fi

# --- 4. Systemd Service for Boot Snapshots ---
log_info "Creating systemd service for boot snapshots at ${SNAPSHOT_CREATION_SERVICE_PATH}..."
mkdir -p "$(dirname "${SNAPSHOT_CREATION_SERVICE_PATH}")"
cat << EOF > "${SNAPSHOT_CREATION_SERVICE_PATH}"
[Unit]
Description=Create BTRFS snapshot on boot (Custom Script)
Documentation=man:btrfs-subvolume(8)
DefaultDependencies=no
After=local-fs.target time-sync.target
Before=sysinit.target shutdown.target
ConditionPathExists=${SNAPSHOT_CREATION_SCRIPT_PATH}
ConditionFileSystem=/ btrfs

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=${SNAPSHOT_CREATION_SCRIPT_PATH}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=sysinit.target
EOF
log_info "Systemd service for boot snapshots created."

# --- 5. Installing and Configuring grub-btrfs ---
log_info "Setting up grub-btrfs..."
GRUB_BTRFS_INSTALLED_BY_SCRIPT=false
if command -v grub-btrfs &> /dev/null; then
    log_info "grub-btrfs is already installed."
else
    log_info "grub-btrfs not found. Attempting to install from AUR..."
    TEMP_AUR_DIR="/tmp/grub-btrfs-aur-build-${ORIGINAL_USER}" # User-specific temp dir
    rm -rf "${TEMP_AUR_DIR}"
    mkdir -p "${TEMP_AUR_DIR}"
    chown "${ORIGINAL_UID}:${ORIGINAL_GID}" "${TEMP_AUR_DIR}" # Change ownership for makepkg

    if sudo -u "${ORIGINAL_USER}" git clone https://aur.archlinux.org/grub-btrfs.git "${TEMP_AUR_DIR}"; then
        log_info "Cloned grub-btrfs AUR repository as user ${ORIGINAL_USER}."
        cd "${TEMP_AUR_DIR}" || { log_error "Failed to cd into ${TEMP_AUR_DIR}"; exit 1; }
        
        log_info "Building grub-btrfs as user ${ORIGINAL_USER}..."
        if sudo -u "${ORIGINAL_USER}" makepkg -s --noconfirm; then
            log_info "grub-btrfs built successfully by ${ORIGINAL_USER}."
            PACKAGE_FILE=$(find . -maxdepth 1 -name "grub-btrfs*.pkg.tar.*" -print -quit)
            if [ -n "${PACKAGE_FILE}" ]; then
                log_info "Installing ${PACKAGE_FILE}..."
                if pacman -U --noconfirm "${PACKAGE_FILE}"; then
                    log_info "grub-btrfs installed successfully."
                    GRUB_BTRFS_INSTALLED_BY_SCRIPT=true
                    log_info "Reloading systemd daemon after grub-btrfs installation..."
                    systemctl daemon-reload # Reload here so systemd sees new units from grub-btrfs
                else
                    log_error "Failed to install built grub-btrfs package."
                fi # End pacman -U
            else
                log_error "Could not find built grub-btrfs package file."
            fi # End find PACKAGE_FILE
        else
            log_error "Failed to build grub-btrfs as user ${ORIGINAL_USER}."
        fi # End makepkg
        cd .. 
        rm -rf "${TEMP_AUR_DIR}"
    else
        log_error "Failed to clone grub-btrfs AUR repository as user ${ORIGINAL_USER}."
        rm -rf "${TEMP_AUR_DIR}" 
    fi # End git clone
    
    if ! ${GRUB_BTRFS_INSTALLED_BY_SCRIPT}; then
        log_error "grub-btrfs installation failed. Automatic GRUB updates for snapshots might not work."
        # exit 1 # Optionally exit if grub-btrfs is critical for the user
    fi
fi


# Configure grub-btrfs
GRUB_BTRFS_CONFIG_DIR="/etc/default/grub-btrfs"
GRUB_BTRFS_CONFIG_FILE="${GRUB_BTRFS_CONFIG_DIR}/config"
mkdir -p "${GRUB_BTRFS_CONFIG_DIR}"
if [ ! -f "${GRUB_BTRFS_CONFIG_FILE}" ]; then
    log_info "Creating default grub-btrfs config at ${GRUB_BTRFS_CONFIG_FILE}."
    cat << EOF_GRUB_BTRFS > "${GRUB_BTRFS_CONFIG_FILE}"
GRUB_BTRFS_SNAPSHOT_DIR="${SNAPSHOT_SUBVOLUME_PATH}"
EOF_GRUB_BTRFS
else
    log_info "grub-btrfs config file ${GRUB_BTRFS_CONFIG_FILE} already exists. Ensuring SNAPSHOT_DIR is set."
    if ! grep -q "^GRUB_BTRFS_SNAPSHOT_DIR=" "${GRUB_BTRFS_CONFIG_FILE}"; then
        log_info "GRUB_BTRFS_SNAPSHOT_DIR not found, adding it."
        echo "GRUB_BTRFS_SNAPSHOT_DIR=\"${SNAPSHOT_SUBVOLUME_PATH}\"" >> "${GRUB_BTRFS_CONFIG_FILE}"
    elif ! grep -Fq "GRUB_BTRFS_SNAPSHOT_DIR=\"${SNAPSHOT_SUBVOLUME_PATH}\"" "${GRUB_BTRFS_CONFIG_FILE}"; then # Use -F for fixed string
        log_info "Updating GRUB_BTRFS_SNAPSHOT_DIR in ${GRUB_BTRFS_CONFIG_FILE}."
        # Use a temporary file for sed to avoid issues with special characters in path
        TMP_SED_PATTERN="GRUB_BTRFS_SNAPSHOT_DIR=\"${SNAPSHOT_SUBVOLUME_PATH}\""
        sed -i "s|^GRUB_BTRFS_SNAPSHOT_DIR=.*|${TMP_SED_PATTERN}|" "${GRUB_BTRFS_CONFIG_FILE}"
    fi
fi

# Systemd unit for grub-btrfs monitoring
GRUB_BTRFS_MONITOR_UNIT=""
# Check for .path units first, then .service units
# Using grep -Eoq for exact whole word match of known unit names
if systemctl list-unit-files | grep -Eoq '^\s*grub-btrfsd\.path\s'; then
    GRUB_BTRFS_MONITOR_UNIT="grub-btrfsd.path"
elif systemctl list-unit-files | grep -Eoq '^\s*grub-btrfs\.path\s'; then
    GRUB_BTRFS_MONITOR_UNIT="grub-btrfs.path"
elif systemctl list-unit-files | grep -Eoq '^\s*grub-btrfsd\.service\s'; then
    GRUB_BTRFS_MONITOR_UNIT="grub-btrfsd.service"
elif systemctl list-unit-files | grep -Eoq '^\s*grub-btrfs\.service\s'; then
    GRUB_BTRFS_MONITOR_UNIT="grub-btrfs.service"
fi

if [ -n "$GRUB_BTRFS_MONITOR_UNIT" ]; then
    log_info "Found grub-btrfs monitoring unit: ${GRUB_BTRFS_MONITOR_UNIT}"
else
    log_warning "Could not automatically find a grub-btrfs monitoring unit (.path or .service)."
    log_warning "Automatic GRUB updates upon snapshot changes might not work without manual intervention."
fi


# --- 6. Create Snapshot Management Script ---
log_info "Creating snapshot management script at ${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}..."
mkdir -p "$(dirname "${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}")"
cat << EOF > "${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}"
#!/bin/bash
# Basic script to manage Btrfs snapshots by keeping the latest N.

# --- Configuration ---
SNAPSHOT_DIR="${SNAPSHOT_SUBVOLUME_PATH}"
SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX_FOR_MANAGEMENT}"
KEEP_LATEST_N=${KEEP_LATEST_N_SNAPSHOTS}
# --- End Configuration ---

if [[ "\$(id -u)" -ne 0 ]]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

if [ ! -d "\${SNAPSHOT_DIR}" ]; then
    echo "Error: Snapshot directory \${SNAPSHOT_DIR} does not exist." >&2
    exit 1
fi

mapfile -t snapshots < <(find "\${SNAPSHOT_DIR}" -maxdepth 1 -type d -name "\${SNAPSHOT_PREFIX}*" -print0 | xargs -0 ls -1dtr)

num_snapshots=\${#snapshots[@]}
num_to_delete=\$((num_snapshots - KEEP_LATEST_N))

echo "Found \${num_snapshots} snapshots matching prefix '\${SNAPSHOT_PREFIX}' in \${SNAPSHOT_DIR}."
echo "Configured to keep the latest \${KEEP_LATEST_N}."

if [[ \${num_to_delete} -le 0 ]]; then
  echo "No snapshots need to be deleted."
  exit 0
fi

echo "Will attempt to delete \${num_to_delete} older snapshot(s):"

deleted_count=0
for ((i=0; i<num_to_delete; i++)); do
  snapshot_to_delete="\${snapshots[i]}"
  if [[ -n "\${snapshot_to_delete}" ]]; then
    echo "Deleting: \${snapshot_to_delete}"
    if btrfs subvolume delete "\${snapshot_to_delete}"; then
      echo "Successfully deleted \${snapshot_to_delete}"
      deleted_count=\$((deleted_count + 1))
    else
      echo "Error: Failed to delete \${snapshot_to_delete}." >&2
    fi
  fi
done

echo "Finished. Deleted \${deleted_count} snapshot(s)."
exit 0
EOF

if chmod +x "${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}"; then
    log_info "Snapshot management script created and made executable."
else
    log_error "Failed to make snapshot management script executable."
    exit 1
fi

# --- 7. Systemd Service and Timer for Snapshot Cleanup ---
log_info "Creating systemd service for snapshot cleanup at ${SNAPSHOT_CLEANUP_SERVICE_PATH}..."
mkdir -p "$(dirname "${SNAPSHOT_CLEANUP_SERVICE_PATH}")"
cat << EOF > "${SNAPSHOT_CLEANUP_SERVICE_PATH}"
[Unit]
Description=Clean up old BTRFS snapshots (Custom Script)
Documentation=man:btrfs-subvolume(8)
ConditionPathExists=${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}

[Service]
Type=oneshot
ExecStart=${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}
StandardOutput=journal
StandardError=journal
EOF
log_info "Systemd service for snapshot cleanup created."

log_info "Creating systemd timer for snapshot cleanup at ${SNAPSHOT_CLEANUP_TIMER_PATH}..."
mkdir -p "$(dirname "${SNAPSHOT_CLEANUP_TIMER_PATH}")"
cat << EOF > "${SNAPSHOT_CLEANUP_TIMER_PATH}"
[Unit]
Description=Run BTRFS snapshot cleanup daily (Custom Script)

[Timer]
OnCalendar=daily
Persistent=true
Unit=$(basename "${SNAPSHOT_CLEANUP_SERVICE_PATH}")

[Install]
WantedBy=timers.target
EOF
log_info "Systemd timer for snapshot cleanup created."

# --- 8. Final Steps: Reload Daemons, Enable Services, Update GRUB ---
log_info "Reloading systemd daemon (final time before enabling services)..."
if systemctl daemon-reload; then
    log_info "Systemd daemon reloaded."
else
    log_error "Failed to reload systemd daemon."
fi

log_info "Configuring systemd services based on Timeshift installation..."
SERVICES_TO_ENABLE_AND_START=() # Units to enable and start
SERVICES_TO_ENABLE_ONLY=()    # Units to only enable (like boot snapshot service)

if command -v timeshift &> /dev/null; then
    log_info "Timeshift is installed. It will be the primary snapshot manager."
    log_info "Disabling this script's custom automated snapshot creation and cleanup services."

    if systemctl list-unit-files | grep -q "^$(basename "${SNAPSHOT_CREATION_SERVICE_PATH}")"; then
        log_info "Ensuring custom boot snapshot service is disabled: $(basename "${SNAPSHOT_CREATION_SERVICE_PATH}")"
        systemctl disable --now "$(basename "${SNAPSHOT_CREATION_SERVICE_PATH}")" &>/dev/null
    fi
    if systemctl list-unit-files | grep -q "^$(basename "${SNAPSHOT_CLEANUP_TIMER_PATH}")"; then
        log_info "Ensuring custom snapshot cleanup timer is disabled: $(basename "${SNAPSHOT_CLEANUP_TIMER_PATH}")"
        systemctl disable --now "$(basename "${SNAPSHOT_CLEANUP_TIMER_PATH}")" &>/dev/null
        systemctl stop "$(basename "${SNAPSHOT_CLEANUP_SERVICE_PATH}")" &>/dev/null 
    fi
else
    log_warning "Timeshift is not installed or not found."
    log_info "Enabling this script's custom automated snapshot creation and cleanup services."
    SERVICES_TO_ENABLE_ONLY+=( "$(basename "${SNAPSHOT_CREATION_SERVICE_PATH}")" )
    SERVICES_TO_ENABLE_AND_START+=( "$(basename "${SNAPSHOT_CLEANUP_TIMER_PATH}")" )
fi

# Always try to enable and start grub-btrfs monitoring unit
if [ -n "$GRUB_BTRFS_MONITOR_UNIT" ]; then
    SERVICES_TO_ENABLE_AND_START+=("$GRUB_BTRFS_MONITOR_UNIT")
else
    log_warning "Skipping enablement/start of grub-btrfs monitoring unit as it was not found."
fi

log_info "Enabling relevant systemd units..."
for unit_to_enable in "${SERVICES_TO_ENABLE_ONLY[@]}" "${SERVICES_TO_ENABLE_AND_START[@]}"; do
    if systemctl list-unit-files | grep -Eq "^\s*${unit_to_enable}\s"; then # More precise grep
        if systemctl is-enabled "${unit_to_enable}" &> /dev/null; then
            log_info "${unit_to_enable} is already enabled."
        else
            if systemctl enable "${unit_to_enable}"; then
                log_info "${unit_to_enable} enabled successfully."
            else
                log_error "Failed to enable ${unit_to_enable}."
            fi
        fi
    else
        log_warning "Unit ${unit_to_enable} not found during enable phase. Skipping."
    fi
done

log_info "Starting relevant systemd units..."
for unit_to_start in "${SERVICES_TO_ENABLE_AND_START[@]}"; do
    if systemctl list-unit-files | grep -Eq "^\s*${unit_to_start}\s"; then # More precise grep
        if systemctl is-active "${unit_to_start}" &> /dev/null; then
            log_info "${unit_to_start} is already active."
        else
            if systemctl start "${unit_to_start}"; then
                log_info "${unit_to_start} started successfully."
            else
                log_error "Failed to start ${unit_to_start}."
            fi
        fi
    else
        log_warning "Unit ${unit_to_start} not found during start phase. Skipping."
    fi
done


log_info "Generating initial GRUB configuration..."
log_info "This may take a moment. If you have existing snapshots, they should be detected."
if grub-mkconfig -o /boot/grub/grub.cfg; then
    log_info "GRUB configuration updated successfully."
else
    log_error "Failed to update GRUB configuration. You may need to run 'sudo grub-mkconfig -o /boot/grub/grub.cfg' manually."
fi

# --- Completion ---
log_info "=============================================================================="
log_info "Btrfs snapshot setup script finished."

if command -v timeshift &> /dev/null; then
    log_info "Timeshift has been installed."
    log_info "It is recommended to use Timeshift as your primary snapshot management tool."
    log_info "The script's custom automated boot snapshot and cleanup services have been DISABLED to prevent conflicts."
    log_info "What's next with Timeshift:"
    log_info "1. Launch Timeshift (usually from your application menu or by typing 'sudo timeshift-launcher')."
    log_info "2. In the Setup Wizard, select 'BTRFS' as the Snapshot Type."
    log_info "3. Select your BTRFS system partition (usually where '/' is mounted)."
    log_info "4. Select '${SNAPSHOT_SUBVOLUME_PATH}' as the Snapshot Location if prompted, or ensure Timeshift is configured to use it."
    log_info "5. Configure your desired snapshot levels (e.g., Boot, Hourly, Daily, Weekly, Monthly) and retention settings in Timeshift."
    log_info "6. Timeshift will then manage automated snapshots."
    log_info "7. The 'grub-btrfs' integration (for GRUB menu entries) installed by this script should work with Timeshift's snapshots."
    if [ -n "$GRUB_BTRFS_MONITOR_UNIT" ]; then
        log_info "   Ensure '${GRUB_BTRFS_MONITOR_UNIT}' is active: 'sudo systemctl status ${GRUB_BTRFS_MONITOR_UNIT}'"
    else
        log_warning "   grub-btrfs monitoring unit was not found by the script. Manual check/setup might be needed for automatic GRUB updates."
        log_warning "   Look for 'grub-btrfsd.path' and try 'sudo systemctl enable --now grub-btrfsd.path'"
    fi
else
    log_warning "Timeshift installation failed or was not found."
    log_info "The script's custom automated boot snapshot and cleanup services have been enabled."
    log_info "What's next with the custom script setup:"
    log_info "1. Reboot your system to ensure the boot snapshot service runs."
    log_info "2. After reboot, check GRUB menu for snapshot entries."
    log_info "3. Verify snapshots are created in ${SNAPSHOT_SUBVOLUME_PATH} by the script."
    log_info "4. Monitor snapshot cleanup: 'sudo systemctl list-timers --all' and check logs."
    log_info "   'journalctl -u $(basename "${SNAPSHOT_CLEANUP_SERVICE_PATH}")'"
    if [ -n "$GRUB_BTRFS_MONITOR_UNIT" ]; then
         log_info "   Ensure '${GRUB_BTRFS_MONITOR_UNIT}' is active for GRUB updates."
    else
        log_warning "   grub-btrfs monitoring unit was not found. Manual check/setup might be needed for automatic GRUB updates."
        log_warning "   Look for 'grub-btrfsd.path' and try 'sudo systemctl enable --now grub-btrfsd.path'"
    fi
fi

log_info "General review:"
log_info "- Scripts created (may be used manually if Timeshift is primary):"
log_info "  ${SNAPSHOT_CREATION_SCRIPT_PATH}, ${SNAPSHOT_MANAGEMENT_SCRIPT_PATH}"
log_info "- grub-btrfs config: ${GRUB_BTRFS_CONFIG_FILE}"
log_info "=============================================================================="

exit 0

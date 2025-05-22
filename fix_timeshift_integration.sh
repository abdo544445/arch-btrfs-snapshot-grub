#!/bin/bash

# ==============================================================================
# Timeshift Integration Fixer for Btrfs Snapshots
# ==============================================================================
#
# This script helps fix common issues with Timeshift and Btrfs integration:
# - Verifies Timeshift is properly installed
# - Fixes "Selected snapshot device is not a system disk" error
# - Ensures proper snapshot directory configuration
# - Sets up appropriate permissions for snapshot location
#
# ==============================================================================

# --- Configuration (Match these with your main script if needed) ---
SNAPSHOT_SUBVOLUME_PATH="/.snapshots"

# --- Helper Functions ---
log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1" >&2
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
log_info "Starting Timeshift integration fixer script..."

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
  log_error "This script must be run as root. Please use sudo."
  exit 1
fi

# Check for Btrfs root
if ! findmnt -n -o FSTYPE --target / | grep -q "btrfs"; then
    log_error "Root filesystem is not Btrfs. This script is for Btrfs systems only."
    exit 1
fi

# --- 1. Check Timeshift Installation ---
log_info "Checking Timeshift installation..."
if command -v timeshift &> /dev/null; then
    log_info "✓ Timeshift is installed."
else
    log_warning "✗ Timeshift not found. Installing..."
    if pacman -Sy --needed --noconfirm timeshift; then
        log_info "✓ Timeshift installed successfully."
    else
        log_error "✗ Failed to install Timeshift."
        log_info "Attempting to install timeshift-bin from AUR..."
        
        # Check for yay
        if command -v yay &> /dev/null; then
            log_info "Using yay to install timeshift-bin..."
            if yay -S --noconfirm timeshift-bin; then
                log_info "✓ Timeshift installed successfully via AUR."
            else
                log_error "✗ Failed to install Timeshift via AUR."
                exit 1
            fi
        else
            log_error "✗ Neither pacman nor yay could install Timeshift."
            log_error "Please install Timeshift manually before continuing."
            exit 1
        fi
    fi
fi

# --- 2. Identify System Disk and Root Subvolume ---
log_info "Identifying system disk and root subvolume..."

# Find the device containing root
ROOT_DEVICE=$(findmnt -n -o SOURCE --target / | awk '{print $1}')
ROOT_MOUNT_OPTS=$(findmnt -n -o OPTIONS --target /)
SUBVOL_NAME=$(echo "$ROOT_MOUNT_OPTS" | grep -oP 'subvol=\K[^,]+')

log_info "Root device: $ROOT_DEVICE"
log_info "Root mount options: $ROOT_MOUNT_OPTS"
log_info "Root subvolume name: ${SUBVOL_NAME:-"(not found)"}"

# Get the actual block device
BLOCK_DEVICE=$(lsblk -no pkname $(findmnt -n -o SOURCE --target / | sed 's/\[\(.*\)\]/\1/'))
if [ -z "$BLOCK_DEVICE" ]; then
    # Try with different approach if the first one failed
    BLOCK_DEVICE=$(df -h / | grep -v Filesystem | awk '{print $1}' | sed 's/[0-9]*$//')
fi

log_info "Block device: /dev/${BLOCK_DEVICE:-"(not found)"}"

if [ -z "$BLOCK_DEVICE" ]; then
    log_error "Failed to identify the block device for root filesystem."
    exit 1
fi

# --- 3. Check and Fix Snapshot Subvolume ---
log_info "Checking snapshot subvolume at ${SNAPSHOT_SUBVOLUME_PATH}..."
if btrfs subvolume show "${SNAPSHOT_SUBVOLUME_PATH}" >/dev/null 2>&1; then
    log_info "✓ ${SNAPSHOT_SUBVOLUME_PATH} already exists and is a subvolume."
else
    log_warning "✗ ${SNAPSHOT_SUBVOLUME_PATH} is not a valid Btrfs subvolume."
    
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
        log_info "✓ Subvolume ${SNAPSHOT_SUBVOLUME_PATH} created successfully."
    else
        log_error "✗ Failed to create subvolume ${SNAPSHOT_SUBVOLUME_PATH}."
        exit 1
    fi
fi

# --- 4. Create/Update Timeshift Configuration ---
log_info "Setting up Timeshift configuration for Btrfs snapshots..."

TIMESHIFT_CONFIG_DIR="/etc/timeshift"
TIMESHIFT_CONFIG_FILE="${TIMESHIFT_CONFIG_DIR}/timeshift.json"

if [ ! -d "$TIMESHIFT_CONFIG_DIR" ]; then
    mkdir -p "$TIMESHIFT_CONFIG_DIR"
    log_info "Created Timeshift config directory."
fi

# Backup existing config if present
if [ -f "$TIMESHIFT_CONFIG_FILE" ]; then
    cp "$TIMESHIFT_CONFIG_FILE" "${TIMESHIFT_CONFIG_FILE}.backup-$(date +%s)"
    log_info "Backed up existing Timeshift configuration."
fi

# Create a basic config file that forces Btrfs mode and specifies the snapshot location
cat << EOF > "$TIMESHIFT_CONFIG_FILE"
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "btrfs_use_qgroup" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "true",
  "schedule_boot" : "true",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [
    "+ /home/**",
    "+ /root/**",
    "- /var/run/**",
    "- /var/cache/**",
    "- /lost+found/**",
    "- /tmp/**",
    "- /boot/efi/EFI/arch"
  ],
  "exclude-apps" : [
  ]
}
EOF
log_info "✓ Created base Timeshift configuration."

# Set proper permissions
chmod 644 "$TIMESHIFT_CONFIG_FILE"

# --- 5. Check for grub-btrfs ---
log_info "Checking for grub-btrfs integration..."
if command -v grub-btrfs &> /dev/null; then
    log_info "✓ grub-btrfs is installed."
    
    # Check if the monitoring service is active
    GRUB_BTRFS_MONITOR_UNIT=""
    if systemctl list-unit-files | grep -Eoq '^\s*grub-btrfsd\.path\s'; then
        GRUB_BTRFS_MONITOR_UNIT="grub-btrfsd.path"
    elif systemctl list-unit-files | grep -Eoq '^\s*grub-btrfs\.path\s'; then
        GRUB_BTRFS_MONITOR_UNIT="grub-btrfs.path"
    fi
    
    if [ -n "$GRUB_BTRFS_MONITOR_UNIT" ]; then
        if systemctl is-active --quiet "$GRUB_BTRFS_MONITOR_UNIT"; then
            log_info "✓ ${GRUB_BTRFS_MONITOR_UNIT} is active."
        else
            log_warning "✗ ${GRUB_BTRFS_MONITOR_UNIT} is not active."
            log_info "Enabling and starting ${GRUB_BTRFS_MONITOR_UNIT}..."
            systemctl enable --now "$GRUB_BTRFS_MONITOR_UNIT"
            log_info "✓ Enabled ${GRUB_BTRFS_MONITOR_UNIT}."
        fi
    else
        log_warning "No grub-btrfs monitoring service found."
    fi
    
    # Update GRUB config
    log_info "Updating GRUB configuration to include snapshots..."
    if grub-mkconfig -o /boot/grub/grub.cfg; then
        log_info "✓ GRUB configuration updated successfully."
    else
        log_error "✗ Failed to update GRUB configuration."
    fi
else
    log_warning "✗ grub-btrfs is not installed."
    log_info "Please run the main setup script to install and configure grub-btrfs."
fi

# --- 6. Test Timeshift and Verify Configuration ---
log_info "Testing Timeshift configuration..."

# Try to create a test snapshot to verify it's working
if timeout 30 timeshift --create --comments "Test snapshot from fix script"; then
    log_info "✓ Successfully created a test snapshot with Timeshift!"
    
    # List snapshots to verify
    log_info "Listing available snapshots:"
    timeshift --list
    
    # Offer to delete the test snapshot
    if confirm_action "Would you like to delete the test snapshot?"; then
        timeshift --delete --snapshot "$(timeshift --list | grep "Test snapshot from fix script" | awk '{print $3}')"
        log_info "Test snapshot deleted."
    fi
else
    log_warning "✗ Could not automatically create a test snapshot."
    log_info "This may require manual configuration through the Timeshift GUI."
    log_info "Run 'sudo timeshift-launcher' and follow these steps:"
    log_info "1. Select 'BTRFS' as the snapshot type"
    log_info "2. Select the appropriate disk with your root subvolume"
    log_info "3. Verify that '${SNAPSHOT_SUBVOLUME_PATH}' is set as the snapshot location"
    log_info "4. Configure your desired snapshot schedule"
fi

# --- Completion ---
log_info "===================================================================="
log_info "Timeshift integration checker/fixer finished."
log_info "If you still have issues, you can manually configure Timeshift:"
log_info "1. Run 'sudo timeshift-launcher'"
log_info "2. If you see 'Selected snapshot device is not a system disk' error:"
log_info "   - Make sure to select the device containing your root filesystem"
log_info "   - Verify your Btrfs subvolume layout, especially if you use '@' subvolume format"
log_info "3. Configure '${SNAPSHOT_SUBVOLUME_PATH}' as your snapshot location"
log_info "===================================================================="

exit 0

# arch-btrfs-snapshot-grub: Arch Linux Btrfs Snapshot & GRUB Integration Setup Script

This script automates the setup of a Btrfs snapshot system on Arch Linux, integrating with GRUB for bootable snapshots. It also includes an option to use Timeshift as the primary snapshot manager.

**DISCLAIMER:** This script makes significant changes to your system. Understand what it does and use it at your own risk. Always back up your important data before running any system modification scripts.

## Features

* **Automated Prerequisite Installation:**
    * `btrfs-progs`
    * `git`
    * `base-devel` (for AUR builds)
    * `timeshift` (recommended GUI snapshot manager)
* **Btrfs Subvolume Setup:** Creates a dedicated `/.snapshots` subvolume if it doesn't exist.
* **Custom Boot Snapshotting (Optional):**
    * Creates a script (`/usr/local/bin/create-btrfs-boot-snapshot.sh`) to take a read-only snapshot of the root subvolume on every boot.
    * Sets up a systemd service (`btrfs-boot-snapshot.service`) to automate this.
* **Custom Snapshot Cleanup (Optional):**
    * Creates a script (`/usr/local/bin/manage-btrfs-snapshots.sh`) to keep the latest N boot snapshots and delete older ones.
    * Sets up a systemd service and timer (`btrfs-snapshot-cleanup.service`, `btrfs-snapshot-cleanup.timer`) for daily cleanup.
* **`grub-btrfs` Integration:**
    * Installs `grub-btrfs` from the Arch User Repository (AUR).
    * Configures `grub-btrfs` to look for snapshots in `/.snapshots`.
    * Enables the `grub-btrfsd.path` (or similar) unit to automatically update the GRUB menu when snapshots are created or deleted.
* **Timeshift Integration (Recommended):**
    * If Timeshift is successfully installed, the script will disable its custom automated snapshot creation and cleanup services, recommending Timeshift as the primary snapshot manager.
    * Guides the user on configuring Timeshift for Btrfs snapshots.
* **GRUB Configuration Update:** Regenerates `grub.cfg` to include snapshot boot entries.

## Prerequisites

1.  **Arch Linux:** A running Arch Linux system.
2.  **Btrfs Root Filesystem:** Your root filesystem (`/`) must be on a Btrfs partition. The script assumes a common layout where a subvolume named `@` (or similar) is mounted as `/`.
3.  **GRUB Bootloader:** You must be using GRUB.
4.  **Sudo Access:** The script must be run with `sudo` by a non-root user (this is required for building AUR packages correctly).
5.  **Internet Connection:** Required for downloading packages and cloning the AUR repository.
6.  **`base-devel` and `git`:** Required for building AUR packages. The script attempts to install these.

## How to Use

1.  **Download the Script:**
    Save the script (e.g., `setup_btrfs_snapshots.sh`) to your Arch Linux system.
    ```bash
    # Example (replace with your actual raw GitHub link once uploaded):
    # curl -O [https://raw.githubusercontent.com/abdo544445/arch-btrfs-snapshot-grub/main/setup_btrfs_snapshots.sh](https://raw.githubusercontent.com/abdo544445/arch-btrfs-snapshot-grub/main/setup_btrfs_snapshots.sh)
    # Or manually copy-paste into a file
    ```

2.  **Review the Script (CRITICAL):**
    Open the script in a text editor and **read it thoroughly**. Understand every command and what it does before proceeding.
    ```bash
    nano setup_btrfs_snapshots.sh
    ```
    Adjust any configuration variables at the top of the script if needed (e.g., `SNAPSHOT_SUBVOLUME_PATH`, `KEEP_LATEST_N_SNAPSHOTS`).

3.  **Make it Executable:**
    ```bash
    chmod +x setup_btrfs_snapshots.sh
    ```

4.  **Run the Script with Sudo:**
    Execute the script with `sudo`. Ensure you are running this from a non-root user account that has sudo privileges.
    ```bash
    sudo ./setup_btrfs_snapshots.sh
    ```
    The script will perform pre-flight checks and ask for confirmation before making any changes.

5.  **Follow Prompts and Output:**
    Pay close attention to any messages, warnings, or errors printed by the script.

## Post-Installation Steps

The script will provide guidance at the end of its execution. Key steps usually include:

* **If Timeshift was installed (Recommended Path):**
    1.  Launch Timeshift (e.g., `sudo timeshift-launcher`).
    2.  Follow the Setup Wizard:
        * Select "BTRFS" as the Snapshot Type.
        * Choose your Btrfs system partition.
        * Ensure the Snapshot Location is set to `/.snapshots` (or your configured path).
        * Configure snapshot levels (Boot, Hourly, Daily, etc.) and retention settings within Timeshift.
    3.  Timeshift will now manage your automated snapshots.
    4.  The `grub-btrfs` integration should automatically add Timeshift's Btrfs snapshots to your GRUB menu. Verify that the `grub-btrfsd.path` (or similar unit found by the script) is active (`sudo systemctl status grub-btrfsd.path`).

* **If Timeshift was NOT installed (Fallback to Custom Scripts):**
    1.  **Reboot your system:** This is necessary for the custom `btrfs-boot-snapshot.service` to create its first snapshot.
    2.  **Check GRUB Menu:** After rebooting, check your GRUB menu for a submenu listing Btrfs snapshots.
    3.  **Verify Snapshots:** Confirm that snapshots are being created in `/.snapshots` (or your configured path).
        ```bash
        sudo ls -la /.snapshots
        sudo btrfs subvolume list /.snapshots
        ```
    4.  **Monitor Cleanup:** Check the status of the custom cleanup timer and service:
        ```bash
        sudo systemctl list-timers --all
        journalctl -u btrfs-snapshot-cleanup.service
        ```
    5.  Ensure the `grub-btrfsd.path` (or similar unit found by the script) is active for automatic GRUB updates.

## Components Created

* **Snapshot Subvolume:** `/.snapshots` (by default)
* **Scripts (in `/usr/local/bin/`):**
    * `create-btrfs-boot-snapshot.sh`
    * `manage-btrfs-snapshots.sh`
* **Systemd Units (in `/etc/systemd/system/`):**
    * `btrfs-boot-snapshot.service`
    * `btrfs-snapshot-cleanup.service`
    * `btrfs-snapshot-cleanup.timer`
* **`grub-btrfs` Configuration:** `/etc/default/grub-btrfs/config`

## Important Considerations

* **Disk Space:** Btrfs snapshots are space-efficient initially due to copy-on-write. However, as files change, snapshots will consume more space. Regularly monitor your disk usage (`df -h`, `sudo btrfs filesystem du /`).
* **AUR Packages:** `grub-btrfs` is installed from the AUR. AUR packages are user-maintained; ensure you understand the implications.
* **Customization:** The scripts and configurations can be customized further to suit specific needs.
* **Rollback Procedure:** Booting into a snapshot from GRUB is typically read-only. To permanently roll back, you would usually:
    1.  Boot into the desired read-only snapshot.
    2.  Create a new read-write snapshot from it.
    3.  Rename your current active root subvolume (e.g., `@` to `@old`).
    4.  Rename the new read-write snapshot to become the active root subvolume (e.g., to `@`).
    5.  Adjust `/etc/fstab` if necessary (if using `subvolid` instead of `subvol=/@`).
    6.  Update the default Btrfs subvolume if needed (`sudo btrfs subvolume set-default ...`).
    *Timeshift provides a GUI to simplify this rollback process.*
* **This script is a starting point.** Advanced users may want to integrate more sophisticated tools like Snapper or further customize the existing scripts.

## Troubleshooting

* **`makepkg as root is not allowed`:** Ensure you are running the main script with `sudo` from a regular user account, not directly from a root shell. The script attempts to use `sudo -u "${SUDO_USER}"` for `makepkg`.
* **`grub-btrfsd` service/path not found/enabled:** The script tries to detect the correct unit name (`grub-btrfsd.path` is preferred). If it fails, you may need to manually find the unit provided by the `grub-btrfs` package and enable/start it (e.g., `sudo systemctl enable --now grub-btrfsd.path`).
* **No snapshots in GRUB:**
    * Ensure snapshots exist in the configured `GRUB_BTRFS_SNAPSHOT_DIR` (default `/.snapshots`).
    * Ensure `grub-btrfsd.path` (or service) is running and has triggered a GRUB update.
    * Manually run `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
* **SSL Certificate Problems during `pacman` operations:** This usually indicates an issue with your system's `ca-certificates` or system time. Try:
    ```bash
    sudo pacman -Syyu ca-certificates
    # Check and correct system time if needed
    # Consider updating your mirrorlist
    ```

## Contributing

Feel free to fork this script, report issues, or suggest improvements.
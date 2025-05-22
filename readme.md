# arch-btrfs-snapshot-grub

A practical, comprehensive solution for integrating Btrfs snapshots with GRUB on Arch Linux. This project automates snapshot creation, cleanup, and GRUB menu integration, providing an easy system recovery solution with optional Timeshift support.

[![GitHub Stars](https://img.shields.io/github/stars/abdo544445/arch-btrfs-snapshot-grub?style=for-the-badge)](https://github.com/abdo544445/arch-btrfs-snapshot-grub/stargazers)
[![GitHub License](https://img.shields.io/github/license/abdo544445/arch-btrfs-snapshot-grub?style=for-the-badge)](https://github.com/abdo544445/arch-btrfs-snapshot-grub/blob/main/LICENSE)

---

## 🚀 What This Project Does

- **Sets up a dedicated Btrfs snapshot subvolume** (`/.snapshots`)
- **Automates snapshot creation on every boot** (via systemd)
- **Cleans up old snapshots automatically** (keeps the latest N)
- **Integrates with GRUB** so you can boot into snapshots from the GRUB menu
- **Optionally uses Timeshift** as the snapshot manager if installed

---

## 📋 Requirements

- **Arch Linux** with Btrfs as your root filesystem
- **GRUB** as your bootloader
- **Sudo access** (run the script as a regular user with `sudo`)
- **Internet connection** (for installing packages and AUR helpers)

---

## ⚡ Quick Start (One-Command Install)
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/abdo544445/arch-btrfs-snapshot-grub/main/setup_btrfs_snapshots.sh)"
```

Just run this command to install everything automatically:

Or if you prefer to review the script first (recommended):

1. **Download the script:**
    ```bash
    curl -fsSL https://raw.githubusercontent.com/abdo544445/arch-btrfs-snapshot-grub/main/setup_btrfs_snapshots.sh -o setup_btrfs_snapshots.sh
    ```

2. **Review the script:**
    ```bash
    nano setup_btrfs_snapshots.sh
    ```
    *(Always read scripts before running them! Adjust config variables at the top if needed.)*

3. **Make it executable and run it:**
    ```bash
    chmod +x setup_btrfs_snapshots.sh
    sudo ./setup_btrfs_snapshots.sh
    ```

4. **Follow the prompts.** The script will guide you through the rest.

---

## 📦 What Gets Installed/Created

- `/.snapshots` subvolume for storing snapshots
- `/usr/local/bin/create-btrfs-boot-snapshot.sh` (boot snapshot script)
- `/usr/local/bin/manage-btrfs-snapshots.sh` (cleanup script)
- Systemd units:
    - `btrfs-boot-snapshot.service`
    - `btrfs-snapshot-cleanup.service`
    - `btrfs-snapshot-cleanup.timer`
- `grub-btrfs` (from AUR) and its config in `/etc/default/grub-btrfs/config`

---

## ✅ After Running the Script

- **If Timeshift is installed:**  
  Use Timeshift for snapshot management. Launch it with `sudo timeshift-launcher` and follow the wizard.
- **If Timeshift is not installed:**  
  The custom scripts/services will handle snapshot creation and cleanup.  
  - Reboot to create your first snapshot.
  - Check `/.snapshots` for new snapshots.
  - GRUB should show a submenu for booting into snapshots.

---

## 🔧 Troubleshooting

- **Not seeing snapshots in GRUB?**
    - Make sure `grub-btrfsd.path` (or similar) is enabled:  
      `sudo systemctl status grub-btrfsd.path`
    - Manually update GRUB:  
      `sudo grub-mkconfig -o /boot/grub/grub.cfg`
- **AUR build errors?**  
  Make sure you're running the script as a regular user with `sudo`, not as root.
- **Disk space:**  
  Snapshots are efficient, but monitor your free space with `df -h` and `sudo btrfs filesystem du /`.

---

## 🔄 Rollback (Manual)

1. Boot into a snapshot from GRUB (read-only).
2. Create a new read-write snapshot from it.
3. Rename your current root subvolume (e.g., `@` to `@old`).
4. Rename the new snapshot to `@`.
5. Update `/etc/fstab` if needed.
6. Set the new default subvolume:  
   `sudo btrfs subvolume set-default <subvolid> /`

---

## 🤝 Contributing

Pull requests and issues are welcome!

---

**Always back up your data before using system scripts.**  
This project is provided as-is, with no warranty.
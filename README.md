# xiTools

xiTools is a set of utilities for operating system optimization and automated deployment of xiRAID Classic.

## Getting started

1. Run `prepare_system.sh` on the target host (use the `-e` option for expert mode). Use `-u` to update the repository without launching any menus. The script now automatically detects Ubuntu or RedHat-based distributions and installs required packages (`yq` version 4, `whiptail`/`newt`, `ansible`, etc.) using the appropriate package manager before cloning the repository.
   The script immediately launches a simplified start menu in default mode to choose a preset. Use `-e` to access the full interactive menu with additional options such as updating the repository or saving the current configuration as a new preset.
   Both menus now include a **Collect HW Keys** option for gathering system information into a tar archive and uploading it via `transfer.sh`. The upload server is configured automatically and listens on port 8080. You can override it by setting the `TRANSFER_SERVER` environment variable if needed.

   Example:
   ```bash
   export TRANSFER_SERVER="http://178.253.23.152:8080"
   ./collect_hw_keys.sh
   ```
2. Execute `startup_menu.sh` separately if you need the complete configuration menu outside of the expert mode. Any presets you create in expert mode will also be available here and in the simplified menu. It also allows setting a custom hostname.
3. To apply the configuration, choose **Install xiRAID Classic** from the menu.
   This now uses `playbooks/xiraid_only.yml` to install xiRAID Classic without applying
   additional roles. An **Exit** option is available if you want to leave without running the playbook.
   On RHEL systems follow the [installation guide](https://xinnor.io/docs/xiRAID-4.3.0/E/en/IG/installing_xiraid_classic_on_rhel.html).
   Before running the playbook make sure any previous xiRAID packages are removed.
   On RHEL, RHEL-based or Oracle Linux systems run:
   ```bash
   sudo dnf remove xiraid-core && sudo dnf autoremove
   sudo dnf remove xiraid-repo
   ```
   On Ubuntu or Proxmox use:
   ```bash
   sudo apt remove xiraid-appimage xiraid-core xiraid-kmod
   sudo apt remove xiraid-repo
   sudo apt autoremove
   ```
4. To configure an NFS client on another system, run `sudo ./client_setup.sh`. Root
   privileges are required to install packages, create the mount point and mount
   the exported share. If you only need the client pieces, copy the contents of
   the `client_repo` directory into a separate repository and run the script
   from there. If you choose to install DOCA OFED using the provided playbook,
   the script will automatically install Ansible packages when needed.

The `prepare_system.sh` script installs dependencies required by the interactive helper scripts. It works on both Ubuntu and RedHat-like systems by selecting `apt`, `dnf`, or `yum` as needed. The helper scripts rely on the [`mikefarah/yq`](https://github.com/mikefarah/yq) binary (v4+). If you encounter errors such as `jq: error: env/1 is not defined`, make sure this version of `yq` is installed by re-running `prepare_system.sh` or installing it manually.
Earlier versions of the RAID configuration script failed with `'//' expects 2 args but there is 1` when no spare pool existed. The script now creates the pool automatically the first time you enter devices.
You can inspect all `yq` binaries with `which -a yq`. If multiple paths are listed, reorder your `PATH` so `/usr/local/bin/yq` precedes others or remove the older version entirely.

The `configure_hostname.sh` script updates `/etc/hosts` so that the system's hostname shares the `127.0.0.1` entry with `localhost`.

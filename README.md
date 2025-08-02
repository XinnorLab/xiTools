# xiTools

xiTools is a set of utilities for operating system optimization and automated deployment of xiRAID Classic.

## Getting started

1. Run `start.sh` on the target host (use the `-e` option for expert mode). Use `-u` to update the repository without launching any menus. The script now automatically detects Ubuntu or RedHat-based distributions and installs required packages (`yq` version 4, `whiptail`/`newt`, `ansible`, etc.) using the appropriate package manager before cloning the repository.
   The script immediately launches a simplified start menu in default mode to choose a preset. Use `-e` to access the full interactive menu with additional options such as updating the repository or saving the current configuration as a new preset. When creating a RAID preset the menu now displays a list of optional `xicli raid create` parameters and lets you enter any desired options.
   Both menus now include a **Collect HW Keys** option that displays hardware
   keys gathered from all systems listed in the Ansible inventory using
   `xicli license show`. Each key is shown in the format
   `hostname : hwkey` inside a text dialog.

   Example:
   ```bash
   ./collect_hw_keys.sh [-i path/to/inventory]
   ```
2. Execute `startup_menu.sh` separately if you need the complete configuration menu outside of the expert mode. Any presets you create in expert mode will also be available here and in the simplified menu. It also allows setting a custom hostname.
3. To apply the configuration, choose **Install xiRAID Classic** from the menu.
   This now uses `playbooks/xiraid_only.yml` to install xiRAID Classic without applying
   additional roles. An **Exit** option is available if you want to leave without running the playbook.
   On RHEL systems follow the [installation guide](https://xinnor.io/docs/xiRAID-4.3.0/E/en/IG/installing_xiraid_classic_on_rhel.html).
   Before running the playbook make sure any previous xiRAID packages are removed using
   [`playbooks/system_cleanup.yml`](playbooks/system_cleanup.yml) or the **System Cleanup** menu option.

4. Choose **System Cleanup** to remove xiRAID and tuning packages from all hosts. This runs `playbooks/system_cleanup.yml` and keeps your inventory intact.

5. To configure an NFS client on another system, run `sudo ./client_setup.sh`. Root
   privileges are required to install packages, create the mount point and mount
   the exported share. If you only need the client pieces, copy the contents of
   the `client_repo` directory into a separate repository and run the script
   from there. If you choose to install DOCA OFED using the provided playbook,
   the script will automatically install Ansible packages when needed.

The `start.sh` script installs dependencies required by the interactive helper scripts. It works on both Ubuntu and RedHat-like systems by selecting `apt`, `dnf`, or `yum` as needed. The helper scripts rely on the [`mikefarah/yq`](https://github.com/mikefarah/yq) binary (v4+). If you encounter an error like `Error: env/1 is not defined` from `yq`, make sure this version of `yq` is installed by re-running `start.sh` or installing it manually.
The playbooks also use Ansible's `json_query` filter, which depends on the
`jmespath` Python library. Recent updates to `start.sh` and
`client_repo/client_setup.sh` automatically install the `python3-jmespath`
package on systems using `apt`, `dnf`, or `yum`. If you see an error like
`You need to install "jmespath" prior to running json_query filter`, rerun the
setup scripts or install the package manually.
Earlier versions of the RAID configuration script failed with `'//' expects 2 args but there is 1` when no spare pool existed. The script now creates the pool automatically the first time you enter devices.
You can inspect all `yq` binaries with `which -a yq`. If multiple paths are listed, reorder your `PATH` so `/usr/local/bin/yq` precedes others or remove the older version entirely.

The `configure_hostname.sh` script updates `/etc/hosts` so that the system's hostname shares the `127.0.0.1` entry with `localhost`.

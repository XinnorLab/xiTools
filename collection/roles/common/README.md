# Role: common

Baseline configuration for all storage nodes. Installs essential packages, configures timezone, NTP, basic kernel tuning and security updates. The role supports both Debian/Ubuntu (apt) and RHEL-based systems (dnf).

## Variables
* **`common_timezone`** – system timezone (default `Europe/Amsterdam`).
* **`common_packages`** – list of baseline packages to install. Includes either `unattended-upgrades` or `dnf-automatic` depending on the OS family.
* **`common_sysctl`** – dictionary of sysctl parameters.
* **`chrony_service_name`** – name of the chrony service to manage (defaults to `chrony` on Debian and `chronyd` on RHEL).
* **`chrony_package_name`** – name of the chrony package to install (default `chrony`).
* **`xinas_hostname`** – hostname to set. Defaults to `xiNAS-HWKEY`.

## Example
```yaml
- hosts: storage_nodes
  roles:
    - role: common
```

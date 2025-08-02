# Role **doca_ofed**
Installs NVIDIA DOCA-OFED from the official DOCA repository on Debian/Ubuntu and RHEL systems.

Variables:
  * `doca_version` – release version string (`DGX_latest_DOCA` for latest).
  * `doca_distro_series` – distribution series used in repository path (e.g. `ubuntu24.04`, `rhel9.3`).
  * `doca_repo_base` – base URL of the DOCA repository.
  * `doca_repo_component` – component path built from version and distro.
  * `doca_pkgs` – list of packages to install (kernel stack and userspace).
  * `doca_ofed_auto_reboot` – reboot automatically if modules built.

### References
* NVIDIA Docs – Installing Mellanox OFED on Ubuntu (DKMS)
* DOCA-OFED installation guide (ConnectX-7)
* DKMS packaging notes for mlnx-ofed-kernel on Ubuntu

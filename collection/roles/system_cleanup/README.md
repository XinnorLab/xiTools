# Role: system_cleanup

Removes xiRAID packages, performance tuning utilities and matching kernel headers from storage nodes.

## Features
* Purges `xiraid*` packages and repository files.
* Uninstalls optional performance tuning packages.
* Removes kernel headers for the running kernel.

## Example
```yaml
- hosts: storage_nodes
  roles:
    - system_cleanup
```

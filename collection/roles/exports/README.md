# Role **exports**
Manages NFS export definitions in `/etc/exports` using a Jinja template so that
access rules are easy to override. To designate an export as the NFSv4 root,
include `fsid=0` in the options field.

## Variables
* `exports` – list of dictionaries `{ path, clients, options }`.

## Example
```yaml
exports:
  - path: /mnt/data
    clients: 192.168.0.0/24
    options: rw,sync,sec=sys,no_root_squash
```

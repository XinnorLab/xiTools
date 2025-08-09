#!/usr/bin/env python3
"""Interactive inventory manager for xiTools.

This utility replaces the shell-based system list editor. It supports
adding hosts by single address, IP ranges, patterns like ``node[01:32]``
and CIDR notation. Hosts can be assigned to groups and enabled or
disabled. The inventory is stored in ``inventories/lab.ini`` in
Ansible's INI format.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from ipaddress import ip_address, ip_network
import re
from pathlib import Path
from typing import Dict, List, Set


@dataclass
class Host:
    """A managed system."""

    name: str
    address: str
    groups: Set[str] = field(default_factory=set)
    enabled: bool = True
    extras: str = ""  # additional inventory fields


@dataclass
class Group:
    name: str
    enabled: bool = True


class Inventory:
    """Simple representation of an Ansible inventory file."""

    def __init__(self, path: Path):
        self.path = path
        self.hosts: Dict[str, Host] = {}
        self.groups: Dict[str, Group] = {}

    def load(self) -> None:
        current_group: str | None = None
        if not self.path.exists():
            return
        for line in self.path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                current_group = line[1:-1]
                self.groups.setdefault(current_group, Group(current_group))
                continue
            if current_group is None:
                continue
            parts = line.split()
            address = parts[0]
            extras = " ".join(parts[1:]) if len(parts) > 1 else ""
            name = address
            host = self.hosts.get(address)
            if host:
                host.groups.add(current_group)
            else:
                self.hosts[address] = Host(name=name, address=address, groups={current_group}, extras=extras)

    def save(self) -> None:
        lines: List[str] = []
        for group_name in sorted(self.groups):
            lines.append(f"[{group_name}]")
            for host in sorted(self.hosts.values(), key=lambda h: h.address):
                if group_name in host.groups and host.enabled:
                    line = host.address
                    if host.extras:
                        line += f" {host.extras}"
                    lines.append(line)
            lines.append("")
        self.path.write_text("\n".join(lines))


def expand_pattern(pattern: str) -> List[str]:
    """Expand host patterns to a list of addresses or names."""

    pattern = pattern.strip()

    # CIDR notation
    try:
        network = ip_network(pattern, strict=False)
        return [str(ip) for ip in network.hosts()]
    except ValueError:
        pass

    # IPv4 range: start-end
    range_match = re.match(r"^([0-9]{1,3}(?:\.[0-9]{1,3}){3})-([0-9]{1,3}(?:\.[0-9]{1,3}){3})$", pattern)
    if range_match:
        start = ip_address(range_match.group(1))
        end = ip_address(range_match.group(2))
        if int(start) > int(end):
            start, end = end, start
        hosts = []
        cur = start
        while int(cur) <= int(end):
            hosts.append(str(cur))
            cur = ip_address(int(cur) + 1)
        return hosts

    # Name pattern: prefix[01:10]suffix
    name_match = re.match(r"^(\w+?)\[(\d+):(\d+)\](.*)$", pattern)
    if name_match:
        prefix, start_s, end_s, suffix = name_match.groups()
        start_i = int(start_s)
        end_i = int(end_s)
        step = 1 if start_i <= end_i else -1
        width = len(start_s)
        return [f"{prefix}{i:0{width}d}{suffix}" for i in range(start_i, end_i + step, step)]

    # Single host/IP
    return [pattern]


def validate_host(addr: str) -> bool:
    """Basic validation for an address or hostname."""

    try:
        ip_address(addr)
        return True
    except ValueError:
        fqdn_re = re.compile(r"^[A-Za-z0-9.-]+$")
        return bool(fqdn_re.match(addr))


def prompt(msg: str) -> str:
    try:
        return input(msg)
    except EOFError:
        return ""


def interactive() -> None:
    inv_path = Path("inventories/lab.ini")
    inv = Inventory(inv_path)
    inv.load()
    modified = False

    while True:
        print("\nInventory manager")
        print("-----------------")
        print("1) Add hosts")
        print("2) Remove host")
        print("3) Toggle host enabled/disabled")
        print("4) Show hosts")
        print("5) Save and exit")
        print("6) Exit without saving")
        choice = prompt("Select option: ").strip()

        if choice == "1":
            pattern = prompt("Enter host/IP/range/pattern: ")
            if not pattern:
                continue
            try:
                expansion = expand_pattern(pattern)
            except Exception as exc:  # pragma: no cover - defensive
                print(f"Invalid pattern: {exc}")
                continue
            print("Hosts to add:")
            for h in expansion:
                print("  ", h)
            if prompt("Add these hosts? [y/N]: ").lower() != "y":
                continue
            group = prompt("Group name [storage_nodes]: ").strip() or "storage_nodes"
            inv.groups.setdefault(group, Group(group))
            for addr in expansion:
                if not validate_host(addr):
                    print(f"Skipping invalid address {addr}")
                    continue
                if addr in inv.hosts:
                    inv.hosts[addr].groups.add(group)
                else:
                    name = addr.split(".")[0]
                    inv.hosts[addr] = Host(name=name, address=addr, groups={group})
            modified = True

        elif choice == "2":
            if not inv.hosts:
                print("No hosts to remove")
                continue
            hosts = list(inv.hosts.values())
            for idx, host in enumerate(hosts, 1):
                groups = ",".join(host.groups)
                status = "enabled" if host.enabled else "disabled"
                print(f"{idx}) {host.address} [{groups}] ({status})")
            sel = prompt("Select number to remove (comma separated): ")
            if not sel:
                continue
            try:
                nums = [int(s) for s in sel.replace(",", " ").split()]
            except ValueError:
                print("Invalid selection")
                continue
            for i in sorted(nums, reverse=True):
                if 1 <= i <= len(hosts):
                    del inv.hosts[hosts[i - 1].address]
                    modified = True

        elif choice == "3":
            if not inv.hosts:
                print("No hosts available")
                continue
            hosts = list(inv.hosts.values())
            for idx, host in enumerate(hosts, 1):
                status = "enabled" if host.enabled else "disabled"
                print(f"{idx}) {host.address} ({status})")
            sel = prompt("Select number to toggle: ")
            if not sel:
                continue
            try:
                idx = int(sel)
            except ValueError:
                print("Invalid selection")
                continue
            if 1 <= idx <= len(hosts):
                host = hosts[idx - 1]
                host.enabled = not host.enabled
                modified = True

        elif choice == "4":
            if not inv.hosts:
                print("Inventory empty")
                continue
            for host in sorted(inv.hosts.values(), key=lambda h: h.address):
                groups = ",".join(sorted(host.groups))
                status = "enabled" if host.enabled else "disabled"
                print(f"{host.address} [{groups}] ({status})")

        elif choice == "5":
            inv.save()
            print(f"Saved to {inv_path}")
            return

        elif choice == "6":
            if modified and prompt("Discard changes? [y/N]: ").lower() != "y":
                continue
            return


def main() -> None:  # pragma: no cover - entry point
    interactive()


if __name__ == "__main__":
    main()

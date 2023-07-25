Deploy `hetzner-ext` with:

```bash
nix run github:numtide/nixos-anywhere -- root@2a01:4f8:10a:eae::2 -i /home/connorbaker/.ssh/id_ed25519 --flake .#hetzner-ext
```

TODO:

- `hetzner-ext`
  - [ ] Switch to ZFS and ZFS-encrypted disks
  - [ ] Jellyfin
    - Expose only over WireGuard?
  - [ ] Make custom NixOS-iso available via torrent?
    - Exponse only over WireGuard?

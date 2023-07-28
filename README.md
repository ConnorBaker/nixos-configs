TODO:

- Switch to nix provided by github:nixos/nix
- Deploy SSH keys to machines
- Migrate to use of flake modules
-

## `nixos-desktop`

- [ ] Move to disko
- [ ] Instructions for using `sops`

Generate the secrete age key using `ssh-to-age`:

```bash
mkdir -p ~/.config/sops/age
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

Edit the files in secrets with `sops secrets/<whatever>.yaml`.

## `hetzner-ext`

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

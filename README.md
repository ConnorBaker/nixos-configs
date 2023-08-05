TODO:

- [x] `nixos-ext` fails to boot.
  - This is due to `nixos-anywhere` not recursively unmounting nested datasets.
  - At the moment, no way to get around `boot.zfs.forceImportRoot = true;`.
- [ ] Deploy SSH keys to machines
- [ ] Migrate to use of flake modules
- [ ] <https://github.com/Mic92/sops-nix/issues/340>
- [ ] <https://samleathers.com/posts/2022-02-03-my-new-network-and-deploy-rs.html>
- [ ] <https://samleathers.com/posts/2022-02-11-my-new-network-and-sops.html>
- [ ] <https://github.com/numtide/nixos-anywhere/pull/34>
- [ ] <https://github.com/numtide/nixos-anywhere/issues/63>
- [ ] <https://github.com/numtide/nixos-anywhere/issues/141>
- [ ] <https://github.com/numtide/nixos-anywhere/issues/161>

## `nixos-desktop`

- [ ] Move to disko
- [ ] Instructions for using `sops`

Generate the secret age key using `ssh-to-age`:

```bash
mkdir -p ~/.config/sops/age
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

Edit the files in secrets with `sops secrets/<whatever>.yaml`.

## `hetzner-ext`

Deploy `hetzner-ext` with:

```bash
ssh hetzner "bash -s" < scripts/hetzner-ipv6-only-dns-fix.sh
nix run github:numtide/nixos-anywhere -- \
  root@2a01:4f9:6a:1692::2 \
  -i /home/connorbaker/.ssh/id_ed25519 \
  --flake .#hetzner-ext
```

TODO:

- `hetzner-ext`
  - [ ] Switch to ZFS and ZFS-encrypted disks
  - [ ] Jellyfin
    - Expose only over WireGuard?
  - [ ] Make custom NixOS-iso available via torrent?
    - Expose only over WireGuard?

## `nixos-ext`

Deploy `nixos-ext` with:

```bash
nix run github:numtide/nixos-anywhere -- \
  root@192.168.1.195  \
  -i /home/connorbaker/.ssh/id_ed25519  \
  --build-on-remote \
  --flake .#nixos-ext
```

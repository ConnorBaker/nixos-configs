TODO:

- `nixos-ext` install ended with

    ```bash
    File system "/boot" is not a FAT EFI System Partition (ESP) file system.
    Traceback (most recent call last):
      File "/nix/store/72h237wzm4rkrxdn8iyz4jx0kj57lprb-systemd-boot", line 341, in <module>
        main()
      File "/nix/store/72h237wzm4rkrxdn8iyz4jx0kj57lprb-systemd-boot", line 258, in main
        subprocess.check_call(["/nix/store/rpagyb9792jx4f2hlqz9q0ld3frlzxq5-systemd-253.6/bin/bootctl", "--esp-path=/boot"] + bootctl_flags + ["install"])
      File "/nix/store/a5k7x5mn7i7rcji4n99mwiqhmgjdzxmk-python3-3.10.12/lib/python3.10/subprocess.py", line 369, in check_call
        raise CalledProcessError(retcode, cmd)
    subprocess.CalledProcessError: Command '['/nix/store/rpagyb9792jx4f2hlqz9q0ld3frlzxq5-systemd-253.6/bin/bootctl', '--esp-path=/boot', '--no-variables', 'install']' returned non-zero exit status 1.
    installation finished!
    cannot unmount '/mnt/boot': pool or dataset is busy
    cannot unmount '/mnt/rpool': no such pool or dataset
    ```

- Deploy SSH keys to machines
- Migrate to use of flake modules
- <https://github.com/Mic92/sops-nix/issues/340>
- <https://samleathers.com/posts/2022-02-03-my-new-network-and-deploy-rs.html>
- <https://samleathers.com/posts/2022-02-11-my-new-network-and-sops.html>
- <https://github.com/numtide/nixos-anywhere/pull/34>
- <https://github.com/numtide/nixos-anywhere/issues/63>
- <https://github.com/numtide/nixos-anywhere/issues/141>
- <https://github.com/numtide/nixos-anywhere/issues/161>

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

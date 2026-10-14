# nixos-configs

Configuration for my NixOS machines.

## To-do

- [ ] Include `nixos-anywhere` in flake to version control it.

- [ ] <https://github.com/Mic92/sops-nix/issues/340>

Common builder policy lives in `profiles/builder.nix`. Host identity and builder metadata live in `inventory.nix`; disk identities stay in each host's `disko.nix`, with the shared ZFS layout in `util.nix`.

> [!WARNING]
>
> When using the `--build-on-remote` flag with `nixos-anywhere`, make sure the remote account is one which Nix trusts. In the NixOS installer, this means `root` instead of `nixos`.

> [!NOTE]
>
> When using impermanence rooted at `/persist`, it's important that the directory provided to `--extra-files` is has a root of `/persist`. For example, instead of using `--extra-files ./secret_deployment_files/etc/ssh`, `--extra-files ./secret_deployment_files/persist/etc/ssh`.

> [!NOTE]
>
> These hosts decrypt secrets with age using `/persist/etc/ssh/ssh_host_ed25519_key`. GPG SSH-key import is disabled; deployment requires the persistent ED25519 private key.

> [!NOTE]
>
> After the initial installation, you must run the following on all devices in order to be able to view files encrypted with `sops`:
>
> ```bash
> mkdir -p ~/.config/sops/age
> sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key >> ~/.config/sops/age/keys.txt
> ```

> [!NOTE]
>
> When creating files with `sops` which can be read by multiple keys, the device creating the file must have access to all the keys. This is because the device creating the file will encrypt the file with all the keys, and the device reading the file will decrypt the file with the correct key.

## x86 hosts

Use the matching deployment values:

| Host | Target | Extra files |
| --- | --- | --- |
| `nixos-desktop` | `connorbaker@192.168.1.12` | `/Volumes/nixos-desktop` |
| `nixos-build01` | `connorbaker@192.168.1.14` | `/Volumes/nixos-build01` |
| `nixos-ext` | `connorbaker@192.168.1.13` | `/Volumes/nixos-ext` |

For example, deploy `nixos-desktop` with:

```bash
host=nixos-desktop
target=connorbaker@192.168.1.12
extra_files=/Volumes/nixos-desktop

nix run "github:nix-community/nixos-anywhere/242444d228636b1f0e89d3681f04a75254c29f66" --builders '' -- \
  "$target" \
  -i ~/.ssh/id_ed25519 \
  --kexec https://gh-v6.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz \
  --flake ".#$host" \
  --build-on-remote \
  --print-build-logs \
  --debug \
  --extra-files "$extra_files"
```

## `nixos-orin`

TODO:

- [ ] The normal `aarch64-linux` tarball `kexec` image doesn't work, presumably because the Jetson is ✨special✨.
  - In progress: creating a custom `kexec` image using the Jetpack kernel.

Deploy `nixos-orin` with:

```bash
nix run github:numtide/nixos-anywhere -- \
  root@192.168.0.95 \
  -i ~/.ssh/id_ed25519 \
  --kexec /Users/connorbaker/Packages/nixos-configs/kexec-installer-aarch64-linux.tar.gz \
  --flake .#nixos-orin \
  --build-on-remote \
  --print-build-logs \
  --debug \
  --extra-files /Volumes/nixos-orin
```

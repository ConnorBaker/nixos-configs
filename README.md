# nixos-configs

Configuration for my NixOS machines.

TODO:

- [ ] Include `nixos-anywhere` in flake to version control it.
- [ ] Deploy SSH keys to machines
- [ ] Migrate to use of flake modules
- [ ] <https://github.com/Mic92/sops-nix/issues/340>
- [ ] <https://samleathers.com/posts/2022-02-03-my-new-network-and-deploy-rs.html>
- [ ] <https://samleathers.com/posts/2022-02-11-my-new-network-and-sops.html>
- [ ] <https://github.com/numtide/nixos-anywhere/pull/34>
- [ ] <https://github.com/numtide/nixos-anywhere/issues/63>
- [ ] <https://github.com/numtide/nixos-anywhere/issues/141>
- [ ] <https://github.com/numtide/nixos-anywhere/issues/161>

> **WARNING**
>
> When using the `--build-on-remote` flag with `nixos-anywhere`, make sure the remote account is one which Nix trusts. In the NixOS installer, this means `root` instead of `nixos`.

> **INFO**
>
> When using impermanence rooted at `/persist`, it's important that the directory provided to `--extra-files` is has a root of `/persist`. For example, instead of using `--extra-files ./secret_deployment_files/etc/ssh`, `--extra-files ./secret_deployment_files/persist/etc/ssh`.

## `nixos-desktop`

- [ ] Move to disko
- [ ] Instructions for using `sops`

Generate the secret age key using `ssh-to-age`:

```bash
mkdir -p ~/.config/sops/age
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

Edit the files in secrets with `sops secrets/<whatever>.yaml`.

## `nixos-ext`

Deploy `nixos-ext` with:

```bash
nix run github:numtide/nixos-anywhere/9df79870b04667f2d16f1a78a1ab87d124403fb7 -- \
  connorbaker@192.168.1.195 \
  -i ~/.ssh/id_ed25519 \
  --flake .#nixos-ext \
  --build-on-remote \
  --extra-files /Volumes/nixos-ext
```

## `nixos-build01`

Deploy `nixos-build01` with:

```bash
nix run github:numtide/nixos-anywhere/9df79870b04667f2d16f1a78a1ab87d124403fb7 -- \
  connorbaker@192.168.1.200 \
  -i ~/.ssh/id_ed25519 \
  --flake .#nixos-build01 \
  --build-on-remote \
  --extra-files /Volumes/nixos-build01
```

# nixos-configs

Configuration for my NixOS machines.

## To-do

- \[ \] Include `nixos-anywhere` in flake to version control it.

- \[ \] Migrate to use of flake modules

- \[ \] <https://github.com/Mic92/sops-nix/issues/340>

- Factor out the huge amount of duplication for Disko between the devices

> \[!WARNING\]
>
> When using the `--build-on-remote` flag with `nixos-anywhere`, make sure the remote account is one which Nix trusts. In the NixOS installer, this means `root` instead of `nixos`.

> \[!NOTE\]
>
> When using impermanence rooted at `/persist`, it's important that the directory provided to `--extra-files` is has a root of `/persist`. For example, instead of using `--extra-files ./secret_deployment_files/etc/ssh`, `--extra-files ./secret_deployment_files/persist/etc/ssh`.

> \[!NOTE\]
>
> When using sops `/etc/ssh/ssh_host_rsa_key` must be present, as it is needed to create the GPG keyring.

## `nixos-desktop`

Generate the secret age key using `ssh-to-age`:

```bash
mkdir -p ~/.config/sops/age
ssh-to-age -private-key -i ~/.ssh/id_ed25519 >> ~/.config/sops/age/keys.txt
```

Do this for whichever private keys are necessary.

Deploy `nixos-desktop` with:

```bash
nix run "github:nix-community/nixos-anywhere/4c94cecf3dd551adf1359fb06aa926330f44e5a6" --builders '' -- \
  connorbaker@192.168.1.12 \
  -i ~/.ssh/id_ed25519 \
  --kexec https://gh-v6.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz \
  --flake .#nixos-desktop \
  --build-on-remote \
  --print-build-logs \
  --debug \
  --extra-files /Volumes/nixos-desktop
```

## `nixos-build01`

Deploy `nixos-build01` with:

```bash
nix run "github:nix-community/nixos-anywhere/4c94cecf3dd551adf1359fb06aa926330f44e5a6" --builders '' -- \
  connorbaker@192.168.1.14 \
  -i ~/.ssh/id_ed25519 \
  --kexec https://gh-v6.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz \
  --flake .#nixos-build01 \
  --build-on-remote \
  --print-build-logs \
  --debug \
  --extra-files /Volumes/nixos-build01
```

## `nixos-ext`

Deploy `nixos-ext` with:

```bash
nix run "github:nix-community/nixos-anywhere/4c94cecf3dd551adf1359fb06aa926330f44e5a6" --builders '' -- \
  connorbaker@192.168.1.13 \
  -i ~/.ssh/id_ed25519 \
  --kexec https://gh-v6.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz \
  --flake .#nixos-ext \
  --build-on-remote \
  --print-build-logs \
  --debug \
  --extra-files /Volumes/nixos-ext
```

## `nixos-orin`

TODO:

- \[ \] The normal `aarch64-linux` tarball `kexec` image doesn't work, presumably because the Jetson is ✨special✨.
  - In progress: creating a custom `kexec` image using the Jetpack kernel.

Deploy `nixos-orin` with:

```bash
nix run github:numtide/nixos-anywhere/17efd86530884d11bff52148a5ff2259e2e869ed -- \
  root@192.168.1.204 \
  -i ~/.ssh/id_ed25519 \
  --flake .#nixos-ext \
  --build-on-remote \
  --extra-files /Volumes/nixos-orin
```

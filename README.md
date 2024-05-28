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
> When using `sops`, `/etc/ssh/ssh_host_rsa_key` must be present, as it is needed to create the GPG keyring.

> \[!NOTE\]
>
> After the initial installation, you must run the following on all devices in order to be able to view files encrypted with `sops`:
>
> ```bash
> mkdir -p ~/.config/sops/age
> sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key >> ~/.config/sops/age/keys.txt
> ```

> \[!NOTE\]
>
> When creating files with `sops` which can be read by multiple keys, the device creating the file must have access to all the keys. This is because the device creating the file will encrypt the file with all the keys, and the device reading the file will decrypt the file with the correct key.

## Binary caches

> \[!NOTE\]
>
> To delete everything:
>
> ```console
> sudo systemctl stop atticd.service caddy.service postgresql.service
> sudo rm -rf /var/log/caddy /var/lib/{atticd,caddy,postgresql}
> ```

> \[!IMPORTANT\]
>
> Caddy provisions a certificate for the domain, so be aware you will lose that and frequent re-creations will cause Let's Encrypt to rate limit you.

### Provision tokens

Create an admin token (hereafter `cuda-admin`) with

```console
sudo atticd-atticadm make-token --sub cuda-admin --validity 1y \
  --pull "*" \
  --push "*" \
  --delete "*" \
  --create-cache "*" \
  --configure-cache "*" \
  --configure-cache-retention "*" \
  --destroy-cache "*"
```

Create a builder token (hereafter `cuda-builder`) with

```console
sudo atticd-atticadm make-token --sub cuda-builder --validity 1y \
  --pull builder-cache \
  --push builder-cache
```

> \[!NOTE\]
>
> The `pull` permission is required for the builder token to be able to successfully push to the cache.

Create a user token (hereafter `cuda-user`) with

```console
sudo atticd-atticadm make-token --sub cuda-user --validity 1y \
  --pull cuda
```

> \[!NOTE\]
>
> After creating a cache with the `cuda-admin` token, it is import to log in with the limited token to overwrite the entry in `~/.config/attic/config.toml`. If we do not, the previous token used, the admin token, will remain in effect.

### Create `cuda-builder` cache

This cache is used for pushing to the global cache, typically by CI or builders. We use the `direct` subdomain because it is not proxied by Cloudflare, allowing us to upload files larger than 100MB.

Log in to the server with

```console
attic login cuda-builder https://direct.cantcache.me <cuda-admin token>
```

Create the cache with

```console
attic cache create cuda-builder:builder-cache
```

Log in with the token with

```console
attic login cuda-builder https://direct.cantcache.me <cuda-builder token>
```

### Create `cuda-user` cache

This cache is used by end-users to pull from the global cache -- however, they will use the `cantcache` subdomain, which is proxied by Cloudflare.

Log in to the server with

```console
attic login cuda-user https://cantcache.me <cuda-admin token>
```

Create the cache with

```console
attic cache create cuda-user:cuda --public
```

Get the public key and binary cache endpoint for the cache with

```console
attic cache info cuda-user:cuda
```

Log in with the token with

```console
attic login cuda-user https://cantcache.me <cuda-builder token>
```

### Push to `cuda-builder`

Assuming attic is configured to use the `direct` subdomain, push to the cache with

```console
attic push cuda-builder:builder-cache <store paths>
```

Alternatively, run and push new store paths with

```console
attic watch-store cuda-builder:builder-cache
```

### Use `cuda-server`

Set up Nix for the local user to pull from the cache with

```console
attic use cuda-server:cuda
```

edit your `~/.config/nix/nix.conf` to include

```conf
substituters = https://cantcache.me/cuda https://cache.nixos.org
trusted-public-keys = cuda:hfPDBopnLbzD3vux+Eu6yJNyKwG167E87s1vZzKtCkQ= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

## `nixos-desktop`

Generate the secret age key using `ssh-to-age`:

```bash
mkdir -p ~/.config/sops/age
sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key >> ~/.config/sops/age/keys.txt
```

Do this for whichever private keys are necessary.

Deploy `nixos-desktop` with:

```bash
nix run "github:nix-community/nixos-anywhere/242444d228636b1f0e89d3681f04a75254c29f66" --builders '' -- \
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
nix run "github:nix-community/nixos-anywhere/242444d228636b1f0e89d3681f04a75254c29f66" --builders '' -- \
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
nix run "github:nix-community/nixos-anywhere/242444d228636b1f0e89d3681f04a75254c29f66" --builders '' -- \
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

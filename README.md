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

## Binary caches

We use two server names, with a cache on each: one for pushing and one for pulling. Since they're backed by the same global cache, we can use the same host for both. However, we need to use different server names to disambiguate the caches because they use different subdomains.

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

> \[!NOTE\]
>
> To delete everything:
>
> ```console
> sudo systemctl stop atticd.service caddy.service postgresql.service
> sudo rm -rf /var/log/caddy /var/lib/{atticd,caddy,postgresql}
> ```
>
> IMPORTANT: Caddy provisions a certificate for the domain, so be aware you will lose that and Let's Encrypt will rate limit you.

### Create `cuda-server-push` cache

This cache is used for pushing to the global cache, typically by CI or builders. We use the `direct` subdomain because it is not proxied by Cloudflare, allowing us to upload files larger than 100MB.

Log in to the server with

```console
attic login cuda-server-push https://direct.cantcache.me <cuda-admin token>
```

Create the cache with

```console
attic cache create cuda-server-push:cuda --private
```

Create a token with

```console
sudo atticd-atticadm make-token --sub cuda-builder --validity 1y \
  --push cuda
```

Log in with the token with

```console
attic login cuda-server-push https://direct.cantcache.me <cuda-builder token>
```

> \[!NOTE\]
>
> It is important to log in afterwards with the limited token to overwrite the entry in `~/.config/attic/config.toml` with the limited token. If we do not, the previous token used, the admin token, will remain in effect.

### Push to `cuda-server-push`

Push to the cache with

```console
attic push cuda-server-push:cuda <store paths>
```

Alternatively, run and push new store paths with

```console
attic watch-store cuda-server-push:cuda
```

### Create `cuda-server`

This cache is used for pulling from the global cache, typically by users. We use the proxied domain to benefit from Cloudflare's caching.

Log in to the server with

```console
attic login cuda-server https://cantcache.me <cuda-admin token>
```

Create the cache with

```console
attic cache create cuda-server:cuda --public
```

Create a token with

```console
sudo atticd-atticadm make-token --sub cuda-user --validity 1y \
  --pull cuda
```

Log in with the token with

```console
attic login cuda-server https://cantcache.me <cuda-user token>
```

> \[!NOTE\]
>
> It is important to log in afterwards with the limited token to overwrite the entry in `~/.config/attic/config.toml` with the limited token. If we do not, the previous token used, the admin token, will remain in effect.

### Use `cuda-server`

Set up Nix for the local user to pull from the cache with

```console
attic use cuda-server:cuda
```

Alternatively edit your `~/.config/nix/netrc` to include

```netrc
machine cantcache.me
password eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NDcwMTQ3NDQsInN1YiI6ImN1ZGEtdXNlciIsImh0dHBzOi8vand0LmF0dGljLnJzL3YxIjp7ImNhY2hlcyI6eyJjdWRhIjp7InIiOjF9fX19.xUkKcsxmAeyYFe1HcyJ-STMiAuuNL_6aSJN1_KKkWzo
```

and your `~/.config/nix/nix.conf` to include

```conf
substituters = https://cantcache.me/cuda https://cache.nixos.org
trusted-public-keys = cuda:NtbpAU7XGYlttrhCduqvpYKottCPdWVITWT+3nFVTBY= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
netrc-file = /home/connorbaker/.config/nix/netrc
```

## `nixos-desktop`

Generate the secret age key using `ssh-to-age`:

```bash
mkdir -p ~/.config/sops/age
ssh-to-age -private-key -i ~/.ssh/id_ed25519 >> ~/.config/sops/age/keys.txt
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

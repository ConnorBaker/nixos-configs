{ lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix

    # Disks and formatting
    ./disko.nix
    ./zram-writeback.nix

    # Secrets
    ./secrets.nix

    ../../profiles/builder.nix
  ];

  # Every NixOS Brev (AWS) instance runs this one configuration, installed by
  # nix-brev's `brev-worker create --nixos` with nixos-anywhere over the
  # Ubuntu image Brev created: a Tribuchet worker, on the instance-store NVMe
  # (disko.nix). What differs between instances is written at install: the
  # name, to /persist/etc/hostname.

  # The builder profile's workstation parts, which a worker never runs; they
  # made up about 1 of the system's 4.9 GiB.
  documentation.enable = false;
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };
  users.users.connorbaker.packages = lib.mkForce [ ];
  virtualisation.docker.enable = lib.mkForce false;

  # brev-worker's scripts on the host (stop-worker, health --builds).
  environment.systemPackages = [ pkgs.jq ];

  environment.etc = {
    # The instance's name. systemd reads it at boot, so Tailscale and
    # nix-grpc-daemon (workerName below) take it from there.
    hostname.source = "/persist/etc/hostname";
    # Shared by every instance: secrets.yaml is encrypted to this key, and
    # brev-worker keeps its private half (README in nix-brev).
    "ssh/ssh_host_ed25519_key.pub".source = ./keys/ssh_host_ed25519_key.pub;
  };

  networking = {
    # Same on every instance: no pool moves between them.
    hostId = "4d6d98d0";
    # Set at runtime from /etc/hostname above.
    hostName = "";
  };

  # Unset, nix-grpc-daemon names itself after the running hostname.
  services.nix-grpc-daemon.workerName = lib.mkForce null;

  services.tribuchet-worker = {
    agents = lib.mkForce 8;
    settings.max-jobs = lib.mkForce 8;
  };

  # 123.5 GiB of RAM on m8id.8xlarge: 80% for the builds. The ARC, which is
  # not charged to the slice, keeps ZFS's default limit and shrinks under
  # memory pressure, as on nixos-configs' other hosts.
  systemd.slices."system-tribuchet\\x2dagent".sliceConfig.MemoryMax = "80%";

  # brev-worker reaches every instance, Ubuntu or NixOS, as Brev's SSH user
  # (the API's hostSshUser, "ubuntu") with Brev's key, ~/.brev/brev.pem.
  # Its list, health, ssh and stop-worker then work here unchanged. Wheel
  # gives it passwordless sudo and makes it a trusted Nix user.
  users.users.ubuntu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./keys/brev.pub ];
  };

  # The store name of the system, which has no hostName to take it from.
  system = {
    name = "brev-worker";
    stateVersion = "26.11";
  };
}

{
  config,
  pkgs,
  ...
}:
{
  # Instance types with instance-store NVMe (m8id): the Tribuchet agents'
  # build trees go on a ZFS pool across those disks instead of the EBS volume
  # (gp3, by default 125 MiB/s; nix-brev's README has brev-x86-15's
  # measurements). AWS hands out blank disks at every start, while a reboot
  # keeps them, so the pool is imported or else created at every boot.
  # Instance types without such disks keep the agents' trees on rpool.
  systemd.services.instance-store = {
    description = "Tribuchet agents' build trees on the instance-store NVMe";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    # The worker reaches its state through /var/lib/tribuchet/worker, the
    # link to /var/lib/private that systemd makes for its DynamicUser
    # StateDirectory at start. Started before the mount, its link would
    # be hidden under it. Ordered from here, a switch does not restart it.
    before = [ "tribuchet-worker.service" ];
    path = [
      config.boot.zfs.package
      pkgs.lvm2
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # The disks' model, read in the shell: lsblk's failure stops the unit,
    # where one inside a process substitution would read as "no disks".
    script = ''
      devices=$(lsblk -dnpo NAME,MODEL)
      disks=()
      while read -r disk model; do
        if [ "$model" = "Amazon EC2 NVMe Instance Storage" ]; then disks+=("$disk"); fi
      done <<<"$devices"
      if [ "''${#disks[@]}" -eq 0 ]; then
        echo "no instance-store disks; build trees stay on rpool"
        exit 0
      fi
      # Mounting under running builds would break them: a switch that
      # restarts this unit then leaves the trees for the next boot.
      if ! mountpoint -q /var/lib/tribuchet &&
        systemctl list-units --plain --no-legend --state=active 'tribuchet-agent@*.service' | grep -q .; then
        echo "agents are running builds; build trees move to the instance store at the next boot"
        exit 0
      fi
      if ! zpool list scratch >/dev/null 2>&1; then
        # The pool sits on partition 1 of each disk, which `-d DISK` does
        # not search; by-id lists the partitions too.
        if ! zpool import -f -N -d /dev/disk/by-id scratch; then
          # Brev's Ubuntu made them an LVM volume group (vg.01) on its
          # first boot, before nixos-anywhere, and NixOS activates it,
          # which keeps the disks busy. They hold scratch only.
          for d in "''${disks[@]}"; do
            vg=$(pvs --noheadings -o vg_name "$d" 2>/dev/null | tr -d ' ') || true
            if [ -n "$vg" ]; then vgchange -an "$vg"; fi
            wipefs -a "$d"
          done
          echo "creating pool scratch on ''${disks[*]}"
          zpool create -f -o ashift=12 -O mountpoint=none -O canmount=off \
            -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
            -O sync=disabled scratch "''${disks[@]}"
        fi
      fi
      zfs list scratch/tribuchet >/dev/null 2>&1 || zfs create -o mountpoint=legacy scratch/tribuchet
      mkdir -p /var/lib/tribuchet
      mountpoint -q /var/lib/tribuchet || mount -t zfs scratch/tribuchet /var/lib/tribuchet
    '';
  };

  # Wants, not Requires: if the pool fails, the agents still build on rpool.
  systemd.services."tribuchet-agent@" = {
    after = [ "instance-store.service" ];
    wants = [ "instance-store.service" ];
  };
}

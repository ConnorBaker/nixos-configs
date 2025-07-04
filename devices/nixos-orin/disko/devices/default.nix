{
  imports = [
    # Physical disks and formatting.
    ./disk.nix

    # ZFS pools and datasets.
    ./zpool.nix
  ];
}

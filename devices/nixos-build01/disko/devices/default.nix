{
  imports = [
    # Physical disks and formatting.
    ./disk.nix

    # Temporary filesystems.
    ./nodev.nix

    # ZFS pools and datasets.
    ./zpool.nix
  ];
}

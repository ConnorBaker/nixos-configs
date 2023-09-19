{
  imports = [
    # Physical disks and formatting.
    ./disk.nix

    # Temporary filesystems.
    ./nodev.nix
  ];
}

{
  # zram (modules/zram.nix) holds swapped pages in RAM. Pages that do not
  # compress, and pages untouched for a writeback interval, go to the NVMe
  # partition instead. This kernel lacks CONFIG_ZRAM_TRACK_ENTRY_ACTIME,
  # so age is tracked by marking every page idle each round: a page still
  # idle at the next round has not been touched since.
  zramSwap.writebackDevice = "/dev/disk/by-partlabel/disk-nvme-zram-writeback";
  systemd.services.zram-writeback = {
    description = "Write idle and incompressible zram pages to the NVMe";
    serviceConfig.Type = "oneshot";
    script = ''
      cd /sys/block/zram0
      if [ "$(cat backing_dev)" = none ]; then
        echo "zram0 has no backing device"
        exit 0
      fi
      echo huge > writeback
      echo idle > writeback
      echo all > idle
      cat bd_stat
    '';
  };
  systemd.timers.zram-writeback = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "10min";
    };
  };
}

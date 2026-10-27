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
      # Each of the three steps walks every slot of the device, about 1.8 s
      # of CPU each on a 400%-of-RAM device even when nothing is swapped, so
      # skip the round while zram holds no pages in memory (mm_stat's
      # mem_used_total; orig_data_size keeps counting the swap header's
      # page after it is written back).
      read -r _ _ used _ <mm_stat
      if [ "$used" -eq 0 ]; then
        echo "zram0 holds no pages in memory"
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

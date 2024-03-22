{
  # Tune the configuration to take advantage of the ZRAM swap device.
  boot.kernel.sysctl = {
    # https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;
    # https://github.com/pop-os/default-settings/blob/master_noble/etc/sysctl.d/10-pop-default-settings.conf
    "vm.swappiness" = 250; # Strong preference for ZRAM
    "vm.max_map_count" = 2147483642;
    # Higher values since these machines are used mostly as remote builders
    "vm.dirty_ratio" = 80;
    "vm.dirty_background_ratio" = 50;
  };

  zramSwap = {
    algorithm = "zstd";
    enable = true;
    memoryPercent = 400;
    # TODO: Consider a writeback device to avoid OOMs.
    # https://wiki.archlinux.org/title/Zram#Enabling_a_backing_device_for_a_zram_block
  };
}

{
  pkgs,
  ...
}: {
  boot = {
    initrd = {
      compressor = "zstd";
      compressorArgs = ["-19"];
      kernelModules = ["nvme"];
    };
    kernelPackages = pkgs.linuxPackages_latest;
    loader.systemd-boot.enable = true;
    tmp.cleanOnBoot = true;
  };
}

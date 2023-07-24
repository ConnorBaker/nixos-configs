{pkgs, ...}: {
  boot = {
    initrd = {
      compressor = "zstd";
      compressorArgs = ["-19"];
    };
    kernelPackages = pkgs.linuxPackages_latest;
    tmp.cleanOnBoot = true;
  };
}

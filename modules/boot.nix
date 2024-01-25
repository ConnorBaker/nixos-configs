{
  boot = {
    initrd = {
      compressor = "zstd";
      compressorArgs = [ "-19" ];
    };
    tmp.cleanOnBoot = true;
  };
  systemd.enableEmergencyMode = false;
}

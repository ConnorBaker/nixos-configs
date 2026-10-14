{
  boot = {
    initrd = {
      compressorArgs = [ "-19" ];
    };
    tmp.cleanOnBoot = true;
  };
  systemd.enableEmergencyMode = false;
}

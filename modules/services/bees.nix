{
  services.beesd.filesystems.root = {
    extraOptions = ["--loadavg-target" "5.0"];
    hashTableSizeMB = 16384;
    spec = "LABEL=nixos";
    verbosity = "crit";
  };
}

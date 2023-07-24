{
  services.beesd.filesystems = {
    extraOptions = ["--loadavg-target" "5.0"];
    hashTableSizeMB = 16384;
    spec = "LABEL=root";
    verbosity = "crit";
  };
}

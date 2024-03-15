{
  programs.htop = {
    enable = true;
    settings = {
      column_meter_modes_0 = [
        1
        2
        2
        2
      ];
      column_meter_modes_1 = [
        1
        2
        2
        2
      ];
      column_meters_0 = [
        "LeftCPUs4"
        "Memory"
        "Zram"
        "NetworkIO"
      ];
      column_meters_1 = [
        "RightCPUs4"
        "DiskIO"
        "ZFSARC"
        "ZFSCARC"
      ];
      header_layout = "two_50_50";
      show_cpu_frequency = 1;
      show_cpu_temperature = 1;
    };
  };
}

{
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/scan/not-detected.nix"
    "${modulesPath}/virtualisation/azure-common.nix"
  ];

  boot = {
    # Would require initrd systemd
    # initrd.systemd.emergencyAccess = lib.mkForce true;
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "pci-hyperv" # TODO(@connorbaker): This was missing and required for HB series.
      "usbhid"
      "xhci_pci"
    ];
    kernelModules = [ "kvm-amd" ];
    kernelParams = [ "amd_pstate=active" ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  hardware = {
    cpu.amd.updateMicrocode = true;
    enableAllFirmware = true;
  };

  powerManagement.cpuFreqGovernor = "performance";

  virtualisation.azure.acceleratedNetworking = true;

  # TODO(@connorbaker): This should be included in azure-common.nix as well.
  services.udev.packages = [
    (pkgs.runCommand "azure-udev-rules" { } ''
      mkdir -p $out/lib/udev/rules.d
      cp ${pkgs.cloud-init}/lib/python*/site-packages/usr/lib/udev/rules.d/66-azure-ephemeral.rules $out/lib/udev/rules.d/
    '')
  ];

  # systemd.network.networks."10-ethernet" = {
  #   linkConfig.MACAddress = "e8:9c:25:5e:3b:92";
  #   networkConfig = {
  #     Address = "192.168.1.14/24";
  #     Gateway = "192.168.1.1";
  #   };
  # };
}

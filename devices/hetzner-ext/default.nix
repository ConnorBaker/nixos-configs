{
  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "sd_mod"
      "xhci_pci"
    ];
    kernelModules = ["kvm-intel"];
    loader.grub = {
      copyKernels = true;
      enable = true;
    };
  };

  disko.devices.disk.main = let
    interface = "ata";
    model = "ST12000NM0017";
    serial = "2A1111_ZJV05SVK";
  in {
    device = "/dev/disk/by-id/${interface}-${model}-${serial}";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # for grub MBR
        };
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            format = "vfat";
            mountpoint = "/boot";
            type = "filesystem";
          };
        };
        root = {
          size = "100%";
          content = {
            format = "ext4";
            mountpoint = "/";
            type = "filesystem";
          };
        };
      };
    };
  };

  hardware = {
    cpu = {
      amd.updateMicrocode = true;
      intel.updateMicrocode = true;
    };
    enableAllFirmware = true;
  };

  nix = {
    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      system-features = [
        "benchmark"
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
      trusted-users = [
        "@nixbld"
        "@wheel"
        "root"
      ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  networking = {
    hostName = "hetzner-ext";
    hostId = "deadbee5";
    useNetworkd = true;
    usePredictableInterfaceNames = false;
  };

  powerManagement.cpuFreqGovernor = "powersave";

  security.sudo = {
    execWheelOnly = true;
    wheelNeedsPassword = false;
  };

  services.openssh = {
    allowSFTP = true;
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      X11Forwarding = false;
    };
  };

  system.stateVersion = "23.05";

  systemd.network = {
    enable = true;
    networks = {
      "eth0".extraConfig = ''
        [Match]
        Name = eth0
        [Network]
        # Add your own assigned ipv6 subnet here here!
        Address = 2a01:4f9:6a:1692::2/64
        Gateway = fe80::1
        DNS = 2a01:4f9:c010:3f02::1
      '';
      "eno1".extraConfig = ''
        [Match]
        Name = eno1
        [Network]
        # Add your own assigned ipv6 subnet here here!
        Address = 2a01:4f9:6a:1692::2/64
        Gateway = fe80::1
        DNS = 2a01:4f9:c010:3f02::1
      '';
    };
    wait-online = {
      anyInterface = true;
      timeout = 30;
    };
  };

  time.timeZone = "UTC";

  users.users = let
    keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJLd6kNEt/f89JGImBViXake15Y3VQ6AuKR/IBr1etpt connorbaker@nixos-desktop"
    ];
  in {
    root.openssh.authorizedKeys = {
      inherit keys;
    };
    connorbaker = {
      description = "Connor Baker's user account";
      extraGroups = ["wheel"];
      isNormalUser = true;
      openssh.authorizedKeys = {
        inherit keys;
      };
    };
  };
}

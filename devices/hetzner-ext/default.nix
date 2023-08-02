{lib, ...}: {
  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "sd_mod"
        "xhci_pci"
      ];
      # TODO(@connorbaker): Really? We specify it twice?
      supportedFilesystems = ["zfs"];
    };
    kernelModules = ["kvm-intel"];
    loader.grub = {
      copyKernels = true;
      enable = true;
    };
    supportedFilesystems = ["zfs"];
    zfs = {
      enableUnstable = true;
      forceImportRoot = false;
    };
  };

  disko.devices = {
    disk.main = let
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
          zroot = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };
    zpool.zroot = {
      type = "zpool";
      rootFsOptions = {
        acltype = "posixacl";
        normalization = "formD";
        xattr = "sa";
        "com.sun:auto-snapshot" = "false";
      };
      options = {
        ashift = "12";
        autotrim = "on";
      };
      mountpoint = "/";
      datasets = {};
    };
  };

  hardware = {
    cpu = {
      amd.updateMicrocode = true;
      intel.updateMicrocode = true;
    };
    enableAllFirmware = true;
  };

  nix.settings = {
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

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  networking = {
    hostName = "hetzner-ext";
    hostId = "deadbee5";
    useDHCP = false;
    useNetworkd = true;
  };

  powerManagement.cpuFreqGovernor = "powersave";

  security.sudo = {
    execWheelOnly = true;
    wheelNeedsPassword = false;
  };

  services = {
    openssh = {
      allowSFTP = true;
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
        X11Forwarding = false;
      };
    };
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };

  system.stateVersion = "23.05";

  systemd.network = {
    enable = true;
    networks."10-eno1" = {
      address = ["2a01:4f9:6a:1692::2/64"];
      DHCP = "no";
      dns = ["2a01:4f9:c010:3f02::1"];
      gateway = ["fe80::1"];
      name = "eno1";
      networkConfig = {
        LLMNR = false;
        DNSOverTLS = "opportunistic";
        DNSSEC = "allow-downgrade";
      };
    };
    wait-online.anyInterface = true;
  };

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

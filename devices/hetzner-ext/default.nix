{
  boot = {
    initrd = {
      availableKernelModules = [
        "ahci"
        "sd_mod"
        "xhci_pci"
      ];
      compressor = "zstd";
      compressorArgs = ["-19"];
    };
    kernelModules = ["kvm-intel"];
    kernelParams = ["nohibernate"];
    loader.grub = {
      copyKernels = true;
      efiSupport = false;
      enable = true;
    };
    tmp.cleanOnBoot = true;
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

  environment = {
    noXlibs = true;
    variables.BROWSER = "echo";
  };

  fonts.fontconfig.enable = false;

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

  powerManagement.cpuFreqGovernor = "powersave";

  networking = {
    dhcpcd.enable = false;
    hostName = "hetzner-ext";
    hostId = "deadbee5";
    useDHCP = false;
    useNetworkd = true;
  };

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

  sound.enable = false;

  system.stateVersion = "23.05";

  systemd = {
    network = {
      enable = true;
      networks."20-wired" = {
        matchConfig = {
          Name = "eno* eth*";
          MACAddress = "24:4b:fe:b8:5f:d9";
        };
        networkConfig = {
          Address = ["2a01:4f9:6a:1692::2/64"];
          Gateway = ["fe80::1"];
          DHCP = "yes";
          DNSSEC = "allow-downgrade";
          DNSOverTLS = "opportunistic";
          DNS = [
            # Kasper Dupont's Public NAT64 service: https://nat64.net
            "2a01:4f9:c010:3f02::1"
            "2a00:1098:2c::1"
            "2a00:1098:2b::1"
          ];
        };
        # TODO(@connorbaker): DHCP static leases?
        # https://github.com/NixOS/nixpkgs/blob/96d403ee2479f2070050353b94808209f1352edb/nixos/tests/systemd-networkd-dhcpserver-static-leases.nix#L30-L35
      };
      wait-online = {
        anyInterface = true;
        timeout = 30;
      };
    };
    sleep.extraConfig = ''
      AllowHibernation=no
      AllowSuspend=no
    '';
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

  zramSwap = {
    algorithm = "zstd";
    enable = true;
    memoryPercent = 200;
  };
}

{ pkgs, ... }:
{
  # An EC2 m8a or m8id (AMD EPYC, Nitro): EBS and instance-store volumes are
  # NVMe devices and the NIC is ENA. The instance boots by UEFI.
  boot = {
    initrd.availableKernelModules = [
      "ena"
      "nvme"
    ];
    kernelParams = [
      # EC2's serial console (get-console-output).
      "console=ttyS0,115200n8"
      # AWS's recommendation for EBS on NVMe: never time out an I/O, since
      # a detached or throttled volume otherwise turns the root read-only.
      "nvme_core.io_timeout=4294967295"
      # Reboot after a panic instead of hanging; GRUB then falls back to
      # its saved entry (below).
      "panic=30"
    ];
    loader = {
      efi.canTouchEfiVariables = false;
      # As NixOS's own EC2 images (amazon-image.nix): GRUB at
      # EFI/BOOT/BOOTX64.EFI, which EC2's "UEFI Amazon Elastic Block Store"
      # entry boots, with no UEFI variables. On brev-nixos-1 and -2,
      # systemd-boot installed this way never came up, and Brev gives no
      # console to say why.
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        efiInstallAsRemovable = true;
        # A way back without a console: brev-worker puts nixos-anywhere's
        # installer on the ESP, behind the rescue entry below, and makes it
        # grubenv's saved_entry. Each boot that gets as far as
        # grub-boot-nixos (below) sets next_entry, which boots NixOS once.
        # A boot that does not, e.g. one that panics, or one with no network
        # followed by a stop and start, ends in the installer, reachable as
        # root with Brev's key.
        default = "saved";
        extraEntries = ''
          menuentry "NixOS installer (rescue)" --id rescue {
            search --no-floppy --set=root --file /rescue/boot.cfg
            source ($root)/rescue/boot.cfg
          }
        '';
      };
    };
  };

  systemd.services.grub-boot-nixos = {
    description = "Boot NixOS, not the rescue entry, next time";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sshd.service"
    ];
    serviceConfig.Type = "oneshot";
    # Only where brev-worker installed the rescue entry's files.
    script = ''
      [ -e /boot/rescue/boot.cfg ] || exit 0
      ${pkgs.grub2}/bin/grub-editenv /boot/grub/grubenv set saved_entry=rescue next_entry=0
    '';
  };

  hardware.cpu.amd.updateMicrocode = true;
}

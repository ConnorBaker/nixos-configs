{pkgs, ...}: {
  imports = [
    ./hardware.nix
    ../common/boot.nix
    ../common/intel.nix
    ../common/mimalloc.nix
    ../common/networking.nix
    ../common/nix-cantcacheme.nix
    ../common/nix-cuda-maintainers.nix
    ../common/nix.nix
    ../common/openssh.nix
    ../common/sudo.nix
    ../common/tailscale.nix
    ../common/zram.nix
  ];
  
  networking.hostName = "nixos-desktop";

  nix.settings.trusted-users = ["connorbaker"];

  system.stateVersion = "23.05";

  users = {
    mutableUsers = false;
    users = {
      connorbaker = {
        description = "Connor Baker's user account";
        extraGroups = ["wheel"];
        isNormalUser = true;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
        ];
        packages = with pkgs; [bat exa gh git htop jq nixpkgs-review ripgrep vim];
      };
    };
  };
}

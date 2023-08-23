{
  config,
  lib,
  ...
}: {
  # nix = {
  #   buildMachines = [
  #     {
  #       hostName = "52.249.197.56";
  #       maxJobs = 1;
  #       protocol = "ssh-ng";
  #       # base64 -w0 - <<< "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL84WOm0Lij8ctWc0bcfx42F/ZTYO5/DD/OXzAtLBzSA"
  #       publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUw4NFdPbTBMaWo4Y3RXYzBiY2Z4NDJGL1pUWU81L0REL09YekF0TEJ6U0EK";
  #       sshKey = "/home/connorbaker/.ssh/id_ed25519";
  #       sshUser = "connorbaker";
  #       supportedFeatures = [
  #         "benchmark"
  #         "big-parallel"
  #         "kvm"
  #         "nixos-test"
  #       ];
  #       system = "x86_64-linux";
  #     }
  #   ];
  #   distributedBuilds = true;
  #   settings = {
  #     builders-use-substitutes = true;
  #     trusted-users = ["connorbaker"];
  #   };
  # };
  # TODO: services.openssh.authorizedKeysFiles
  nix.settings.trusted-users = ["connorbaker"];
  programs.git.config = lib.attrsets.optionalAttrs config.programs.git.enable {
    init.defaultBranch = "main";
    user.name = "Connor Baker";
    user.email = "connor.baker@tweag.io";
  };
  users.users = let
    opensshConfig.openssh.authorizedKeys = {
      keyFiles = [
        ../devices/nixos-desktop/keys/id_ed25519.pub
        ../devices/nixos-ext/keys/ssh_host_ed25519_key.pub
        ../devices/nixos-ext/keys/ssh_host_rsa_key.pub
      ];
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
    };
  in {
    root = opensshConfig;
    connorbaker =
      {
        description = "Connor Baker's user account";
        extraGroups = ["wheel"];
        isNormalUser = true;
      }
      // opensshConfig;
  };
}

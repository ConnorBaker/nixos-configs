{
  config,
  lib,
  pkgs,
  ...
}: {
  nix = {
    buildMachines = [
      {
        hostName = "52.249.197.56";
        maxJobs = 1;
        protocol = "ssh-ng";
        # base64 -w0 - <<< "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL84WOm0Lij8ctWc0bcfx42F/ZTYO5/DD/OXzAtLBzSA"
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUw4NFdPbTBMaWo4Y3RXYzBiY2Z4NDJGL1pUWU81L0REL09YekF0TEJ6U0EK";
        sshKey = "/home/connorbaker/.ssh/id_ed25519";
        sshUser = "connorbaker";
        supportedFeatures = [
          "benchmark"
          "big-parallel"
          "kvm"
          "nixos-test"
        ];
        system = "x86_64-linux";
      }
    ];
    distributedBuilds = true;
    settings = {
      builders-use-substitutes = true;
      trusted-users = ["connorbaker"];
    };
  };
  programs = {
    git.config = lib.attrsets.optionalAttrs config.programs.git.enable {
      init.defaultBranch = "main";
      user.name = "Connor Baker";
      user.email = "connor.baker@tweag.io";
    };
    # NOTE: Use mkOptionDefault to ensure our value is added to the list of
    # values, rather than replacing the list of values.
    nix-ld.libraries = lib.mkOptionDefault [pkgs.icu.out];
  };
  users.users = {
    connorbaker = {
      description = "Connor Baker's user account";
      extraGroups = ["wheel"];
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXpenPZWADrxK4+6nFmPspmYPPniI3m+3PxAfjbslg+ connorbaker@Connors-MacBook-Pro.local"
      ];
      packages = with pkgs;
      # Rust unix tools
        [
          bat
          exa
          ripgrep
        ]
        # Python
        ++ [
          black
          (python3.withPackages (ps: with ps; [pydantic requests typing-extensions]))
          ruff
        ]
        # C/C++
        ++ [
          cmake
          dotnet-runtime # for CMake LSP in VS Code
        ]
        # Misc tools
        ++ [
          gh
          git
          htop
          jq
          nvitop
          vim
        ]
        # Nix
        ++ [
          alejandra
          nil
          nix-output-monitor
          nixpkgs-review
        ]
        # Sops tools
        ++ [
          age
          sops
          ssh-to-age
        ];
    };
  };
}

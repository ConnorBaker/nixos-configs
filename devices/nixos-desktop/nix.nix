{
  nix = {
    buildMachines = [
      {
        hostName = "nixos-ext.rove-hexatonic.ts.net";
        maxJobs = 2;
        protocol = "ssh-ng";
        # base64 -w0 - <<< "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL84WOm0Lij8ctWc0bcfx42F/ZTYO5/DD/OXzAtLBzSA"
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBMUjVZYW9jamd4MU80VWFsK1h3UDFVTnRIMFFUVUt2K1pWK2lSSy8yNGUgcm9vdEBuaXhvcy1leHQK";
        sshKey = "/home/connorbaker/.ssh/nixos-ext-id_ed25519";
        sshUser = "connorbaker";
        supportedFeatures = [
          "benchmark"
          "big-parallel"
          "kvm"
          "nixos-test"
        ];
        system = "x86_64-linux";
      }
      {
        hostName = "nixos-build01.rove-hexatonic.ts.net";
        maxJobs = 2;
        protocol = "ssh-ng";
        # base64 -w0 - <<< "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCSiOOQCQMwIcFf4fAULiPu6OpozyY4+Ug41AR0wBqu root@nixos-build01"
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpDU2lPT1FDUU13SWNGZjRmQVVMaVB1Nk9wb3p5WTQrVWc0MUFSMHdCcXUgcm9vdEBuaXhvcy1idWlsZDAxCg==";
        sshKey = "/home/connorbaker/.ssh/nixos-ext-id_ed25519";
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
    settings.builders-use-substitutes = true;
  };
}

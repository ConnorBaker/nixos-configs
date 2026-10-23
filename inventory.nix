{
  tailnet = "rove-hexatonic.ts.net";
  gateway = "192.168.1.1";
  hub = "nixos-ext";

  # Keep fleet metadata independent of evaluated NixOS configurations.
  hosts = builtins.mapAttrs (_: host: host // { system = builtins.head host.systems; }) {
    nixos-build01 = {
      systems = [ "x86_64-linux" ];
      features = [ ];
      maxJobs = 3;
      mandatoryFeatures = [ ];
      nixos = true;
      sshHostKey = ./devices/nixos-build01/keys/ssh_host_ed25519_key.pub;
      lan = {
        ipv4 = "192.168.1.14";
        primaryMAC = "e8:9c:25:5e:3b:92";
      };
    };
    nixos-desktop = {
      systems = [ "x86_64-linux" ];
      features = [ "cuda" ];
      maxJobs = 2;
      mandatoryFeatures = [ "cuda" ];
      nixos = true;
      sshHostKey = ./devices/nixos-desktop/keys/ssh_host_ed25519_key.pub;
      lan = {
        ipv4 = "192.168.1.12";
        primaryMAC = "58:11:22:b4:9d:69";
        secondaryMAC = "58:11:22:b4:9d:68";
      };
    };
    # The hub's queue bounds the pool; connected workers bound actual jobs.
    nixos-ext = {
      systems = [ "x86_64-linux" ];
      features = [ ];
      maxJobs = 32;
      mandatoryFeatures = [ ];
      nixos = true;
      sshHostKey = ./devices/nixos-ext/keys/ssh_host_ed25519_key.pub;
      lan = {
        ipv4 = "192.168.1.13";
        primaryMAC = "e8:9c:25:5e:3c:6d";
        secondaryMAC = "08:bf:b8:13:a2:61";
      };
    };
    nixos-orin = {
      systems = [ "aarch64-linux" ];
      features = [ "cuda" ];
      maxJobs = 3;
      mandatoryFeatures = [ "cuda" ];
      nixos = true;
      sshHostKey = ./devices/nixos-orin/keys/ssh_host_ed25519_key.pub;
    };
    # Ubuntu DGX Spark also serves CPU jobs, so CUDA is not mandatory.
    spark-ee4c = {
      systems = [ "aarch64-linux" ];
      features = [ "cuda" ];
      maxJobs = 3;
      mandatoryFeatures = [ ];
      nixos = false;
    };
  };
}

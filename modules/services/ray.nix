{ pkgs, ... }:
let
  python311 = pkgs.python311;
  ray = python311.pkgs.ray.overridePythonAttrs {
    version = "2.30.0";
    src =
      let
        pyShortVersion = "cp311";
      in
      pkgs.fetchPypi {
        pname = "ray";
        version = "2.30.0";
        format = "wheel";
        dist = pyShortVersion;
        python = pyShortVersion;
        abi = pyShortVersion;
        platform = "manylinux2014_x86_64";
        # NOTE: This hash is only for 3.11
        hash = "sha256-4gO1dWWgCPKsn54ekpIW4NfXdvU0FEzMePZsEFI09wE=";
      };
  };
in
{
  networking.firewall = {
    allowedTCPPorts = [
      6379
      8265
    ];
    allowedUDPPorts = [
      6379
      8265
    ];
  };
  systemd.services.ray-agent = {
    description = "ray-agent";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig =
      let
        RAY_ADDRESS = "192.168.1.216:6379";
      in
      {
        RestartSec = 10;
        Restart = "on-failure";
        Environment = [
          "RAY_ADDRESS=${RAY_ADDRESS}"
          "RAY_ENABLE_WINDOWS_OR_OSX_CLUSTER=1"
        ];
        TimeoutStartSec = "infinity";
        ExecStart =
          let
            python-env = python311.withPackages (_: [ ray ]);
          in
          "${python-env}/bin/ray start --address=${RAY_ADDRESS} --block";
      };
  };
}

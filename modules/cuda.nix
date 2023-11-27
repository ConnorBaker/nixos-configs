{
  nix.settings =
    let
      substituters = [ "https://cuda-maintainers.cachix.org" ];
    in
    {
      extra-substituters = substituters;
      extra-trusted-substituters = substituters;
      extra-trusted-public-keys = [
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
    };
  nixpkgs.config = {
    allowUnfree = true;
    cudaSupport = true;
  };
}

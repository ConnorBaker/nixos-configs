{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = {self, nixpkgs}: {
    nixosConfigurations = import ./nixosConfigurations nixpkgs;
  };
}

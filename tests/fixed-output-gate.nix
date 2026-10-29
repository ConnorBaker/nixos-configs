# modules/nix/fixed-output-gate.nix on a host with max-jobs = 0, as off the
# hub. With the gate, Nix refuses every sandboxed local build it would give
# the network (fixed-output, builtin:fetchurl, impure), for an untrusted
# user through the daemon with any --max-jobs and for root in-process;
# without it (the control), the same derivations build. Either way, other
# builds, GPU builds with the mounts of nix-required-mounts' hook, which the
# gate runs next, and fixed-output builds handed to an external builder (the
# hub's Tribuchet) build. A trusted user can turn the hook or the sandbox
# off for its own builds; this does not test that.
{ pkgs, gate }:
let
  inherit (pkgs) lib;
  hash = "sha256-mOpuTyFvL7S2n/+bOkSELDhobKaF8/VdxIxdP7EQe+Q="; # "hi\n"
  # Stands in for Tribuchet's attach program: prints the ready line Nix
  # waits for after starting a builder, as attach does, and writes the
  # output itself.
  externalBuilder = pkgs.writeShellScript "fake-external-builder" ''
    printf '\2\n' >&2
    printf 'hi\n' > "$(${lib.getExe pkgs.jq} -r .outputs.out "$1")"
  '';
  derivations = pkgs.writeText "fixed-output-gate.nix" ''
    let
      sh = name: extra: derivation ({
        inherit name;
        system = builtins.currentSystem;
        builder = "/bin/sh";
        args = [ "-c" "echo hi > $out" ];
      } // extra);
      fixed = { outputHashMode = "flat"; outputHash = "${hash}"; };
    in
    {
      plain = sh "plain" { };
      plainRoot = sh "plain-root" { };
      gpu = derivation {
        name = "gpu";
        system = builtins.currentSystem;
        builder = "/bin/sh";
        # read sets x but fails on a last line without a newline.
        args = [ "-c" "read -r x < /run/gate-chain; [ \"$x\" = chained ] || { echo \"/run/gate-chain: $x\" >&2; exit 1; }; echo hi > $out" ];
        requiredSystemFeatures = [ "cuda" ];
      };
      fixed = sh "fixed" fixed;
      fixedBuiltin = derivation ({
        name = "fixed-builtin";
        system = "builtin";
        builder = "builtin:fetchurl";
        url = "file://''${builtins.toFile "hi" "hi\n"}";
      } // fixed);
      impure = sh "impure" { __impure = true; };
      fixedExternal = derivation ({
        name = "fixed-external";
        system = "riscv64-linux";
        builder = "/bin/sh";
      } // fixed);
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "fixed-output-gate${lib.optionalString (!gate) "-without"}";
  nodes.machine = {
    imports = lib.optional gate ../modules/nix/fixed-output-gate.nix;
    environment.etc."fixed-output-gate.nix".source = derivations;
    nix.settings = {
      max-jobs = 0;
      substituters = lib.mkForce [ ];
      # nix-required-mounts' hook runs `nix show-derivation`.
      experimental-features = [
        "ca-derivations"
        "external-builders"
        "impure-derivations"
        "nix-command"
      ];
      external-builders = builtins.toJSON [
        {
          systems = [ "riscv64-linux" ];
          program = toString externalBuilder;
          args = [ ];
        }
      ];
      system-features = [ "cuda" ];
    };
    programs.nix-required-mounts = {
      enable = true;
      allowedPatterns.gpu = {
        onFeatures = [ "cuda" ];
        paths = [ "/run/gate-chain" ];
        unsafeFollowSymlinks = false;
      };
    };
    systemd.tmpfiles.rules = [ "f /run/gate-chain 0444 root root - chained" ];
    users.users.alice.isNormalUser = true;
    virtualisation.writableStore = true;
  };
  testScript = ''
    import shlex

    gate = ${if gate then "True" else "False"}

    # nix-build fails on an impure derivation here ("cannot operate on output
    # 'out' of the unbuilt derivation"); Nix's own tests use nix build.
    def build(attr, user="root", jobs=None, ok=True):
        if attr == "impure":
            cmd = f"nix build --no-link --file /etc/fixed-output-gate.nix {attr}"
        else:
            cmd = f"nix-build /etc/fixed-output-gate.nix -A {attr} --no-out-link"
        if jobs is not None:
            cmd += f" --max-jobs {jobs}"
        if user != "root":
            cmd = f"su - {user} -c {shlex.quote(cmd)}"
        cmd += " 2>&1"
        out = machine.succeed(cmd) if ok else machine.fail(cmd)
        print(out)
        return out

    machine.wait_for_unit("multi-user.target")

    # max-jobs = 0: nothing builds here by default.
    assert "max-jobs = 0" in build("plain", ok=False)
    # Any client's --max-jobs reaches the daemon, an untrusted one's too.
    build("plain", user="alice", jobs=1)
    # Root builds in-process, from a .drv that stays in Tarmac's store.
    drv = machine.succeed("nix-instantiate /etc/fixed-output-gate.nix -A plainRoot").strip()
    machine.succeed(f"test ! -e {drv}")
    build("plainRoot", jobs=1)
    # GPU builds, which arrive through the daemon, get nix-required-mounts'
    # mounts: the gate runs its hook after the check.
    build("gpu", user="alice", jobs=1)
    # A build handed to an external builder never meets the hook.
    build("fixedExternal", jobs=1)
    # Builds with the network build here only without the gate.
    for attr, user in [("fixed", "alice"), ("impure", "alice"), ("fixedBuiltin", "root")]:
        out = build(attr, user=user, jobs=1, ok=not gate)
        assert ("refuse-local-fixed-output" in out) == gate, out
  '';
}

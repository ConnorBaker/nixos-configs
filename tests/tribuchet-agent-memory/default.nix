# The checks of the agents' memory policy
# (modules/services/tribuchet-agent-memory.nix): with Tribuchet's package
# and module as this flake pins them, on nixpkgs without our overlays, as
# Tribuchet's own checks run.
{
  inputs,
  system,
  tribuchetModule,
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;
  vmTest =
    file:
    pkgs.testers.runNixOSTest (
      import file {
        tribuchet = inputs.tribuchet.packages.${system}.default;
        nixosModule = tribuchetModule;
      }
    );
  # A worker with the policy for a 1536 MiB reserve, evaluated only.
  host = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      tribuchetModule
      {
        nixpkgs.hostPlatform = system;
        boot.isContainer = true;
        system.stateVersion = "25.11";
        services.tribuchet-worker = {
          enable = true;
          settings.hub = "https://hub.example.org:7437";
          agentMemoryReserve = 1536 * 1024 * 1024;
        };
      }
    ];
  };
  # The messages of the assertions that fail on `host` with `module`.
  failed =
    module:
    builtins.toJSON (
      map (a: a.message) (
        lib.filter (a: !a.assertion) (host.extendModules { modules = [ module ]; }).config.assertions
      )
    );
  # The four properties the policy sets on the slice, and a host that
  # sets `p` of them too.
  props = {
    MemoryMax = "80%";
    MemorySwapMax = 0;
    MemoryZSwapMax = 0;
    MemoryZSwapWriteback = true;
  };
  alsoSet = p: {
    systemd.slices."system-tribuchet\\x2dagent".sliceConfig = lib.getAttrs p props;
  };
in
{
  tribuchet-agent-memory = vmTest ./memory.nix;
  tribuchet-agent-memory-switch = vmTest ./switch.nix;
  tribuchet-agent-memory-repeat = vmTest ./repeat.nix;
  tribuchet-agent-memory-stop = vmTest ./stop.nix;

  # tribuchet-agent-guard as the module builds it for a 1536 MiB reserve,
  # against a stand-in systemd and cgroup: a clamp and the OOM kill; a
  # clamp a TERM left, undone by the next guard; a clamp applied after
  # its call failed; a restore that fails; a reload of the swap unit
  # during a clamp, and as the clamp's call returns; a clamp no OOM kill
  # follows, kept.
  tribuchet-agent-memory-guard =
    pkgs.runCommand "agent-memory-guard-test"
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          util-linux
          gnused
          gnugrep
        ];
      }
      ''
        bash ${./agent-memory-guard-test.sh} ${host.config.systemd.services.tribuchet-agent-guard.serviceConfig.ExecStart} >log 2>&1 || {
          cat log
          exit 1
        }
        cp log $out
      '';

  # A host that sets one of the slice's memory properties as well fails
  # evaluation, by that property's assertion and no other; with
  # agentMemoryReserve = null it keeps all four.
  tribuchet-agent-memory-assertion =
    pkgs.runCommand "tribuchet-agent-memory-assertion"
      (
        lib.mapAttrs (p: _: failed (alsoSet [ p ])) props
        // {
          own = failed {
            imports = [ (alsoSet (builtins.attrNames props)) ];
            services.tribuchet-worker.agentMemoryReserve = lib.mkForce null;
          };
        }
      )
      ''
        bad=
        for p in ${toString (builtins.attrNames props)}; do
          got=$({ grep -o 'agentMemoryReserve sets [A-Za-z]* of' <<<"''${!p}" || true; } | tr '\n' ' ')
          if [ "$got" != "agentMemoryReserve sets $p of " ]; then bad="$bad $p: [$got]"; fi
        done
        if grep -q 'agentMemoryReserve sets' <<<"$own"; then bad="$bad null: $own"; fi
        if [ -n "$bad" ]; then
          echo "AGENT-MEMORY-ASSERTION FAILED:$bad" >&2
          exit 1
        fi
        touch $out
      '';
}

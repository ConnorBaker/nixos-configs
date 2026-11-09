# NixOS VM test of the agents' memory (agentMemoryReserve, agentSwapPercent
# at its default). The worker has zram swap and the vm sysctls of the
# NixOS hosts; its agents' slice is capped at A, MemTotal less the reserve
# and less 256 bytes per page of its swap S (MemTotal), and swaps through
# zswap only. A build that outgrows A but compresses must succeed;
# runaways must be OOM-killed inside the slice, zero pages at S, random
# bytes once the guard clamps the slice's swap; a build whose child holds
# incompressible bytes past A outlives the child's kill; no agent is ever
# killed, not even when a build's memory counts toward no task (that an
# agent runs at -1000 and a build cannot lower its OOM score is
# Tribuchet's own e2e test). A 16 GiB VM checks at scale that the
# slice's RAM, zswap's uncharged metadata included, stays within MemTotal
# less the reserve, that zswap serves the slice alone, and that a random
# runaway dies within minutes. Everything is measured and printed
# (AGENT-MEMORY) before it is checked, and each check is reported on its
# own (AGENT-MEMORY-CHECK) before the test fails, so a run with another
# revision's module shows every difference.
{ tribuchet, nixosModule }:
{ pkgs, lib, ... }:
let
  mib = 1024 * 1024;
  # 1.5 GiB: on the worker's 3 GiB, A is about 1.25 GiB and S 2.9 GiB.
  reserve = 1536 * mib;
  am = import ./node.nix {
    inherit
      tribuchet
      nixosModule
      pkgs
      lib
      ;
  };
  fill =
    args:
    "import ${./slicefill.nix} ({ python3 = \"${pkgs.python3}\"; script = \"${./slicefill.py}\"; } // ${
      lib.generators.toPretty { } args
    })";
  hog = args: ''
    import ${./slicehog.nix} ({ bash = "${pkgs.bash}"; coreutils = "${pkgs.coreutils}"; } // ${
      lib.generators.toPretty { } args
    })
  '';
  # Every `interval` s until stopped, as one JSON line: the slice's
  # memory, swap, zswap pool and local events; zswap's state; zram's RAM;
  # and the phase the test script is in (/run/phase).
  monitor = pkgs.writeText "slice-monitor.py" ''
    import json, sys, time
    cg, out, interval = sys.argv[1], sys.argv[2], float(sys.argv[3])
    def read(path):
        try:
            return open(path).read()
        except OSError:
            return None
    def pairs(t):
        return dict((l.split()[0], int(l.split()[1])) for l in (t or "").splitlines() if len(l.split()) == 2)
    with open(out, "w") as f:
        while True:
            row = {"t": time.monotonic(), "phase": (read("/run/phase") or "").strip()}
            for k in ["memory.current", "memory.swap.current", "memory.zswap.current", "memory.max", "memory.swap.max"]:
                v = read(f"{cg}/{k}")
                row[k] = None if v is None else v.strip()
            row["events"] = pairs(read(f"{cg}/memory.events.local"))
            row["zswap_enabled"] = (read("/sys/module/zswap/parameters/enabled") or "").strip()
            mm = read("/sys/block/zram0/mm_stat")
            row["zram_mem_used"] = None if mm is None else int(mm.split()[2])
            print(json.dumps(row), file=f, flush=True)
            time.sleep(interval)
  '';
  # Runs a command in a cgroup under the slice that systemd does not
  # manage, as a build's is under its agent: the slice's zswap settings
  # apply, and no unit's.
  launch = pkgs.writeShellScript "slice-launch" ''
    ${pkgs.coreutils}/bin/mkdir -p "$1"
    echo $$ >"$1/cgroup.procs"
    shift
    exec "$@"
  '';
in
{
  name = "tribuchet-agent-memory";
  defaults.documentation.enable = false;
  # boot, nine builds and the 16 GiB node's runs take about 450 s
  globalTimeout = 570;

  nodes = {
    hub =
      { ... }:
      {
        environment.systemPackages = [ tribuchet ];
        networking.firewall.allowedTCPPorts = [ 7437 ];
        virtualisation = {
          writableStore = true;
          memorySize = 2048;
          additionalPaths = [
            pkgs.bash
            pkgs.coreutils
            pkgs.python3
          ];
        };
        nix.settings.substituters = lib.mkForce [ ];
        environment.etc = {
          "tt/slice-hogchild.nix".text = hog {
            name = "hogchild";
            mib = 1792;
            child = true;
          };
          "tt/slice-small.nix".text = hog {
            name = "small";
            mib = 64;
          };
          # 1728 MiB, about 1.35 times A, of pages that compress about 4 to 1
          "tt/slice-comp.nix".text = fill {
            name = "comp";
            what = "hold";
            mode = "comp";
            mib = 1728;
          };
          # (c): runaways
          "tt/slice-growzero.nix".text = fill {
            name = "growzero";
            what = "grow";
            mode = "zero";
          };
          "tt/slice-growrand.nix".text = fill {
            name = "growrand";
            what = "grow";
            mode = "rand";
          };
          # memory no task's size counts: past A and S both
          "tt/slice-shm.nix".text = ''
            import ${./sliceshm.nix} { python3 = "${pkgs.python3}"; bash = "${pkgs.bash}"; coreutils = "${pkgs.coreutils}"; mib = 6144; }
          '';
        };
        imports = [ nixosModule ];
        services.tribuchet-hub = {
          enable = true;
          externalBuilders = {
            enable = true;
            systems = [ "x86_64-linux" ];
          };
          package = tribuchet;
          # Every build on the worker: the hub declines none for as long
          # as the test runs, so Nix never builds one here, where it would
          # take the hub down with it (max-jobs = 0 would stop every
          # build: the external builder takes a local slot).
          settings.worker-grace-secs = 600;
        };
        systemd.sockets.tribuchet-hub.wantedBy = lib.mkForce [ ];
        systemd.services.tribuchet-hub.wantedBy = lib.mkForce [ ];
      };

    worker = {
      imports = [
        (am.node {
          memorySize = 3072;
          inherit reserve;
          maxJobs = 2;
        })
      ];
      virtualisation.useNixStoreImage = true;
      virtualisation.writableStore = true;
      services.tribuchet-worker.agents = 2;
    };

    # its worker never started
    big = {
      imports = [
        (am.node {
          memorySize = 16384;
          inherit reserve;
          cores = 4;
          maxJobs = 2;
        })
      ];
      # zswap_entry and zs_handle in caches of their own, to be counted
      boot.kernelParams = [ "slab_nomerge" ];
      services.tribuchet-worker.agents = 1;
    };
  };

  extraPythonPackages = p: [ (am.checks p) ];

  testScript = builtins.readFile ./slicetest.py + ''
    main(hub, worker, big, start_all, subtest, "${monitor}", "${launch}", "${./slicescale.py}", "${./slicefill.py}", ${toString reserve})
  '';
}

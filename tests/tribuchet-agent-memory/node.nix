# What the agent-memory VM tests share: `node`, a host configured as a
# worker (the slice, zswap, the guard) on Linux 6.18, whose memcg OOM
# killer waits for its victim (Tribuchet's DESIGN.md, Known limitations), with zram
# swap at four times its RAM and the vm sysctls usual with zram; its worker
# starts only when a test starts it. `checks`: checks.py as a
# Python module, for a test's extraPythonPackages.
{
  tribuchet,
  nixosModule,
  pkgs,
  lib,
}:
{
  checks =
    p:
    p.toPythonModule (
      pkgs.writeTextDir "${p.python.sitePackages}/checks.py" (builtins.readFile ./checks.py)
    );
  node =
    {
      memorySize,
      reserve,
      cores ? 2,
      maxJobs ? 1,
    }:
    {
      imports = [ nixosModule ];
      boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_18;
      boot.kernel.sysctl = {
        # a memcg OOM kill must not panic the VM
        "vm.panic_on_oom" = lib.mkForce 0;
        # usual with zram: no watermark boost or swap readahead, swap first
        "vm.watermark_boost_factor" = 0;
        "vm.watermark_scale_factor" = 125;
        "vm.page-cluster" = 0;
        "vm.swappiness" = 190;
      };
      zramSwap = {
        enable = true;
        memoryPercent = 400;
      };
      virtualisation = { inherit memorySize cores; };
      environment.systemPackages = [
        tribuchet
        pkgs.python3
      ];
      services.tribuchet-worker = {
        enable = true;
        package = tribuchet;
        agentMemoryReserve = reserve;
        keyFile = "/etc/tribuchet/tls/worker.key";
        settings = {
          hub = "https://hub:7437";
          cert = "/etc/tribuchet/tls/worker.crt";
          ca-cert = "/etc/tribuchet/tls/ca.crt";
          max-jobs = maxJobs;
        };
      };
      systemd.services.tribuchet-worker.wantedBy = lib.mkForce [ ];
    };
}

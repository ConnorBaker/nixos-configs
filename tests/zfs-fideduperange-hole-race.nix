# A failing-first check for 0006 (f1f96f5e7, "dbuf: restore BP_IS_HOLE()
# recheck after dnode_block_freed()"), which fixes openzfs/zfs#19185 in stock
# 2.4.4: a read races dnode_sync() freeing a block held in the dnode,
# dnode_block_freed() answers "not freed" for what is now a hole, and the
# hole goes to arc_read(), which fails with EINVAL (and suspends the pool
# when the read cannot fail).
#
# The window is microseconds wide, so this follows the reproducer in
# openzfs/zfs#19234: a test-only module parameter, dbuf_read_hole_delay,
# sleeps in dbuf_read_hole() between the first BP_IS_HOLE() and
# dnode_block_freed(). The module is the hosts' patch set plus that patch,
# with or without 0006 (with0006); the hosts never get the delay patch. Two
# test-only counters show that the sleeps ran (dbuf_read_hole_delays) and
# how many reads hit the window (dbuf_read_hole_races: a hole bp and no free
# range after the sleep).
#
# with0006 = false expects the bug: reads fail with EINVAL, and every data
# ereport has #19185's signature on a read that may fail (zio_err 0x16,
# flags CANFAIL and RAW_COMPRESS, level 0, blkid 0). with0006 = true expects
# the window to be hit, every read to return zeros, and no data ereport.
{
  lib,
  pkgs,
  hostConfig,
  with0006,
  # Files per cycle, cycles and reader threads; see
  # zfs-fideduperange-hole-race.py. (Not plain names: callPackage would fill
  # those from pkgs.)
  raceFiles ? 2000,
  raceCycles ? 20,
  raceThreads ? 32,
  # Ticks; #19234 used 1.
  raceDelay ? 1,
}:
let
  hostBoot = hostConfig.boot;
  inherit (import ../packages/zfs-fideduperange { inherit lib; }) withHoleReadDelay;
  modulePackage =
    withHoleReadDelay with0006
      hostBoot.kernelPackages.${pkgs.zfs_unstable.kernelModuleAttribute};
  reproducer = ./zfs-fideduperange-hole-race.py;
in
pkgs.testers.runNixOSTest {
  name = "zfs-fideduperange-hole-race-${if with0006 then "with" else "without"}-0006";
  nodes.machine = {
    boot = {
      inherit (hostBoot) kernelPackages;
      supportedFilesystems = [ "zfs" ];
      zfs = {
        package = hostBoot.zfs.package;
        inherit modulePackage;
        forceImportRoot = false;
      };
      # As on the hosts, so that only the reproducer's zpool sync syncs the
      # frees.
      extraModprobeConfig = "options zfs zfs_txg_timeout=30";
    };
    networking.hostId = "deadbee3";
    virtualisation = {
      cores = 4;
      memorySize = 4096;
      emptyDiskImages = [ 4096 ];
    };
    environment.systemPackages = [ pkgs.python3 ];
  };

  testScript = ''
    import json
    import re

    machine.wait_for_unit("multi-user.target")
    machine.succeed("modprobe zfs")
    module = machine.succeed("cat /sys/module/zfs/version /sys/module/zfs/srcversion; "
                             "readlink -f $(modinfo -n zfs); uname -r").split()
    print("module", module)
    p = "/sys/module/zfs/parameters/dbuf_read_hole_"
    # As in #19234, ashift 12, lz4 and 128K records (#19234 used a file vdev).
    machine.succeed(
        "zpool create -f -o ashift=12 -o failmode=continue -O compression=lz4 "
        "-O recordsize=128K -O mountpoint=none tank /dev/vdb",
        "zfs create -o mountpoint=/race tank/race",
        "zpool events -c",
        f"echo ${toString raceDelay} > {p}delay",
    )
    assert machine.succeed(f"cat {p}delay").strip() == "${toString raceDelay}"
    out = machine.succeed("python3 ${reproducer} ${toString raceFiles} ${toString raceCycles} ${toString raceThreads}")
    result = json.loads(out.strip().splitlines()[-1])
    machine.succeed(f"echo 0 > {p}delay")
    result["delays"] = int(machine.succeed(f"cat {p}delays"))
    result["races"] = int(machine.succeed(f"cat {p}races"))
    result["module"] = module
    result["with0006"] = ${if with0006 then "True" else "False"}
    result["pool"] = machine.succeed("zpool list -H -o health tank").strip()

    # Data ereports: class, and the fields #19185 shows.
    events = machine.succeed("zpool events -v tank")
    blocks = re.split(r"\n(?=\S)", events)
    data = [b for b in blocks if "ereport.fs.zfs.data" in b.splitlines()[0]]
    fields = ("zio_err", "zio_flags", "zio_pipeline", "zio_delay", "zio_level", "zio_blkid",
              "zio_objset", "zio_object")
    sig = []
    for b in data:
        kv = dict(re.findall(r"^\s+(\w+) = (.*)$", b, re.M))
        sig.append({k: kv.get(k) for k in fields})

    # #19185's signature, on a read that may fail: EINVAL, CANFAIL and
    # RAW_COMPRESS only, level 0, blkid 0. Checked on every data ereport.
    def flag_names(s):
        m = re.search(r"\[(.*)\]", s.get("zio_flags") or "")
        return sorted(m.group(1).split()) if m else []

    def matches(s):
        return (s["zio_err"] == "0x16" and flag_names(s) == ["CANFAIL", "RAW_COMPRESS"]
                and s["zio_level"] == "0x0" and s["zio_blkid"] == "0x0")

    kinds: dict[str, int] = {}
    for s in sig:
        key = json.dumps({k: s[k] for k in fields[:6]}, sort_keys=True)
        kinds[key] = kinds.get(key, 0) + 1
    result["data_ereports"] = len(data)
    result["data_ereports_einval"] = sum(s["zio_err"] == "0x16" for s in sig)
    result["data_ereports_signature"] = sum(matches(s) for s in sig)
    result["data_ereports_off_signature"] = [s for s in sig if not matches(s)][:10]
    result["data_ereport_kinds"] = [[json.loads(k), n] for k, n in kinds.items()]
    result["data_ereport_objects"] = len({(s["zio_objset"], s["zio_object"]) for s in sig})
    result["data_ereport_sample"] = sig[:3]
    totals = result["totals"]
    print("HOLE_RACE " + json.dumps(result, sort_keys=True))
    (machine.out_dir / "hole-race.json").write_text(json.dumps(result, indent=1, sort_keys=True))

    reads = ${toString (raceFiles * raceCycles)}
    assert totals.get("reads") == reads, totals
    assert result["delays"] > 0, "the delay never ran"
    assert result["races"] > 0, "no read hit the window; the check would be vacuous"
  ''
  + (
    if with0006 then
      ''
        assert totals.get("zeros") == reads, totals
        assert result["data_ereports"] == 0, result["data_ereport_sample"]
      ''
    else
      ''
        assert totals.get("errno_22", 0) > 0, totals
        assert result["data_ereports"] > 0, totals
        assert result["data_ereports_signature"] == result["data_ereports"], result["data_ereports_off_signature"]
      ''
  );
}

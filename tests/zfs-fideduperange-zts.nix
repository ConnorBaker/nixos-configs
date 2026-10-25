# OpenZFS's own ZFS Test Suite cases, run in a VM against the hosts' ZFS.
#
# nixpkgs has no ZTS runner, and generic.nix deletes share/zfs/zfs-tests at
# install. So this builds a separate userspace that keeps them (the hosts'
# patches plus 0004, the commit's ZTS cases) and runs zfs-tests.sh from it.
# The kernel module and the zfs/zpool/zdb on PATH are the hosts' (patched) or
# stock zfs_unstable, chosen by `patched`, exactly as in zfs-fideduperange.nix.
{
  lib,
  pkgs,
  hostConfig,
  patched,
  # Test names in tests/functional/block_cloning.
  tests,
  suffix,
}:
let
  hostBoot = hostConfig.boot;
  zfsPackage = if patched then hostBoot.zfs.package else pkgs.zfs_unstable;
  zfsModulePackage =
    if patched then
      hostBoot.zfs.modulePackage
    else
      hostBoot.kernelPackages.${pkgs.zfs_unstable.kernelModuleAttribute};

  inherit (import ../packages/zfs-fideduperange { inherit lib; }) withFideduperangeTests;
  removeTests = "rm -rf $out/share/zfs/zfs-tests";
  zts = (withFideduperangeTests pkgs.zfs_unstable).overrideAttrs (old: {
    pname = "zfs-tests";
    postInstall =
      assert lib.hasInfix removeTests old.postInstall;
      lib.replaceStrings [ removeTests ] [ "" ] old.postInstall;
  });

  runfile = pkgs.writeText "fideduperange.run" ''
    [DEFAULT]
    pre = setup
    quiet = False
    pre_user = root
    user = root
    timeout = 120
    post_user = root
    post = cleanup
    failsafe_user = root
    failsafe = callbacks/zfs_failsafe
    tags = ['functional']

    [tests/functional/block_cloning]
    tests = [${lib.concatMapStringsSep ", " (t: "'${t}'") tests}]
    tags = ['functional', 'block_cloning']
  '';

  # Parses zfs-tests.sh output in the VM: the test driver's console transport
  # truncates large outputs, so only this compact JSON crosses it.
  parse = pkgs.writeText "zts-parse.py" ''
    import json, re, sys
    out = open(sys.argv[1]).read()
    res = {}
    for l in out.splitlines():
        # "<time>Test: <path> (run as <user>) <padding>[<runtime>] [<result>]"
        m = re.search(r"Test: \S*/block_cloning/(\S+) \(run as \w+\)\s+\[[0-9:]+\] \[(\w+)\]", l)
        if m:
            res[m.group(1)] = m.group(2)
    tail = out[out.find("Results Summary"):] if "Results Summary" in out else ""
    logdir = re.search(r"^Log directory:\s+(/\S+)", out, re.M)
    print(json.dumps({"results": res, "summary": tail.splitlines()[:12],
                      "logdir": logdir.group(1) if logdir else None}))
  '';
in
pkgs.testers.runNixOSTest {
  name = "zfs-fideduperange-zts-${suffix}-${if patched then "patched" else "stock"}";
  nodes.machine = {
    boot = {
      inherit (hostBoot) kernelPackages;
      supportedFilesystems = [ "zfs" ];
      zfs = {
        package = zfsPackage;
        modulePackage = zfsModulePackage;
        forceImportRoot = false;
      };
    };
    networking.hostId = "deadbee2";
    virtualisation = {
      cores = 2;
      memorySize = 4096;
      diskSize = 8192;
      additionalPaths = [ zts ];
    };
    # zfs-tests.sh refuses root and needs passwordless sudo.
    users.users.zts = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
    security.sudo.wheelNeedsPassword = false;
    # constrain_path() looks only in /usr/local/{bin,sbin}, /usr/{bin,sbin},
    # /bin and /sbin, in that order. /usr/local/bin comes first so it finds
    # the setuid sudo wrapper. zfs-tests.sh calls /sbin/losetup; the tests'
    # shebang is /bin/ksh.
    systemd.tmpfiles.rules = [
      "L+ /usr/local/bin - - - - /run/wrappers/bin"
      "L+ /usr/local/sbin - - - - /run/current-system/sw/bin"
      "L+ /sbin - - - - /run/current-system/sw/bin"
      "L+ /bin/ksh - - - - ${pkgs.ksh}/bin/ksh"
    ];
    environment.systemPackages = with pkgs; [
      acl
      attr
      bc
      bzip2
      cpio
      cryptsetup
      e2fsprogs
      file
      fio
      jq
      ksh
      libcap
      lsscsi
      lvm2
      openssl
      parted
      pax
      python3
      rsync
      sysstat
      xfsprogs
      xxhash
    ];
  };

  testScript = ''
    import json
    from typing import Any

    machine.wait_for_unit("multi-user.target")
    machine.succeed("modprobe zfs")
    info = machine.succeed("cat /sys/module/zfs/version /sys/module/zfs/srcversion; "
                           "readlink -f $(modinfo -n zfs); readlink -f $(command -v zfs); uname -r")
    print(info)
    rc, _ = machine.execute(
        "su - zts -c 'cd /tmp && ${zts}/share/zfs/zfs-tests.sh -v -s 2G -r ${runfile}"
        " > /tmp/zts.out 2>&1'")
    machine.copy_from_machine("/tmp/zts.out", "")
    # The tail only: the console transport truncates large outputs.
    print(machine.succeed("tail -c 3000 /tmp/zts.out"))
    parsed: dict[str, Any] = json.loads(machine.succeed("python3 ${parse} /tmp/zts.out"))
    if parsed["logdir"]:
        machine.succeed(f"tar -C {parsed['logdir']} -czf /tmp/zts-logs.tar.gz .")
        machine.copy_from_machine("/tmp/zts-logs.tar.gz", "")
    results: dict[str, str] = parsed["results"]
    summary: dict[str, Any] = {"exit": rc, "patched": ${if patched then "True" else "False"},
               "module": info.splitlines(), "results": results, "summary": parsed["summary"]}
    print("ZTS " + json.dumps(summary, sort_keys=True))
    (machine.out_dir / "zts.json").write_text(json.dumps(summary, indent=1, sort_keys=True))
    want = ${builtins.toJSON tests}
    missing = [t for t in want if t not in results]
    assert not missing, ("did not run", missing, results)
    ${
      if patched then
        ''
          assert rc == 0, rc
          assert all(results[t] == "PASS" for t in want), results
        ''
      else
        ''
          # Stock 2.4.4 returns EOPNOTSUPP for every FIDEDUPERANGE, which
          # only the feature-disabled case expects.
          assert all(results[t] != "PASS" for t in want if "disabled" not in t), results
        ''
    }
  '';
}

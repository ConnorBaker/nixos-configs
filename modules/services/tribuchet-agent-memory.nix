# The agents' memory (agentMemoryReserve, agentSwapPercent): every
# agent and its builds run in system-tribuchet\x2dagent.slice, capped at
# MemTotal less a reserve and less a per-page bound on the RAM zswap
# holds for the slice outside its charge, and swapping through zswap
# only, which nothing else on the host uses. A guard hands a slice that
# reclaims nothing back to the kernel's OOM killer. Moved here from
# Tribuchet's nix/agent-memory.nix, which flake.nix disables while the
# pinned Tribuchet still has it; tests/tribuchet-agent-memory/ tests it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  worker = config.services.tribuchet-worker;
  reserve = worker.agentMemoryReserve;
  pct = worker.agentSwapPercent;
  swapOn = reserve != null && pct > 0;
  slice = "system-tribuchet\\x2dagent.slice";
  sliceConfig = config.systemd.slices."system-tribuchet\\x2dagent".sliceConfig or { };
  # Bytes of RAM per page zswap stores that the slice's charge leaves
  # out: zswap_entry (56) and zs_handle (8) slabs, xarray nodes and
  # zsmalloc's slack. Measured 66 to 186 (by mechanism, at scale and
  # fragmented); every stored page holds a swap slot, so S / 4096 pages bound
  # their number. Not covered: zsmalloc's fragmentation after scattered
  # frees, which only global reclaim compacts (measured: 657 MB
  # outside the charge against 257 MB allowed, given back under global
  # pressure), and zstd's per-CPU workspaces.
  perPage = 256;
  # S and the cap A in bytes from MemTotal, for the generator and the
  # swap unit alike: S whole MiB, A = MemTotal - reserve - S / 4096 * perPage.
  sizes = ''
    total_kib=
    while read -r key value _; do
      if [ "$key" = MemTotal: ]; then total_kib=$value; fi
    done </proc/meminfo
    [ -n "$total_kib" ] || exit 0
    total=$((total_kib * 1024))
    swap=$((total * ${toString pct} / 100 / 1048576 * 1048576))
    max=$((total - ${toString reserve} - swap / 4096 * ${toString perPage}))
    [ "$max" -gt 0 ] || exit 0
  '';
  # At boot and at every daemon-reload: the slice's cap, no swap until
  # tribuchet-agent-swap has seen zswap on, and MemoryZSwapMax=0 for
  # every other unit (zswap.max is hierarchical: system.slice and the
  # agents' units are let through, the rest of the tree is not). systemd
  # applies drop-ins in the order of their file names, whatever their
  # directory: set-property's 50-<Property>.conf comes after these.
  generator = pkgs.writeShellScript "tribuchet-agent-memory" ''
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    ${sizes}
    d=$1
    mkdir -p "$d/${slice}.d"
    printf '[Slice]\nMemoryMax=%s\nMemorySwapMax=0\n' "$max" >"$d/${slice}.d/40-tribuchet-agent-memory.conf"
    ${lib.optionalString swapOn ''
      printf 'MemoryZSwapWriteback=no\n' >>"$d/${slice}.d/40-tribuchet-agent-memory.conf"
      for t in Service:service Socket:socket Mount:mount Swap:swap Scope:scope Slice:slice; do
        mkdir -p "$d/''${t#*:}.d"
        printf '[%s]\nMemoryZSwapMax=0\n' "''${t%:*}" >"$d/''${t#*:}.d/10-tribuchet-zswap-off.conf"
      done
      for u in Slice:system.slice 'Slice:${slice}' 'Service:tribuchet-agent@.service'; do
        mkdir -p "$d/''${u#*:}.d"
        printf '[%s]\nMemoryZSwapMax=infinity\n' "''${u%:*}" >"$d/''${u#*:}.d/11-tribuchet-zswap-on.conf"
      done
    ''}
  '';
  # zswap on, then the slice's swap: with zswap off the slice would swap
  # into zram, whose RAM no cgroup is charged for (writeback=0 does
  # nothing then). The slice's swap limit has one writer, systemd, which
  # rewrites memory.swap.max whenever it applies the slice's settings, so
  # this module changes it only with `systemctl set-property --runtime`.
  swapStart = pkgs.writeShellScript "tribuchet-agent-swap-start" ''
    set -eu
    ${sizes}
    p=/sys/module/zswap/parameters
    echo zstd >$p/compressor
    echo 100 >$p/max_pool_percent
    echo Y >$p/enabled
    read -r on <$p/enabled
    read -r comp <$p/compressor
    if [ "$on" != Y ] || [ "$comp" != zstd ]; then
      echo "zswap is not on with zstd (enabled $on, compressor $comp): the slice keeps no swap" >&2
      exit 1
    fi
    systemctl set-property --runtime '${slice}' MemorySwapMax="$swap"
    echo "zswap on; the slice may swap $swap bytes through it, capped at $max"
  '';
  # S to 0, the runtime setting gone (so that the next daemon-reload, a
  # switch's, gives the slice what its configuration says), and only then
  # zswap off: S is never in force with zswap off.
  # ExecStopPost, not ExecStop: a stop while the start or a reload runs
  # kills it and skips ExecStop (systemd 261.3 service.c:3544-3555), but
  # not ExecStopPost (2571-2572, 4920-4923), which also follows a start
  # that failed. With ExecStop, S stayed in force after 9 of 800 stops
  # 0-79 ms after a start.
  swapStop = pkgs.writeShellScript "tribuchet-agent-swap-stop" ''
    set -eu
    systemctl set-property --runtime '${slice}' MemorySwapMax=0
    rm -f '/run/systemd/system.control/${slice}.d/50-MemorySwapMax.conf'
    echo N >/sys/module/zswap/parameters/enabled
    echo "the slice may not swap; zswap off"
  '';
  guard = pkgs.writeShellScript "tribuchet-agent-guard" ''
    set -u
    ${sizes}
    slice='${slice}'
    cg=/sys/fs/cgroup/system.slice/$slice
    # Livelocked: at its cap (within 1/64 of it, or a max event) over a
    # whole window of `window` s, the slice reclaimed under `steal` % of
    # `minscan` or more pages scanned, with a task stalled on memory
    # `stall` % of the time, `hold` s running. On a 13 GiB slice a random
    # runaway went 150 s without one firing on max events alone.
    window=10 hold=20 steal=2 stall=50 minscan=2560
    # `settle clamp` puts the slice's swap at what it holds now, and
    # `settle` gives it S (swap). Through systemd, never into
    # memory.swap.max, and asked for whatever memory.swap.max shows: a
    # call that failed may still be applied later. 0: what was asked is
    # in force, and in `asked`; 2: the call failed.
    asked=
    settle() {
      local v=$swap
      if [ "''${1-}" = clamp ]; then
        { read -r v <"$cg/memory.swap.current"; } 2>/dev/null || v=
      fi
      if [ -n "$v" ] && systemctl set-property --runtime "$slice" MemorySwapMax="$v"; then
        asked=$v
        return 0
      fi
      return 2
    }
    event() {
      local k v
      while read -r k v; do
        if [ "$k" = "$2" ]; then echo "$v"; fi
      done <"$cg/$1"
    }
    # microseconds a task in the slice has stalled on memory
    stalled() {
      local kind total s=0
      while read -r kind _ _ _ total; do
        if [ "$kind" = some ]; then s=''${total#total=}; fi
      done <"$cg/memory.pressure"
      echo "$s"
    }
    # what settle's status leaves the slice with, for the log
    left() {
      if [ "$1" = 0 ]; then echo "$2"; else echo "the call for its swap failed; asking again each second"; fi
    }
    # Undo a clamp an earlier instance left: a clamp ends when the guard
    # restarts, or when the swap unit stops, which takes the slice's swap
    # to 0.
    settle
    n=0 run=0
    while sleep 1; do
      # Not clamped, the slice's swap other than S: a clamp systemd applied
      # after its call failed, a failed restore.
      { read -r m <"$cg/memory.swap.max"; } 2>/dev/null || m=
      if [ -z "$m" ]; then
        n=0 run=0
        continue
      fi
      if [ "$m" != "$swap" ]; then
        echo "the slice's swap limit is $m, not $swap: asking for $swap again"
        settle
      fi
      scan=$(event memory.stat pgscan) got=$(event memory.stat pgsteal)
      some=$(stalled)
      read -r cur <"$cg/memory.current" || cur=0
      read -r max <"$cg/memory.max" || max=max
      atcap=0
      if [ "$max" != max ] && [ $((cur + max / 64)) -ge "$max" ]; then atcap=1; fi
      i=$((n % (window + 1)))
      T[i]=''${EPOCHREALTIME/./}
      SC[i]=$scan
      ST[i]=$got
      MX[i]=$(event memory.events.local max)
      SO[i]=$some
      if [ "$n" -ge "$window" ]; then
        j=$(((n - window) % (window + 1)))
        dt=$((T[i] - T[j]))
        dscan=$((SC[i] - SC[j]))
        dgot=$((ST[i] - ST[j]))
        dsome=$((SO[i] - SO[j]))
        if { [ "$atcap" = 1 ] || [ $((MX[i] - MX[j])) -gt 0 ]; } && [ "$dscan" -ge "$minscan" ] &&
          [ $((dgot * 100)) -lt $((dscan * steal)) ] && [ $((dsome * 100)) -ge $((dt * stall)) ]; then
          run=$((run + 1))
        else
          run=0
        fi
      fi
      n=$((n + 1))
      if [ "$run" -ge "$hold" ]; then
        ooms=$(event memory.events.local oom)
        kills=$(event memory.events oom_kill)
        if settle clamp; then
          # the clamp settle asked for, not memory.swap.max read after: a
          # reload of the swap unit in between gives the slice S, which the
          # guard would then wait on as on its clamp
          cur=$asked
          echo "reclaimed $dgot of $dscan pages scanned in $((dt / 1000)) ms, stalled $((dsome * 100 / dt)) %: swap clamped at $cur bytes for the OOM killer"
          # Until the kernel's OOM kill, or 3 s in a row of the slice not
          # stalling: a reclaim pass under way at the clamp runs to its
          # end first.
          waited=0 calm=0 t1=''${EPOCHREALTIME/./} s1=$(stalled)
          while [ "$(event memory.events.local oom)" -le "$ooms" ] && [ "$calm" -lt 3 ]; do
            sleep 1
            waited=$((waited + 1))
            # A reload of tribuchet-agent-swap gives the slice S, clamp or
            # not: nothing to wait for then, and if the slice still reclaims
            # nothing it is clamped again in 30 s.
            { read -r m <"$cg/memory.swap.max"; } 2>/dev/null || m=
            if [ "$m" != "$cur" ]; then
              echo "the slice's swap limit is $m, not the clamp: no longer waiting for an OOM kill"
              break
            fi
            t2=''${EPOCHREALTIME/./} s2=$(stalled)
            if [ $(((s2 - s1) * 100)) -lt $(((t2 - t1) * stall)) ]; then calm=$((calm + 1)); else calm=0; fi
            t1=$t2 s1=$s2
          done
          settle
          back=$(left $? "its swap is back")
          sleep 1
          echo "after $waited s the kernel had OOM-killed $(($(event memory.events oom_kill) - kills)) task(s) in the slice; $back"
        else
          settle
          back=$(left $? "its swap is as before")
          echo "reclaimed $dgot of $dscan pages scanned in $((dt / 1000)) ms: the slice's swap could not be clamped; $back"
        fi
        n=0 run=0
      fi
    done
  '';
  # The slice gets no memory below this (A <= 0).
  floor = reserve * 409600 / (409600 - pct * perPage) + 1;
in
{
  options.services.tribuchet-worker = {
    agentMemoryReserve = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 8 * 1024 * 1024 * 1024;
      defaultText = lib.literalExpression "8 * 1024 * 1024 * 1024";
      description = ''
        Bytes of memory the build agents leave to the rest of the host.
        Every agent and its builds run in `system-tribuchet\x2dagent.slice`;
        at boot and at every daemon-reload a generator sets its MemoryMax
        A to MemTotal less this, and less 256 bytes per page of the
        slice's swap S (`agentSwapPercent`): a bound on what zswap holds
        for those pages outside the slice's charge. It does not cover
        zsmalloc's fragmentation after scattered frees, which zsmalloc
        compacts only under global reclaim (400 MB past it measured in a
        4 GiB VM, given back under global pressure),
        nor zstd's per-CPU workspaces. When builds together reach A,
        the kernel OOM-kills inside the slice: the host, the worker,
        nix-daemon and a hub keep their memory. The worker does not start
        on a host where A would be 0 (AssertMemory). `null`: no cap, no
        swap limit, zswap left as the host boots it (the slice as
        configured elsewhere); a configuration that sets the slice's
        MemoryMax both ways fails to evaluate.
      '';
    };
    agentSwapPercent = lib.mkOption {
      type = lib.types.ints.between 0 400;
      default = 100;
      description = ''
        The slice's swap S, in percent of MemTotal: MemorySwapMax, through
        zswap only. tribuchet-agent-swap turns zswap on (zstd) and only
        then gives the slice S; stopping it, as removing this setting
        does, takes S to 0, removes that runtime setting (so the next
        daemon-reload gives the slice its configured swap) and only then
        turns zswap off. The slice has
        MemoryZSwapWriteback=no, so none of its pages reaches the swap
        device's RAM (zram, charged to no cgroup); every other unit has
        MemoryZSwapMax=0 and swaps to that device as before. Past A,
        pages that compress r to 1 give S (1 - 1/r) of room; zero pages
        take a slot and no RAM; zswap refuses incompressible ones, which
        stay in RAM. At S the kernel OOM-kills inside the slice. Default
        100: host swap has reached 88 % of MemTotal while a build that
        succeeded ran. Pages that do not
        compress never reach an S at or above A; tribuchet-agent-guard
        then clamps the slice's swap at what it holds whenever the slice
        has reclaimed next to nothing for 30 s, so the kernel OOM-kills
        as at S: the largest process by its footprint with swapped pages
        counted at full size, which may be a co-tenant build rather than
        the runaway. A build that thrashes over pages that compress,
        without growing, reaches neither S nor the guard; only its
        timeouts end it (one holding about 0.96 A or more of pages that do
        not compress may trip the guard: a measured trend, not run). 0: no
        swap, no zswap.
      '';
    };
  };

  config = lib.mkIf (worker.enable && reserve != null) (
    lib.mkMerge [
      {
        # The generator's drop-in would override these silently (a
        # host's MemoryMax = "80%"): one of the two
        # has to go.
        assertions =
          map
            (k: {
              assertion = !(sliceConfig ? ${k});
              message = ''
                services.tribuchet-worker.agentMemoryReserve sets ${k} of ${slice} at boot, over
                systemd.slices."system-tribuchet\\x2dagent".sliceConfig.${k}. Set agentMemoryReserve
                to null to keep that, or remove it.
              '';
            })
            (
              [
                "MemoryMax"
                "MemorySwapMax"
              ]
              ++ lib.optionals swapOn [
                "MemoryZSwapWriteback"
                "MemoryZSwapMax"
              ]
            );
        systemd.generators.tribuchet-agent-memory = generator;
        systemd.services.tribuchet-worker.unitConfig.AssertMemory = ">${toString floor}";
      }
      (lib.mkIf swapOn {
        systemd.services = {
          tribuchet-agent-swap = {
            description = "zswap for the tribuchet agents' slice";
            wantedBy = [ "multi-user.target" ];
            wants = [ "tribuchet-agent-guard.service" ];
            before = [ "tribuchet-worker.service" ];
            # a restart would leave the slice without swap for a moment
            reloadIfChanged = true;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = swapStart;
              ExecReload = swapStart;
              ExecStopPost = swapStop;
            };
          };
          tribuchet-agent-guard = {
            description = "OOM kills in the tribuchet agents' slice when it reclaims nothing";
            # Runs only while the swap unit has given the slice S, and stops
            # first: that unit's stop then takes the slice's swap, a clamp
            # included, to 0 and zswap off. The two never set the slice's
            # swap at once but on a reload, which leaves zswap on whichever
            # call lands last.
            bindsTo = [ "tribuchet-agent-swap.service" ];
            after = [ "tribuchet-agent-swap.service" ];
            before = [ "tribuchet-worker.service" ];
            serviceConfig = {
              ExecStart = guard;
              Restart = "always";
              RestartSec = 1;
            };
          };
          tribuchet-worker = {
            # Not Requires=: stopping the swap unit leaves the slice no
            # swap, which the worker can lease builds under.
            wants = [
              "tribuchet-agent-swap.service"
              "tribuchet-agent-guard.service"
            ];
            after = [
              "tribuchet-agent-swap.service"
              "tribuchet-agent-guard.service"
            ];
          };
        };
      })
    ]
  );
}

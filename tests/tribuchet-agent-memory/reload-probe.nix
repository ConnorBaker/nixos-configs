# repeat.nix's reloads at the clamps the guard sets on a
# hog node. At each clamp but the second, systemd reloads its units: the
# clamp must still be in force after (systemd, the one writer, keeps it;
# one written into memory.swap.max directly is undone). At the
# second the swap unit reloads, which gives the slice S, and always
# before the kernel's OOM kill. `held` goes ahead of systemctl on the
# guard's PATH: it freezes the hog's cgroup before it passes a clamp's
# call on (a call for less than the slice's swap limit), so that no OOM
# kill ends the clamp while the reload runs, and reload-watch thaws it
# once the reload is done (the second, once the guard has said that it
# stopped waiting for the kill). Left to the race, the swap reload came
# first in 2 to 5 of 8 runs.
{
  pkgs,
  bin,
  cg,
  slice,
}:
{
  held = pkgs.writeShellScriptBin "systemctl" ''
    cg='${cg}'
    if [ "''${1-}" = set-property ]; then
      v=''${4#MemorySwapMax=} m=
      { read -r m <"$cg/memory.swap.max"; } 2>/dev/null || m=
      if [ "$m" -gt "$v" ] 2>/dev/null; then
        for d in "$cg"/hog*/; do
          [ -e "$d/cgroup.freeze" ] || continue
          echo 1 >"$d/cgroup.freeze"
          k=0
          until ${pkgs.gnugrep}/bin/grep -qx 'frozen 1' "$d/cgroup.events" || [ "$k" -ge 500 ]; do
            ${pkgs.coreutils}/bin/sleep 0.01
            k=$((k + 1))
          done
        done
      fi
    fi
    exec ${pkgs.systemd}/bin/systemctl "$@"
  '';
  # Each clamp's reload, then until S is back, as a JSON line in $1.
  reloadWatch = pkgs.writeShellScript "reload-watch" ''
    set -u
    PATH=${bin}
    out=$1
    cg='${cg}'
    slice='${slice}'
    # S, in force once the guard runs and before any clamp
    until systemctl is-active -q tribuchet-agent-guard && { read -r s <"$cg/memory.swap.max"; } 2>/dev/null; do sleep 0.1; done
    frozen() {
      local d k v f=0
      for d in "$cg"/hog*/; do
        [ -e "$d/cgroup.events" ] || continue
        while read -r k v; do if [ "$k" = frozen ] && [ "$v" = 1 ]; then f=1; fi; done <"$d/cgroup.events"
      done
      echo "$f"
    }
    said() { journalctl -b -u tribuchet-agent-guard -o cat | grep -c 'no longer waiting' || true; }
    n=0
    while ! [ -e "$out.stop" ]; do
      { read -r m <"$cg/memory.swap.max"; } 2>/dev/null || m=
      if [ -n "$m" ] && [ "$m" != "$s" ]; then
        n=$((n + 1))
        t0=$(cut -d' ' -f1 /proc/uptime)
        rc=0 held=$(frozen) ended=0
        read -r c <"$cg/memory.swap.max"
        if [ "$n" != 2 ]; then
          kind=daemon-reload
          systemctl daemon-reload || rc=$?
        else
          kind=swap-reload
          w=$(said)
          systemctl reload tribuchet-agent-swap || rc=$?
        fi
        read -r a <"$cg/memory.swap.max"
        p=$(systemctl show -P MemorySwapMax "$slice")
        if [ "$kind" = swap-reload ]; then
          k=0
          while [ "$(said)" = "$w" ] && [ "$k" -lt 100 ]; do
            sleep 0.1
            k=$((k + 1))
          done
          if [ "$(said)" != "$w" ]; then ended=1; fi
        fi
        for d in "$cg"/hog*/; do if [ -e "$d/cgroup.freeze" ]; then echo 0 >"$d/cgroup.freeze"; fi; done
        t1=$(cut -d' ' -f1 /proc/uptime)
        k=0
        while { read -r m <"$cg/memory.swap.max"; } 2>/dev/null && [ "$m" != "$s" ] && [ "$k" -lt 1200 ]; do
          sleep 0.05
          k=$((k + 1))
        done
        t2=$(cut -d' ' -f1 /proc/uptime)
        printf '{"kind": "%s", "rc": %d, "held": %d, "ended": %d, "t0": %s, "t1": %s, "t2": %s, "clamp": "%s", "after_reload": "%s", "systemd": "%s", "then": "%s"}\n' \
          "$kind" "$rc" "$held" "$ended" "$t0" "$t1" "$t2" "$c" "$a" "$p" "$m" >>"$out"
      fi
      sleep 0.02
    done
  '';
}

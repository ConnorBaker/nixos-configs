#!/usr/bin/env bash
# tribuchet-agent-guard (tribuchet-agent-memory.nix) against a stand-in systemd and
# cgroup, each case from a fresh state: the guard script as built, with
# only its cgroup and /proc/meminfo (whose MemTotal gives S) pointed into
# a scratch directory, and the stand-ins first on PATH.
#   systemctl  set-property applies MemorySwapMax=v to memory.swap.max
#              before it returns, as PID 1 does for a slice; a marker
#              makes one call for v slow (slow-v), fail and apply 0.5 s
#              later (late-v), or fail (fail-v; failafter-v holding u:
#              the first call for v once u was applied). With
#              reload-after-v, a reload of the swap unit gives the slice S
#              the moment the call for v has been applied.
#   sleep      `sleep 1` takes 20 ms, is counted in sleeps, and advances
#              the kernel stand-in:
#              while livelocked, the slice scans 10000 pages a poll and
#              reclaims none, stalled all the time, at its cap; once
#              memory.swap.max is below S the OOM killer kills one task
#              and the livelock ends (unless no-oom)
# usage: agent-memory-guard-test.sh GUARD-SCRIPT
set -euo pipefail
guard=$1
S=3049259008
C=1248862208
work=$(mktemp -d)
realsleep=$(command -v sleep)
failed=0

put() { printf '%s\n' "$2" >"$1.tmp" && mv "$1.tmp" "$1"; }

setup() {
  T=$work/$1
  mkdir -p "$T/cg" "$T/bin"
  put "$T/cg/memory.swap.max" "$S"
  put "$T/cg/memory.swap.current" "$C"
  put "$T/cg/memory.max" 1000001536
  put "$T/cg/memory.current" 1000001536
  put "$T/cg/memory.stat" "$(printf 'pgscan 0\npgsteal 0')"
  put "$T/cg/memory.pressure" "$(printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0')"
  put "$T/cg/memory.events.local" "$(printf 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0')"
  put "$T/cg/memory.events" "$(printf 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0')"
  # S is MemTotal in whole MiB
  put "$T/meminfo" "MemTotal:       $((S / 1024)) kB"
  : >"$T/calls"
  : >"$T/sleeps"
  touch "$T/livelock"
  cat >"$T/bin/systemctl" <<EOF
#!$BASH
put() { printf '%s\n' "\$2" >"\$1.tmp.\$\$" && mv "\$1.tmp.\$\$" "\$1"; }
v=\${4#MemorySwapMax=}
echo "start \$v" >>$T/calls
if [ -e $T/late-\$v ]; then
  rm $T/late-\$v
  ( $realsleep 0.5; put $T/cg/memory.swap.max "\$v"; echo "late-applied \$v" >>$T/calls ) &
  echo "Failed to set unit properties: Connection timed out" >&2
  exit 1
fi
if [ -e $T/failafter-\$v ] && grep -qx "applied \$(cat $T/failafter-\$v)" $T/calls; then
  mv $T/failafter-\$v $T/fail-\$v
fi
if [ -e $T/fail-\$v ]; then
  rm $T/fail-\$v
  echo "failed \$v" >>$T/calls
  echo "Failed to set unit properties: Connection timed out" >&2
  exit 1
fi
if [ -e $T/slow-\$v ]; then rm $T/slow-\$v; $realsleep 1; else $realsleep 0.01; fi
put $T/cg/memory.swap.max "\$v"
echo "applied \$v" >>$T/calls
if [ -e $T/reload-after-\$v ]; then
  rm $T/reload-after-\$v
  put $T/cg/memory.swap.max $S
  echo "reload $S" >>$T/calls
fi
EOF
  cat >"$T/bin/sleep" <<EOF
#!$BASH
if [ "\$*" != 1 ]; then exec $realsleep "\$@"; fi
echo >>$T/sleeps
$realsleep 0.02
put() { printf '%s\n' "\$2" >"\$1.tmp" && mv "\$1.tmp" "\$1"; }
[ -e $T/livelock ] || exit 0
read -r m <$T/cg/memory.swap.max
if [ "\$m" != $S ] && ! [ -e $T/no-oom ]; then
  put $T/cg/memory.events.local "\$(printf 'low 0\nhigh 0\nmax 0\noom 1\noom_kill 1')"
  put $T/cg/memory.events "\$(printf 'low 0\nhigh 0\nmax 0\noom 1\noom_kill 1')"
  rm $T/livelock
  exit 0
fi
read -r _ scan <$T/cg/memory.stat
put $T/cg/memory.stat "\$(printf 'pgscan %d\npgsteal 0' \$((scan + 10000)))"
now=\${EPOCHREALTIME/./}
read -r t0 <$T/t0
put $T/cg/memory.pressure "\$(printf 'some avg10=99.00 avg60=99.00 avg300=99.00 total=%d\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0' \$((now - t0)))"
EOF
  chmod +x "$T/bin/systemctl" "$T/bin/sleep"
  echo "${EPOCHREALTIME/./}" >"$T/t0"
  # the guard as built, pointed at the stand-ins: each line it changes
  # occurs exactly once, and no path into /sys, /run or /proc is left
  local re n
  # shellcheck disable=SC2016 # \$slice is the script's own text
  for re in '^cg=/sys/fs/cgroup/system\.slice/\$slice$' '^done </proc/meminfo$'; do
    n=$(grep -c -- "$re" "$guard" || true)
    if [ "$n" != 1 ]; then
      echo "the guard script has $n lines matching $re, not 1" >&2
      exit 1
    fi
  done
  sed -e "s|^cg=/sys/fs/cgroup/system\.slice/\$slice\$|cg=$T/cg|" \
    -e "s|^done </proc/meminfo\$|done <$T/meminfo|" \
    "$guard" >"$T/guard"
  if grep -n '/sys/\|/run/\|/proc/' "$T/guard" >&2; then
    echo "the guard script still names a path into /sys, /run or /proc" >&2
    exit 1
  fi
}

# the stand-ins first, then this script's PATH (the same coreutils as the
# unit's)
start() {
  PATH=$T/bin:$PATH bash "$T/guard" >"$T/out" 2>&1 &
  pid=$!
}

# until $T/$1 has ${3:-1} lines that are $2 whole (a grep regex), or fail
# after 10 s: calls, out (the guard's lines: .*TEXT.*), sleeps (one empty
# line a sleep 1) or cg/memory.swap.max
poll() {
  for _ in $(seq 500); do
    if [ "$(grep -cx -- "$2" "$T/$1")" -ge "${3:-1}" ]; then return 0; fi
    "$realsleep" 0.02
  done
  return 1
}

said() { grep -q -- "$1" "$T/out"; }

# TERM to the guard, which ends it at once: memory.swap.max then in m
term() {
  termed=1
  kill -TERM "$pid"
  wait "$pid" || true
  read -r m <"$T/cg/memory.swap.max"
}

# what systemd applied from the line $1 in calls on
applied_from() { sed -n "/^$1\$/,\$p" "$T/calls" | grep '^applied' | tr '\n' ' '; }

verdict() {
  local text=$1 ok=$2
  shift 2
  if [ "$ok" = 1 ]; then
    echo "AGENT-MEMORY-GUARD ok: $text"
  else
    echo "AGENT-MEMORY-GUARD FAILED: $text"
    failed=1
  fi
  echo "  $*"
  echo "  calls: $(tr '\n' ';' <"$T/calls")"
  echo "  guard: $(tr '\n' ';' <"$T/out")"
}

# A case: case_start NAME [FILE[=CONTENT]...] starts the guard from a
# fresh state with those markers in $T; the case then waits for its
# moment, acts, calls term and judges, ok=1 if all of it holds; case_end
# TEXT TERMs the guard if the case did not, and gives the verdict.
case_start() {
  local marker
  setup "$1"
  shift
  for marker; do printf '%s\n' "${marker#*=}" >"$T/${marker%%=*}"; done
  ok=0 termed=0 m='' order=''
  start
}

case_end() {
  if [ "$termed" = 0 ]; then term; fi
  verdict "$1" "$ok" "memory.swap.max $m${order:+, applied in order: $order}"
}

# livelock, clamp at C, the OOM kill, S again
case_start c0
if poll calls "applied $C" && poll calls "applied $S" && "$realsleep" 0.2 &&
  [ "$(cat "$T/cg/memory.swap.max")" = "$S" ] && said "swap clamped at $C bytes" && said "its swap is back" &&
  term && [ "$m" = "$S" ]; then ok=1; fi
case_end "clamped at C for the OOM kill, then S again"

# A clamp ends when the guard restarts (or the swap unit stops, which
# takes the slice's swap to 0): a TERM leaves it, and the next guard's
# first call is for S
case_start c1 no-oom
if poll calls "applied $C" && "$realsleep" 0.2 && term && [ "$m" = "$C" ] &&
  start && poll calls "applied $S" && poll cg/memory.swap.max "$S"; then ok=1; fi
termed=0
case_end "a clamp a TERM left: the restarted guard gives S first"

# a reload of tribuchet-agent-swap during a clamp, before any OOM kill
# (its start gives the slice S): the guard stops waiting for one and, the
# slice still reclaiming nothing, clamps again
case_start reload no-oom
if poll calls "applied $C" && poll out ".*swap clamped at $C.*" &&
  "$T/bin/systemctl" set-property --runtime x MemorySwapMax="$S" &&
  poll out ".*no longer waiting.*" && poll calls "applied $C" 2; then ok=1; fi
case_end "a reload of the swap unit during a clamp: the guard stops waiting and clamps again"

# the same reload the moment the clamp's call has been applied, before
# the guard has looked at what is in force: the guard must wait on the C
# it asked for, not on the S it would read, and so stop waiting at once,
# after its first second (a guard that went on waiting passed every
# case before this one)
case_start rg "reload-after-$C"
if poll calls "reload $S" && poll out ".*no longer waiting.*" && poll calls "applied $C" 2 &&
  said "swap clamped at $C bytes" && said "after 1 s the kernel"; then ok=1; fi
case_end "a reload of the swap unit as the clamp's call returns: it waits on C, not S"

# the restore's call fails (systemd re-executing, say): the guard must
# not say the slice has its swap back, and asks again
case_start fr "failafter-$S=$C"
if poll calls "failed $S" && poll out ".*asking for $S again.*" && poll cg/memory.swap.max "$S" &&
  said "the call for its swap failed" && ! said "its swap is back" &&
  term && [ "$m" = "$S" ]; then ok=1; fi
case_end "the restore's call fails once: S asked for again, and not reported back before"

# the clamp's call fails, and systemd applies it later (the kernel then
# OOM-kills as for any clamp, and the livelock ends)
case_start late "late-$C"
if poll calls "late-applied $C" && poll cg/memory.swap.max "$S" &&
  said "could not be clamped" && said "swap limit is $C, not $S"; then ok=1; fi
case_end "a clamp applied after its call failed: S again"

# a clamp that brings no OOM kill, the slice still stalled (still freeing
# a few pages a pass, as try_charge_memcg retries on): the clamp lasts
# until an OOM kill, a reload or 3 calm seconds, so 40 polls on it is
# still the one call for C, and still in force
case_start bd no-oom
if poll calls "applied $C" && poll sleeps '' $(($(wc -l <"$T/sleeps") + 40)) &&
  [ "$(applied_from "applied $C")" = "applied $C " ] && term && [ "$m" = "$C" ]; then ok=1; fi
case_end "a clamp with no OOM kill lasts while the slice stalls"

rm -rf "$work"
exit "$failed"

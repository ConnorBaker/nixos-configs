# memcg OOM scans and exiting OOM victims

`0001-mm-memcontrol-let-memcg-OOM-scans-see-exiting-OOM-vi.patch` makes
`mem_cgroup_scan_tasks()` pass `CSS_TASK_ITER_WITH_DEAD` along with
`CSS_TASK_ITER_PROCS`. The memcg OOM scan then shows tasks as it did before
`a72f73c4dd9b`. When the victim's own exit drops the last reference to its mm,
as for a single-threaded victim, the scan still sees the victim while it exits,
and aborts on it as `oom_evaluate_task()` intends, instead of killing a second
task while the victim's memory is being freed. A victim can still be missed when
another thread or process drops that reference, as on 6.18; see
[Where the window stays open](#where-the-window-stays-open).

`modules/zfs.nix` applies it, through `boot.kernelPatches`, to `brev-worker`,
`nixos-build01`, `nixos-desktop` and `nixos-ext`: every host that takes
`linuxKernel.packages.linux_7_2` there, which is everything but `nixos-orin`.

Line numbers below are at v7.2.12 (`cc9de5d4b5ab`), the hosts' kernel, unless
another version is named.

## The problem

- `d245698d727a` ("cgroup: Defer task cgroup unlink until after the task is
  done switching out") left an exited task on its css_set until its final
  context switch: `finish_task_switch()` calls `cgroup_task_dead()`
  (`kernel/sched/core.c:5419-5429`), after `exit_notify()` has made the task
  reapable. `9311e6c29b34` moved that work to irq_work on PREEMPT_RT.
- `a72f73c4dd9b` ("cgroup: Don't expose dead tasks in cgroup", v7.0, and 6.19.9
  in stable; `Fixes: 9311e6c29b34`) fixed what systemd saw, `waitpid()`
  returning a pid still listed in `cgroup.procs`, by making
  `css_task_iter_advance()` skip every task with `PF_EXITING` whose
  `signal->live` is 0 (`kernel/cgroup/cgroup.c:5153-5155`).
- `60f21a264930` ("cgroup, sched_ext: Include exiting tasks in cgroup iter",
  v7.1) added `CSS_TASK_ITER_WITH_DEAD` to opt out, for sched_ext.
  `mem_cgroup_scan_tasks()` still passes only `CSS_TASK_ITER_PROCS`
  (`mm/memcontrol.c:1374`; mainline `8a36f53fd5ec`, 2026-10-27: 1454).
- In `do_exit()`, a single-threaded victim sets `PF_EXITING`
  (`kernel/exit.c:929`) and drops `signal->live` (934) before `exit_mm()`
  (975); `exit_mmap()` sets `MMF_OOM_SKIP` on the mm (`mm/mmap.c:1307`). From
  934 on, the memcg scan no longer returns the victim.
- `oom_evaluate_task()` aborts the scan on an OOM victim whose mm is not yet
  `MMF_OOM_SKIP` (`mm/oom_kill.c:324-328`). That abort is what stops a charge
  that reaches the OOM killer meanwhile from killing a second task. With the
  victim hidden, `select_bad_process()` picks another one.

## sashiko-bot's review, and Zhan Xusheng's v2

Zhan Xusheng's "[PATCH] mm: memcontrol: don't miss processes whose leader has
exited in OOM scans" (2026-10-26,
`<20261026120248.2188024-1-zhanxusheng1024@gmail.com>`) walks all threads
(flags 0) and lets one task stand for each thread group. sashiko-bot's AI
review of it (2026-10-27, `<sashiko-outbox-186496@kernel.org>`), in its finding
"mem_cgroup_scan_skip() skips exiting OOM victims", described this mechanism:
with exiting tasks skipped, and `css_task_iter_start()` called without
`CSS_TASK_ITER_WITH_DEAD`, a concurrent memcg OOM scan misses the victim before
`exit_mmap()` sets `MMF_OOM_SKIP` and kills another process. It raised this as
a regression of v1. Unpatched kernels already do it through the PROCS path.

v2 (2026-10-27, `<20261027144016.2582880-1-zhanxusheng1024@gmail.com>`) says
it keeps exiting threads visible "so a concurrent scan still finds an OOM victim
and aborts", but it still calls `css_task_iter_start(&iter->css, 0, &it)`
(line 1455 on its base, `d135ab453a74`). Without `CSS_TASK_ITER_WITH_DEAD` the
iterator drops every thread of a group whose `signal->live` is 0 (5153-5155),
and without `CSS_TASK_ITER_PROCS` it drops all of `dying_tasks` (5166-5169),
before v2's `mem_cgroup_scan_skip()` sees them. v2's exiting stand-in can only
be seen between the group's last `exit_signals()` and its last `signal->live`
decrement (`kernel/exit.c:929-934`), so v2 does not fix this. With
`CSS_TASK_ITER_WITH_DEAD` added, its helper would see the exiting threads it is
written for. In the lore archives as fetched at 2026-10-28T02:42Z, v1 has
sashiko-bot's review, Tao Cui's Reviewed-by and Tested-by (which v2 does not
carry), and Zhan's selftest patch; v2 has no replies.

## What `CSS_TASK_ITER_PROCS | CSS_TASK_ITER_WITH_DEAD` shows

With `CSS_TASK_ITER_WITH_DEAD` the check at 5153-5155 does not apply, and
`css_task_iter_advance()` filters as it did before `a72f73c4dd9b`, whose diff
only inserted that check:

- `CSS_TASK_ITER_PROCS` skips threads that are not group leaders (5159-5160),
  and leaders on `dying_tasks` whose `signal->live` is 0 (5162-5165).
- `do_cgroup_task_dead()` unlinks a task at its final context switch and puts it
  on `dying_tasks` only if it is a leader with live threads (7102-7104). A
  leader whose whole group has exited is never there: it stays on its css_set's
  task list, and the scan returns it, from `exit_notify()`
  (`kernel/exit.c:999`) until its final switch, as before `a72f73c4dd9b`.
- So the patched 7.2.12 matches 7.0-rc before `a72f73c4dd9b`, not 6.18: 6.18.y
  unlinks in `cgroup_exit()`, from `do_exit()` before `exit_notify()`
  (v6.18.59 `kernel/exit.c:986` and `994`; `kernel/cgroup/cgroup.c:7021`).
- Unrelated to the hide, 7.2.12's `css_task_iter_next()` skips a task whose
  refcount has reached zero (`kernel/cgroup/cgroup.c:5234-5237`); v6.18.59 and
  v6.19.14 take a reference unconditionally.

The scan's three callers (`mm/oom_kill.c:367`, `428`, `1050`) handle exiting
tasks:

- `oom_evaluate_task()`: an OOM victim aborts the scan until its mm is
  `MMF_OOM_SKIP`, then is passed over (324-328). Any other task goes to
  `oom_badness()`, which returns `LONG_MIN` when `find_lock_task_mm()` finds
  no thread with an mm (207-209), so it is passed over (340-341).
- If an exiting task that still has an mm is chosen, `oom_kill_process()` lets
  it exit through `task_will_free_mem()` and kills nothing (1020-1027).
- `dump_task()` skips a task with no mm (391-397).
- `memory.oom.group`: `oom_kill_memcg_member()` (998-1006) calls
  `__oom_kill_process()` on each member it is given:
  - A member with no mm left, such as a dead zombie leader, is not killed again:
    `__oom_kill_process()` logs "OOM victim ... is already exiting. Skip killing
    the task" and returns (918-923).
  - A member that is exiting but still holds its mm, between its
    `signal->live` decrement (`kernel/exit.c:934`) and `exit_mm()` clearing
    `->mm` (586), is now walked too. It is sent `SIGKILL` again, counted in
    `OOM_KILL` and the memcg's `oom_kill` event (`mm/oom_kill.c:935-936`),
    marked as an OOM victim by `mark_oom_victim()` (944), logged as "Killed
    process" (945), and queued for the OOM reaper by `queue_oom_reaper()`
    (987-988).
  - The marking and the reaper are harmless: the member clears `TIF_MEMDIE`
    again as it leaves `exit_mm()` (`kernel/exit.c:594-595`), and the reaper
    only frees early an mm that is already being torn down. What the member
    adds is inflated `oom_kill` counts and log lines; 6.18 and 6.19.0-6.19.8
    did the same.

## Where the window stays open

The patch restores the pre-`a72f73c4dd9b` scan. That closes the window when the
victim's own exit drops the last reference to its mm, the single-threaded case
the evidence below tests. As on 6.18, it stays open when another task drops
that reference after the victim has left the scan:

- `MMF_OOM_SKIP` is set in `exit_mmap()` (`mm/mmap.c:1307`), which the last
  `mmput()` runs (`kernel/fork.c:1208` and `1186`). `exit_mm()` calls
  `mmput()` for each exiting thread (`kernel/exit.c:593`).
- **Multi-threaded victims.** `CSS_TASK_ITER_PROCS` returns only thread-group
  leaders (5159-5160), so the scan sees a victim only through its leader.
  - If the leader makes its final context switch while other threads still
    live, `do_cgroup_task_dead()` moves it to `dying_tasks` (7102-7104). The
    PROCS branch then hides it from the group's last `signal->live` decrement
    (`kernel/exit.c:934`) on (5162-5165), and `CSS_TASK_ITER_WITH_DEAD` does
    not change that branch.
  - If no thread is live at the leader's final switch, `do_cgroup_task_dead()`
    unlinks the leader (7100), and it disappears at that switch, which can come
    after the last decrement. The victim is then hidden early only if that
    switch comes before the last `mmput()` has run `exit_mmap()`.
  - In either case, while the leader is hidden and a non-leader has yet to do
    the last `mmput()`, the victim stays hidden until `exit_mmap()` sets
    `MMF_OOM_SKIP`, and a charge meanwhile can still kill a second task.
- **Other holders of the mm.** A `/proc` reader (`get_task_mm()`,
  `fs/proc/array.c:441` and `494`), or a process sharing the mm through
  `CLONE_VM`, can hold a reference past the victim's final switch, which
  unlinks the victim. The victim is then hidden until that holder's `mmput()`
  runs `exit_mmap()`, or until the OOM reaper sets `MMF_OOM_SKIP`
  (`mm/oom_kill.c:628`), at the earliest 2 s after the kill (685).

Neither is a regression: 6.18 has the same gaps. Its `cgroup_exit()`, run from
each task's own `do_exit()` after `exit_mm()` (v6.18.59 `kernel/exit.c:970`
and `986`), parks a leader on `dying_tasks` or unlinks it by the same test
(v6.18.59 `kernel/cgroup/cgroup.c:7021-7025`), and its PROCS branch hides a
parked leader the same way (5149-5152). Closing the multi-threaded gap would
need a walk over all threads, with `CSS_TASK_ITER_WITH_DEAD`, that counts each
thread group once. These cases come from reading the source; no test here
exercises them.

## Affected kernels

- 7.x: yes. `a72f73c4dd9b` is in v7.0. Mainline `8a36f53fd5ec` still hides
  exiting tasks (`kernel/cgroup/cgroup.c:5242-5244`) and scans with
  `CSS_TASK_ITER_PROCS` only (`mm/memcontrol.c:1454`). The patch needs
  `CSS_TASK_ITER_WITH_DEAD`, which is in v7.1 and later; on 7.0.y it would need
  that flag from `60f21a264930` as well.
- 6.19.y: yes. `a72f73c4dd9b` came in 6.19.9; v6.19.14 hides exiting tasks
  (`kernel/cgroup/cgroup.c:5117`) and has no `CSS_TASK_ITER_WITH_DEAD`, so this
  patch alone does not build there.
- 6.18.y, 6.12.y, 6.6.y: no. v6.18.59, v6.12.114 and v6.6.160 have neither the
  hide nor the deferred unlink: `css_task_iter_advance()` goes straight to the
  PROCS check (v6.18.59 `kernel/cgroup/cgroup.c:5144`, v6.12.114 5027,
  v6.6.160 4919).
- `nixos-orin` runs L4T's 5.15 and does not get the patch. `a72f73c4dd9b` is
  marked for stable 6.19 and later; L4T's source was not inspected.

## Evidence

Both tests below are NixOS VM tests made from Tribuchet's agent-memory repeat
test: `nix/agent-memory-repeat-test.nix`, `nix/oom-probes.bt` and
`nix/agent-memory-oom-trace.py` at Tribuchet commits `6496516` and `4ad5351`.
Those two commits are unpushed: they exist only in local candidate refs
(`refs/archive/2026-10-27/candidate/tribuchet-memory-guard*`) of one Tribuchet
clone, not on any public branch. The cut-down harness used for the patched run
is not committed anywhere either. The setup below is what the tests did, in
enough detail to build an equivalent test without them.

### Setup

- **VMs:** NixOS from Tribuchet's nixpkgs; 3 GiB of memory, 2 vCPUs, zram swap
  at 400 % of memory; `vm.swappiness` 190, `vm.page-cluster` 0,
  `vm.watermark_boost_factor` 0 and `vm.watermark_scale_factor` 125, as on
  `nixos-ext`; `vm.panic_on_oom` 0. Each runs Tribuchet's worker module (its
  agent slice, zswap and swap guard) with `agentMemoryReserve` 1536 MiB, and
  does not start the worker itself.
- **Hog case**, runs one after another on each hog VM (10 in the patched run, 5
  in B1):
  - A loop unit in the agent slice, at `OOMScoreAdjust=-1000`, makes a new
    cgroup `hog<i>` under the slice for each run.
  - In it, a shell at OOM score 0 runs
    `tr -d '\n' </dev/urandom | head -c 1792M | tail -n 1` under a 150 s
    `timeout`, until the guard clamps the slice's swap and the kernel OOM-kills
    the pipeline. The shell then prints the pipeline's exit status and exits 0.
  - The loop waits for the cgroup to empty, reads `oom_kill` from the
    `memory.events` of the cgroup and of the slice, removes the cgroup, and
    waits 2 s.
  - A run passes if the shell exits 0 after printing status 137, and both
    counts are 1.
  - As in Tribuchet's test, a watcher runs `systemctl daemon-reload` under the
    guard's lock at each clamp.
- **Second-allocator case**, run after run for a fixed time on one VM:
  - A new cgroup `kx<i>` for each run, at the root of the hierarchy, with
    `memory.max` 768M, `memory.swap.max` 256M and `memory.zswap.writeback` 0,
    so that zswap's rejects stay in swap cache.
  - In that same cgroup, both at OOM score 0: a loop of
    `dd if=/dev/zero of=/dev/null bs=8M count=4`, and the same pipeline under a
    60 s `timeout`.
  - Then `cgroup.kill`, a wait for the cgroup to empty, and its `oom_kill`
    count from `memory.events`. A run passes if that count is 1.
- **Probes:** bpftrace on every VM, attached before either case starts, traces
  `out_of_memory()`, `oom_evaluate_task()`, `__oom_kill_process()`, and each
  victim's `do_exit()` and `exit_mmap()`.
- **Over-kill scans:** a scan that, after a kill, passes the victim's place in
  the task list before the victim's `exit_mmap()` returns, does not evaluate
  the victim, and selects another task. `MMF_OOM_SKIP` is set partway through
  `exit_mmap()`, but every patched scan in that stretch evaluated the victim
  and aborted. `agent-memory-oom-trace.py` counts (victim, scan) pairs, so a
  scan placed after two victims counts twice; the scan counts below count each
  scan once.

### Patched against unpatched 7.2.12

Run on 2026-10-28 with Tribuchet `6496516`'s files, cut to the two cases:

- **Kernels:** this repository's `linux_7_2` package set as `nixos-ext`
  evaluates it, with this directory's patch and without it (at `f7f0e9a`, the
  commit before the patch was added), plus Tribuchet's own `linux_7_2`
  (7.2.9). The two 7.2.12 kernels have byte-identical `.config` files; their
  derivations differ only by the patch.
- **Layout:** for each 7.2.12 kernel, two hog VMs and one second-allocator VM
  running for 300 s; for 7.2.9, one second-allocator VM. All seven VMs ran at
  once.

Runs with two or more OOM kills:

| Case | Patched 7.2.12 | Unpatched 7.2.12 | 7.2.9 |
| --- | --- | --- | --- |
| Hog | 0 of 20 | 4 of 20 | not run |
| Second allocator | 0 of 86 | 29 of 90 | 34 of 78 |
| Over-kill scans, all runs | 0 | 36 | 35 |

- **Patched kernel:** every hog shell survived, and every run had exactly one
  kill. Its scans evaluated an exiting victim (`PF_EXITING` set,
  `signal->live` 0) 57 times, and aborted every time, as 6.18.55 does below.

- **Unpatched 7.2.12:** `agent-memory-oom-trace.py` reports 37 (victim, scan)
  pairs; one scan on a hog VM is placed after two victims, so there are 36
  over-kill scans. They killed 34 more tasks; the other 2 picked a task that
  was already exiting. Unpatched scans evaluated an exiting victim with
  `signal->live` 0 only 3 times on each kernel, consistent with
  `signal->live` dropping between the iterator's check and the evaluation.

- **Significance:** each arm pools runs from few VMs, two per kernel for the
  hog case and one for the second allocator, so its runs are not independent
  replicates. One-sided tests, patched against unpatched 7.2.12:

  - second allocator: Fisher exact p = 2.6e-10;
  - hog: Fisher exact p = 0.053, Boschloo p = 0.030, and an exact test
    stratified by VM pair p = 0.053.

  Fisher's and Boschloo's tests both treat the runs as independent. The
  VM-stratified test addresses differences between VMs, not dependence between
  runs within a VM. The trace evidence is the stronger result: 0 over-kill
  scans patched against 36 unpatched, and 57 aborts on an exiting victim
  against 3.

### Before the patch: 7.2.9 against 6.18.55

Tribuchet's test at `4ad5351` (build B1, 2026-10-28) ran both cases with the
setup above on 7.2.9 and 6.18.55, beside its other cases: 5 hog runs on each of
two VMs per kernel, and a 150 s second-allocator loop on one VM per kernel.

- Hog runs with two kills: 7.2.9 3 of 10, 6.18.55 0 of 10.
- Second-allocator runs with two kills: 7.2.9 6 of 29, 6.18.55 0 of 39.
- Traces, summarised with Tribuchet `6496516`'s `agent-memory-oom-trace.py`:
  - On 7.2.9, 11 scans passed the victim's place in the task list after its
    `do_exit()`, 7 of them during its `exit_mmap()`. None evaluated the victim.
    Each selected another task, which was killed in 9 cases and already exiting
    in 2.
  - On 6.18.55, all 17 such scans evaluated the victim, with `PF_EXITING` set
    and `signal->live` 0, and aborted.

## Deploying

- **Tested:** the patched kernel has booted in the VM test above and in this
  flake's 33 `zfs-fideduperange` checks, which use `nixos-ext`'s kernel package
  set; all passed. No host has booted it.
- **Before switching:** build the four host toplevels. What is still unbuilt
  changes as other builds land; to see it for a host, run
  `nix build --dry-run .#nixosConfigurations.<host>.config.system.build.toplevel`.
- **Rollback:** keep the previous generation selectable.
  - `nixos-ext` and `nixos-desktop` are remote, with no KVM access, and boot
    with systemd-boot. Neither enables
    `boot.loader.systemd-boot.bootCounting`. The default entry is the
    generation last installed by `nixos-rebuild switch` or `boot`, unless an
    EFI default set earlier (`bootctl set-default`, or `d` in the boot menu)
    overrides it. So a boot that fails and reboots comes back on the same
    kernel, and picking an older entry takes the boot menu (5 s timeout) and a
    console.
  - Stage 1 never reboots by itself on these two hosts, unless the firmware has
    a watchdog of its own; nobody has checked for one. The initrd applies no
    `kernel.panic`, the kernel's `CONFIG_PANIC_TIMEOUT` is 0, and the command
    line has no `panic=`, so a panic there halts the host. The initrd has no
    watchdog, and `boot.initrd.systemd.emergencyAccess` is off, so a hang there,
    such as a root pool that fails to import, stays hung.
  - From stage 2 on, `kernel.panic = 10` (`modules/watchdog.nix`, applied by
    `systemd-sysctl`) reboots after a panic, and the 60 s hardware watchdog
    that PID 1 arms reboots after a hang of PID 1, if the board's watchdog
    driver binds (not checked on the hosts).
  - Without a console, arrange a fallback before rebooting; it covers only
    failures from stage 2 on. For example, after `nixos-rebuild boot`, on the
    running system: `bootctl set-default @current`, then `bootctl set-oneshot`
    the new generation's entry. Entry IDs are content hashes
    (`nixos-<sha256>.conf`); find them with `bootctl list`. Once the new
    generation is accepted, clear the persistent default with
    `bootctl set-default ""`, which hands the choice back to NixOS. After a
    fallback, first make the old generation the installed default again (e.g.
    `/run/current-system/bin/switch-to-configuration boot`), then clear it.
    `bootCounting` is the alternative, with the same stage-2 limit. Neither has
    been tried on these hosts.
  - The one-shot fallback fires only on a failure that reboots. A boot that
    completes but leaves the host unreachable stays on the new generation.
    Since the persistent default still names the old generation, any reboot
    then returns to it, but causing that reboot takes console or remote-hands
    access.
  - `panic=10` in `boot.kernelParams` would also reboot after a stage-1 panic,
    as `brev-worker`'s `panic=30` does. It changes the toplevels, not the
    kernel, and does not help a hang without a panic. That is the deployer's
    choice; this repository does not set it.
  - `nixos-build01` uses systemd-boot the same way, but sets neither
    `kernel.panic` nor the watchdog, so any panic, at any stage, halts it.
    `brev-worker` uses GRUB, whose saved entry falls back to its rescue
    installer (`devices/brev-worker/hardware.nix`).
- **Checking the running kernel:** `uname -r` reads 7.2.12 with or without the
  patch. Compare `readlink /run/booted-system/kernel` with the kernel's out
  path instead. With the current nixpkgs it is
  `/nix/store/nxk3gcwiarc8wkwkvh62p37g496ggij5-linux-7.2.12/bzImage` with the
  patch and `/nix/store/ydi4la1gxv20licqiba9vwinx6vwikgd-linux-7.2.12/bzImage`
  without it, on all four hosts. After a nixpkgs or patch change, get the
  current one with
  `nix eval --raw .#nixosConfigurations.<host>.config.boot.kernelPackages.kernel.outPath`.

## Provenance

- The patch is `git format-patch -1` of a commit (`729b86c59a4c`, kept only in
  a local scratch clone) on linux-stable tag v7.2.12 (`cc9de5d4b5ab`).
- nixpkgs' `linux-7.2.12.tar.xz`, the hosts' kernel `src`, has the same
  `mm/memcontrol.c`, `kernel/cgroup/cgroup.c`, `include/linux/cgroup.h` and
  `mm/oom_kill.c` as the tag. `patch -p1 --dry-run` applies the patch to it
  cleanly, and the kernel build applies it with no offset or fuzz.
- nixpkgs' other kernel patches (`bridge-stp-helper`, `request-key-helper`,
  `randstruct-provide-seed-5.19`) touch other files.
- Where this README and the commit message inside the `.patch` differ, this
  README is current. The message claims more than the patch covers: it says
  nothing of the gaps under
  [Where the window stays open](#where-the-window-stays-open). It also says
  less about `memory.oom.group`: only that a member with no mm is skipped. The
  message is left as it is, because any change to the file changes the kernel
  derivation that was built and tested. Refresh it when the patch has to be
  regenerated anyway, e.g. at a kernel update that moves its context.

## When to drop it

When the hosts' kernel fixes this upstream: `mem_cgroup_scan_tasks()` passes
`CSS_TASK_ITER_WITH_DEAD`, or the memcg OOM scan sees exiting victims some other
way. Check `css_task_iter_start()` in `mm/memcontrol.c` on each kernel update.
A change to those lines makes the patch fail to apply, which forces the check.
On 6.19.y or 7.0.y it does not build, for want of `CSS_TASK_ITER_WITH_DEAD`.

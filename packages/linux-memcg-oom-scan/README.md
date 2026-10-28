# memcg OOM scans and exiting OOM victims

`0001-mm-memcontrol-let-memcg-OOM-scans-see-exiting-OOM-vi.patch` makes
`mem_cgroup_scan_tasks()` pass `CSS_TASK_ITER_WITH_DEAD` along with
`CSS_TASK_ITER_PROCS`. A memcg OOM scan then still sees an OOM victim while it
exits, and aborts on it as `oom_evaluate_task()` intends, instead of killing a
second task while the first victim's memory is being freed.

`modules/zfs.nix` applies it, through `boot.kernelPatches`, to every host that
takes `linuxKernel.packages.linux_7_2` there: everything but `nixos-orin`.

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
  `__oom_kill_process()`, which for a task with no mm logs "OOM victim ... is
  already exiting. Skip killing the task" and returns (918-923). A dead zombie
  leader is not killed again; at most that line is logged.

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

Unpatched, from Tribuchet's agent-memory repeat test, build B1 at Tribuchet
`4ad5351` (output `ixphcz0g…-vm-test-run-tribuchet-agent-memory-repeat`,
2026-10-28): `~/Packages/fork-harness/runs/tribuchet-memory-guard/v2/b1-analysis.txt`,
its traces in `v2/b1-traces/`, and the VM consoles in `v2/b1-tip/build.log`.

- A shell's child pipeline buffers 1792 MiB of random bytes in a memcg until
  the kernel OOM-kills it. Runs with two OOM kills, by the cgroup's
  `memory.events`: 7.2.9 3 of 10, 6.18.55 0 of 10 (`b1-analysis.txt` lines
  9-12).
- The same in a memcg of its own (`memory.max` 768M, `memory.swap.max` 256M,
  zswap writeback off, so zswap's rejects stay in swap cache) with a `dd` loop
  beside it: 7.2.9 6 of 29, 6.18.55 0 of 39 (lines 17-18).
- bpftrace on `out_of_memory()`, `oom_evaluate_task()`, `__oom_kill_process()`,
  and the victim's `do_exit()` and `exit_mmap()`, summarised by Tribuchet's
  `nix/agent-memory-oom-trace.py` at `6496516`: on 7.2.9, 11 scans passed the
  victim's place in the task list after its `do_exit()`, 7 of them during its
  `exit_mmap()`. None evaluated the victim; each selected another task, which
  was killed in 9 and already exiting in 2 (`build.log` lines 21332 and 22979).
  On 6.18.55, all 17 such scans evaluated the victim, with `PF_EXITING` set and
  `signal->live` 0, and aborted.

The patched kernel had not been built or booted when this was committed.

## Provenance

- Base: linux-stable tag v7.2.12 (`cc9de5d4b5ab`), fetched shallow into
  `~/Packages/fork-harness/runs/kernel-overkill-check/trees.git`. The change is commit
  `729b86c59a4c` on it (`refs/archive/2026-10-27/memcg-oom-with-dead-7.2.12`),
  and the patch is its `git format-patch -1`.
- nixpkgs' `linux-7.2.12.tar.xz`, the hosts' kernel `src`, has the same
  `mm/memcontrol.c`, `kernel/cgroup/cgroup.c`, `include/linux/cgroup.h` and
  `mm/oom_kill.c` as the tag, and `patch -p1 --dry-run` applies the patch to
  it cleanly. nixpkgs' own kernel patches (`bridge-stp-helper`,
  `request-key-helper`) touch other files.
- Analysis and scratch files: `~/Packages/fork-harness/runs/kernel-overkill-check/`
  (`vendor/`, `draft2/`).

## When to drop it

When the hosts' kernel fixes this upstream: `mem_cgroup_scan_tasks()` passes
`CSS_TASK_ITER_WITH_DEAD`, or the memcg OOM scan sees exiting victims some other
way. Check `css_task_iter_start()` in `mm/memcontrol.c` on each kernel update.
A change to those lines makes the patch fail to apply, which forces the check.
On 6.19.y or 7.0.y it does not build, for want of `CSS_TASK_ITER_WITH_DEAD`.

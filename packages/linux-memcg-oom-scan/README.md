# memcg OOM scans and exiting OOM victims

`0001-mm-memcontrol-let-memcg-OOM-scans-see-exiting-OOM-vi.patch` makes
`mem_cgroup_scan_tasks()` pass `CSS_TASK_ITER_WITH_DEAD` along with
`CSS_TASK_ITER_PROCS`. The memcg OOM scan then shows tasks as it did before
`a72f73c4dd9b`. For a single-threaded OOM victim that means the scan still sees
the victim while it exits, and aborts on it as `oom_evaluate_task()` intends,
instead of killing a second task while the victim's memory is being freed. A
multi-threaded victim can still be missed, as on 6.18; see
[Multi-threaded victims](#multi-threaded-victims).

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
  `__oom_kill_process()` on each member it is given:
  - A member with no mm left, such as a dead zombie leader, is not killed again:
    `__oom_kill_process()` logs "OOM victim ... is already exiting. Skip killing
    the task" and returns (918-923).
  - A member that is exiting but still holds its mm, between its
    `signal->live` decrement (`kernel/exit.c:934`) and `exit_mm()` clearing
    `->mm` (586), is now walked too. It is sent `SIGKILL` again, counted in
    `OOM_KILL` and the memcg's `oom_kill` event (`mm/oom_kill.c:935-936`), and
    logged as "Killed process" (945). That only inflates the counters and the
    log; 6.18 and 6.19.0-6.19.8 did the same.

## Multi-threaded victims

The patch does not keep every multi-threaded victim visible:

- `CSS_TASK_ITER_PROCS` returns only thread-group leaders (5159-5160), so the
  scan sees a victim only through its leader.
- `MMF_OOM_SKIP` is set by whichever thread drops the mm's last user reference:
  `exit_mm()` calls `mmput()` (`kernel/exit.c:593`), and the last one runs
  `exit_mmap()`.
- If the leader makes its final context switch while other threads still live,
  `do_cgroup_task_dead()` moves it to `dying_tasks` (7102-7104). If no thread
  lives by then, it unlinks the leader altogether. Either way, once the group's
  last `signal->live` decrement (`kernel/exit.c:934`) has happened, the PROCS
  branch hides the leader (5162-5165), and `CSS_TASK_ITER_WITH_DEAD` does not
  change that branch.
- So when the leader is gone and a non-leader does the last `mmput()`, the
  victim is hidden from that decrement until `exit_mmap()` sets `MMF_OOM_SKIP`,
  and a charge meanwhile can still kill a second task.

This is not a regression: 6.18 has the same gap. Its `cgroup_exit()`, run from
the leader's own `do_exit()` (v6.18.59 `kernel/exit.c:986`), puts the leader on
`dying_tasks` the same way (v6.18.59 `kernel/cgroup/cgroup.c:7021-7025`), and
its PROCS branch hides it the same way (5149-5152). The patch restores the
pre-`a72f73c4dd9b` behaviour, which closes the window for single-threaded
victims, the case the evidence below tests. Closing it for multi-threaded ones
would need a walk over all threads, with `CSS_TASK_ITER_WITH_DEAD`, that counts
each thread group once.

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

Both tests below are NixOS VM tests built from Tribuchet's agent-memory repeat
test (`nix/agent-memory-repeat-test.nix`, `nix/oom-probes.bt` and
`nix/agent-memory-oom-trace.py` in the Tribuchet repository). Their run records
were kept as scratch outside this repository; what follows describes the tests
well enough to rerun them.

Each VM has 3 GiB of memory, 2 vCPUs and zram swap as on `nixos-ext`, and runs
Tribuchet's worker module (its agent slice, zswap and swap guard) without
starting the worker itself. The test runs two cases:

- **Hog:** in a cgroup under the agent slice, a shell at OOM score 0 runs
  `tr -d '\n' </dev/urandom | head -c 1792M | tail -n 1` until the guard clamps
  the slice's swap and the kernel OOM-kills the pipeline. A run passes if the
  shell survives and the cgroup's `memory.events` counts one `oom_kill`.
- **Second allocator:** the same pipeline in a cgroup of its own
  (`memory.max` 768M, `memory.swap.max` 256M, `memory.zswap.writeback` 0, so
  zswap's rejects stay in swap cache), beside a loop of
  `dd if=/dev/zero of=/dev/null bs=8M count=4`, repeated for a fixed time. A
  run passes if `memory.events` counts one `oom_kill`.

bpftrace on every VM traces `out_of_memory()`, `oom_evaluate_task()`,
`__oom_kill_process()`, and each victim's `do_exit()` and `exit_mmap()`. An
over-kill scan is one that, after a kill, passes the victim's place in the task
list before the victim's `exit_mmap()` returns, does not evaluate the victim,
and selects another task.

### Patched against unpatched 7.2.12

Run on 2026-10-28 with Tribuchet's test files at `6496516`, cut to the two cases
above:

- **Kernels:** this repository's `linux_7_2` package set as `nixos-ext`
  evaluates it, both with the patch (`6826e2b`) and without it (`f7f0e9a`),
  plus Tribuchet's own `linux_7_2` (7.2.9). The two 7.2.12 kernels have
  byte-identical `.config` files; their derivations differ only by the patch.
- **Layout:**
  - each 7.2.12 kernel: two VMs with 10 hog runs each, and one VM with a 300 s
    second-allocator loop;
  - 7.2.9: one second-allocator VM.

Runs with two or more OOM kills:

| Case | Patched 7.2.12 | Unpatched 7.2.12 | 7.2.9 |
| --- | --- | --- | --- |
| Hog | 0 of 20 | 4 of 20 | not run |
| Second allocator | 0 of 86 | 29 of 90 | 34 of 78 |
| Over-kill scans, all runs | 0 | 36 | 35 |

- **Patched kernel:** every hog shell survived, and every run had exactly one
  kill. Its scans evaluated an exiting victim (`PF_EXITING` set,
  `signal->live` 0) 57 times, and aborted every time, as 6.18.55 does below.
- **Unpatched 7.2.12:** its 36 over-kill scans killed 34 more tasks; the other
  2 picked a task that was already exiting. Unpatched scans evaluated an
  exiting victim with `signal->live` 0 only 3 times on each kernel, consistent
  with `signal->live` dropping between the iterator's check and the evaluation.
- **Significance:** one-sided Fisher exact tests, patched against unpatched
  7.2.12, give p = 2.6e-10 for the second-allocator runs and p = 0.053 for the
  hog runs. Each second-allocator arm is a single VM, so its runs are not
  independent replicates.

### Before the patch: 7.2.9 against 6.18.55

Tribuchet's test at `4ad5351` (build B1, 2026-10-28) ran both cases on 7.2.9
and 6.18.55: 5 hog runs on each of two VMs per kernel, and a 150 s
second-allocator loop on one VM per kernel.

- Hog runs with two kills: 7.2.9 3 of 10, 6.18.55 0 of 10.
- Second-allocator runs with two kills: 7.2.9 6 of 29, 6.18.55 0 of 39.
- Traces, summarised with Tribuchet `6496516`'s `agent-memory-oom-trace.py`:
  - On 7.2.9, 11 scans passed the victim's place in the task list after its
    `do_exit()`, 7 of them during its `exit_mmap()`. None evaluated the victim.
    Each selected another task, which was killed in 9 cases and already exiting
    in 2.
  - On 6.18.55, all 17 such scans evaluated the victim, with `PF_EXITING` set
    and `signal->live` 0, and aborted.

The patched kernel has been built and booted only in the VM test above; no
host has booted it yet.

## Provenance

- The patch is `git format-patch -1` of a commit (`729b86c59a4c`) on
  linux-stable tag v7.2.12 (`cc9de5d4b5ab`).
- nixpkgs' `linux-7.2.12.tar.xz`, the hosts' kernel `src`, has the same
  `mm/memcontrol.c`, `kernel/cgroup/cgroup.c`, `include/linux/cgroup.h` and
  `mm/oom_kill.c` as the tag. `patch -p1 --dry-run` applies the patch to it
  cleanly, and the kernel build applies it with no offset or fuzz.
- nixpkgs' other kernel patches (`bridge-stp-helper`, `request-key-helper`,
  `randstruct-provide-seed-5.19`) touch other files.

## When to drop it

When the hosts' kernel fixes this upstream: `mem_cgroup_scan_tasks()` passes
`CSS_TASK_ITER_WITH_DEAD`, or the memcg OOM scan sees exiting victims some other
way. Check `css_task_iter_start()` in `mm/memcontrol.c` on each kernel update.
A change to those lines makes the patch fail to apply, which forces the check.
On 6.19.y or 7.0.y it does not build, for want of `CSS_TASK_ITER_WITH_DEAD`.

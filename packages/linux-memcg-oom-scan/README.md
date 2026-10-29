# memcg OOM scans miss exiting OOM victims (7.0+)

[`0001-mm-memcontrol-let-memcg-OOM-scans-see-exiting-OOM-vi.patch`](0001-mm-memcontrol-let-memcg-OOM-scans-see-exiting-OOM-vi.patch)
changes one call in `mem_cgroup_scan_tasks()` from `CSS_TASK_ITER_PROCS` to
`CSS_TASK_ITER_PROCS | CSS_TASK_ITER_WITH_DEAD`. Without it, a memcg OOM can kill
a second task while the first victim is still freeing its memory.
[`modules/zfs.nix`](../../modules/zfs.nix) applies it with `boot.kernelPatches`
to every host on `linux_7_2`, which is all of them except `nixos-orin`.

## Problem

Line links are to v7.2.12.

1. [a72f73c4dd9b] ("cgroup: Don't expose dead tasks in cgroup", Sebastian
   Andrzej Siewior; in v7.0 and 6.19.9) makes `css_task_iter_advance()` skip a
   task with `PF_EXITING` once its `signal->live` is 0
   ([cgroup.c:5153][cg-hide]). The skip applies unless the caller passes
   `CSS_TASK_ITER_WITH_DEAD`, which [60f21a264930] (Tejun Heo, v7.1) added for
   sched_ext.
1. `mem_cgroup_scan_tasks()` passes only `CSS_TASK_ITER_PROCS`
   ([memcontrol.c:1374][mc-scan]), so the scan stops returning a victim at its
   `signal->live` decrement ([exit.c:934][exit-live]). That happens before
   `exit_mm()`, and so before `exit_mmap()` sets `MMF_OOM_SKIP`
   ([mmap.c:1307][mmap-skip]).
1. `oom_evaluate_task()` aborts the scan while it can still see a victim whose
   mm is not `MMF_OOM_SKIP` ([oom_kill.c:324][oom-abort]). With the victim
   hidden, a concurrent charge selects and kills another task.

The underlying cause is [d245698d727a] (Tejun Heo), which defers the cgroup
unlink until the task's final context switch. a72f73c4dd9b fixed the systemd
symptom of that change (`waitpid()` returning a pid that was still in
`cgroup.procs`), and in doing so hid victims from the OOM scan.

## Fix

With `CSS_TASK_ITER_WITH_DEAD`, `css_task_iter_advance()` filters exactly as it
did before a72f73c4dd9b, whose diff only inserted the skip. The scan's callers
already handle exiting tasks:

- `oom_badness()` and `dump_task()` skip a task with no mm;
- `oom_kill_process()` lets an exiting victim go via `task_will_free_mem()`;
- `__oom_kill_process()` skips a `memory.oom.group` member with no mm.

## Evidence

The tests are NixOS VMs: 3 GiB of memory, 2 vCPUs, and zram swap with swappiness 190.

- **Hog:** a shell runs `tr -d '\n' </dev/urandom | head -c 1792M | tail -n 1`
  in a fresh memcg, until the pipeline is OOM-killed. The memcg sits under a
  slice with a 1536 MiB reserve, and Tribuchet's swap guard clamps that slice's
  swap.
- **Second allocator:** the same pipeline runs alongside a
  `dd if=/dev/zero of=/dev/null bs=8M` loop, in a memcg with `memory.max=768M`,
  `memory.swap.max=256M` and `memory.zswap.writeback=0`.

A run fails if it records two or more kills (memcg `oom_kill` ≥ 2). bpftrace
traced `out_of_memory()`, `oom_evaluate_task()`, `__oom_kill_process()`, and
the victim's `do_exit()` and `exit_mmap()`. The two 7.2.12 kernels have
identical `.config` files and differ only by the patch.

| Runs with ≥ 2 kills | 7.2.12 patched | 7.2.12 unpatched | 7.2.9 | 6.18.55 |
| --- | --- | --- | --- | --- |
| Hog | 0/20 | 4/20 | 3/10 | 0/10 |
| Second allocator | 0/86 | 29/90 | 6/29, 34/78 | 0/39 |
| Scans that passed the exiting victim and picked another task | 0 | 36 | 11, 35 | 0 |

- **Patched 7.2.12:** scans evaluated an exiting victim (`PF_EXITING`,
  `signal->live == 0`) 57 times and aborted every time, as 6.18.55 did (17 of
  17). Unpatched 7.2.12 evaluated one only 3 times.
- **7.2.9 and 6.18.55:** the first number in each cell is from an earlier,
  separate run: 5 hog runs on each of two VMs, plus a 150 s second-allocator
  loop. 7.2.9's second numbers come from the run that compared patched and
  unpatched 7.2.12.
- **Significance:** one-sided Fisher exact tests, patched against unpatched
  7.2.12, give p = 2.6e-10 for the second allocator and p = 0.053 for the hog.
  The runs pool few VMs, so they are not independent replicates.
- **Harness:** it lives in unpublished Tribuchet commits (`6496516`,
  `4ad5351`). The second-allocator case needs nothing beyond what is described
  here.

## Limits

These limits are not regressions: 6.18 has the same gaps. They come from
reading the source, and no test covers them.

- **Multi-threaded victims.** `CSS_TASK_ITER_PROCS` sees a process only through
  its group leader. A leader that exits while other threads live is parked on
  `dying_tasks`, and the PROCS branch hides it ([cgroup.c:5162][cg-procs]) until
  the last thread's `mmput()`. Closing this needs a walk over all threads with
  `CSS_TASK_ITER_WITH_DEAD` that counts each thread group once.
- **Other mm holders.** A `/proc` reader (`get_task_mm()`) or a `CLONE_VM`
  sharer can keep the mm alive after the victim is unlinked. That window lasts
  until its `mmput()`, or until the OOM reaper runs, at least 2 s after the kill.
- **`memory.oom.group`.** A member that is exiting but still has an mm is
  killed again. That only inflates `oom_kill` counts and log lines, as 6.18 and
  6.19.0–6.19.8 did.

## Related upstream work

- **Zhan Xusheng's patch** ([v1], 2026-10-26; [v2], 2026-10-27; Reviewed-by and
  Tested-by from Tao Cui on v1) walks all threads to catch processes whose
  leader has exited.
- **sashiko-bot's review of v1** ([sashiko]) flagged exactly this missed
  victim.
- **v2** still calls `css_task_iter_start(..., 0, ...)` without
  `CSS_TASK_ITER_WITH_DEAD`, so the iterator drops the exiting threads before
  v2's helper sees them. v2 with `CSS_TASK_ITER_WITH_DEAD` added would cover
  both this patch and the multi-threaded limit above.

## Affected kernels

| Kernel | Hides exiting tasks | This patch applies |
| --- | --- | --- |
| 7.1+, mainline [8a36f53fd5ec] | yes | yes (mainline: memcontrol.c:1454) |
| 7.0.y | yes | needs 60f21a264930 first |
| 6.19.9+ | yes | needs 60f21a264930 first |
| ≤ 6.19.8, 6.18.y, 6.12.y, 6.6.y | no | not needed |

`nixos-orin` runs L4T 5.15; its source was not checked.

## Upstreaming

- **Base:** rebase onto mm-unstable or mainline; the hunk moves to
  memcontrol.c:1454. Keep `Fixes: a72f73c4dd9b`, and add `Cc: stable` for 7.1+.
  For 6.19.y and 7.0.y, the stable backport needs 60f21a264930 as well.

- **Commit message:** update it before sending:

  - add the multi-threaded limit;
  - cite Zhan's thread and how this patch relates to v2;
  - describe the reproducer, as in Evidence above.

  The message in the `.patch` is left as built and tested, because editing the
  file changes the kernel derivation.

## Deploying and dropping

- **Check the running kernel:** `uname -r` reads 7.2.12 either way. Compare
  `readlink /run/booted-system/kernel` with
  `nix eval --raw .#nixosConfigurations.<host>.config.boot.kernelPackages.kernel.outPath`.
- **Rollback:**
  - `nixos-ext` and `nixos-desktop` have no console. Before rebooting, run
    `bootctl set-default @current`, then `bootctl set-oneshot <new entry>`.
    Once the new generation is accepted, run `bootctl set-default ""`.
  - A stage-1 panic halts these hosts unless `panic=10` is in
    `boot.kernelParams`.
- **Drop the patch** once the hosts' kernel passes `CSS_TASK_ITER_WITH_DEAD`,
  or otherwise shows exiting victims to the memcg scan. A change to that line
  makes the patch fail to apply, which forces the check.

[60f21a264930]: https://git.kernel.org/torvalds/c/60f21a2649308bbd84919ba6656d5ccd660953cf
[8a36f53fd5ec]: https://git.kernel.org/torvalds/c/8a36f53fd5ec
[a72f73c4dd9b]: https://git.kernel.org/torvalds/c/a72f73c4dd9b209c53cf8b03b6e97fcefad4262c
[cg-hide]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/kernel/cgroup/cgroup.c?h=v7.2.12#n5153
[cg-procs]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/kernel/cgroup/cgroup.c?h=v7.2.12#n5162
[d245698d727a]: https://git.kernel.org/torvalds/c/d245698d727ab8f5420b3e28d1243f96a5234851
[exit-live]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/kernel/exit.c?h=v7.2.12#n934
[mc-scan]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/mm/memcontrol.c?h=v7.2.12#n1374
[mmap-skip]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/mm/mmap.c?h=v7.2.12#n1307
[oom-abort]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/mm/oom_kill.c?h=v7.2.12#n324
[sashiko]: https://lore.kernel.org/r/sashiko-outbox-186496@kernel.org
[v1]: https://lore.kernel.org/r/20261026120248.2188024-1-zhanxusheng1024@gmail.com
[v2]: https://lore.kernel.org/r/20261027144016.2582880-1-zhanxusheng1024@gmail.com

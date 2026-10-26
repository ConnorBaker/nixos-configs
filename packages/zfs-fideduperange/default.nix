# OpenZFS afb4010 ("Implement FIDEDUPERANGE via block cloning", PR
# openzfs/zfs#18745), backported to zfs-2.4.4. It is on master and in no
# release yet. With it, a dedupe leaves the destination's mtime, ctime and
# setid bits alone, and zfs-dedup can run without --force.
#
# The patches, from `git format-patch zfs-2.4.4..` on the backport:
# - 0001: afb4010, the kernel change. It also touches zfs.4, so the userspace
#   tools take it too and both stay on the same source.
# - 0002: 39764eb06, the fix for a double free when cloning a block with a
#   pending free. It is in dmu_read_l0_bps(), which both FICLONE and
#   FIDEDUPERANGE use.
# - 0003: 1a8e51491, the fix for a self-deadlock when cloning a range within
#   one file.
# - 0004: a5b536566, the commit's ZTS cases. It changes only tests/, which
#   generic.nix does not install, so hosts do not apply it.
# - 0005: c0688a275, the fix for ZIL replay of indirect writes. Without it,
#   a write logged WR_INDIRECT and then deduped in the same txg is logged
#   by fsync() as a TX_WRITE2 with no data, and is lost if the txg does not
#   sync before a crash. With it, fsync() waits for that txg to sync. It
#   also changes zdb, so the userspace tools take it too. Its ZTS cases are
#   in tests/, and it applies with or without 0004.
# - 0006: f1f96f5e7, which restores the BP_IS_HOLE() recheck in
#   dbuf_read_hole(). Stock 2.4.4 has the race: its a6f557c2c (79cf54582 on
#   2.3) dropped the recheck. A read that waits in dnode_block_freed() while
#   dnode_sync() frees a block held in the dnode hands a hole to arc_read(),
#   which suspends the pool (openzfs/zfs#19185). Applies without conflict.
#   Failing first: checks zfs-fideduperange-hole-race(-without-0006) widen
#   the window with a test-only delay, as openzfs/zfs#19234's reproducer did
#   (test-only-dbuf-read-hole-delay.patch, never in hostPatches). Without
#   0006, reads fail with EINVAL and data ereports match #19185's; with it,
#   every read returns zeros.
# - 0007: e9e24ce2c, which stops zfs_xattr_owner_unlinked() from releasing
#   znodes inline under an assigned transaction. On Linux that can run inode
#   cleanup during writeback and deadlock the txg (openzfs/zfs#19253).
#   Applies without conflict.
# - 0008: 7c3d85aaf, which keeps ZIL replay from applying part of a
#   WR_NEED_COPY write that was split across log blocks. Upstream it comes
#   before c0688a275 (0005), so it conflicts with 0005 in zil_replay() only;
#   the resolution makes zil_replay() the same as master's after both. Its
#   other conflicts are in the ZTS slog lists, which now match master's. It
#   also changes zdb and ztest. Its four slog ZTS cases are in tests/, and it
#   applies with or without 0004.
# Each patch's message has its backport notes.
#
# sync=disabled: every dataset on nixos-ext and nixos-desktop is
# sync=disabled (zfs get, 2026-10-25), so nothing is logged, and the ZIL
# fixes (0005, 0007, 0008) are not reached through the ZIL there today. The
# set does not depend on that: it is carried so that a dataset or zvol that
# leaves sync=disabled is covered too. 0005 is not inert regardless: it also
# changes dmu_write_direct() and dmu_sync_done(), which every Direct I/O
# write runs, whatever the sync setting. 0006 is not a ZIL fix; it covers
# every read.
#
# A ZFS bump must re-check them: master may have changed, or the release may
# already include them.
{ lib }:
let
  hostPatches = [
    ./0001-Implement-FIDEDUPERANGE-via-block-cloning.patch
    ./0002-Fix-double-free-when-cloning-a-block-with-a-pending-.patch
    ./0003-Fix-self-deadlock-when-cloning-a-range-within-the-sa.patch
    ./0005-ZIL-replay-of-an-indirect-write-leaks-later-writes-i.patch
    ./0006-dbuf-restore-BP_IS_HOLE-recheck-after-dnode_block_fr.patch
    ./0007-ZIL-avoid-deadlock-in-xattr-owner-check.patch
    ./0008-ZIL-replay-can-apply-part-of-a-split-WR_NEED_COPY-wr.patch
  ];
  testsPatch = ./0004-ZTS-Add-FIDEDUPERANGE-tests.patch;
  # Test only, never in hostPatches: see withHoleReadDelay.
  holeReadDelayPatch = ./test-only-dbuf-read-hole-delay.patch;
  patchWith =
    patches: zfs:
    lib.throwIfNot (zfs.version == "2.4.4")
      "zfs-fideduperange: the backport targets zfs 2.4.4, but this ZFS is ${zfs.version}"
      (
        zfs.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ patches;
        })
      );
in
{
  # For boot.zfs.package and boot.zfs.modulePackage.
  withFideduperange = patchWith hostPatches;
  # For the ZTS VM test only.
  withFideduperangeTests = patchWith (hostPatches ++ [ testsPatch ]);
  # For the 0006 race check only (tests/zfs-fideduperange-hole-race.nix):
  # the hosts' patches, with or without 0006, plus a test-only module
  # parameter that sleeps in dbuf_read_hole() to widen the race 0006 closes.
  withHoleReadDelay =
    with0006:
    patchWith (
      (
        if with0006 then
          hostPatches
        else
          lib.remove ./0006-dbuf-restore-BP_IS_HOLE-recheck-after-dnode_block_fr.patch hostPatches
      )
      ++ [ holeReadDelayPatch ]
    );
}

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
  ];
  testsPatch = ./0004-ZTS-Add-FIDEDUPERANGE-tests.patch;
  patch =
    extra: zfs:
    lib.throwIfNot (zfs.version == "2.4.4")
      "zfs-fideduperange: the backport targets zfs 2.4.4, but this ZFS is ${zfs.version}"
      (
        zfs.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ hostPatches ++ extra;
        })
      );
in
{
  # For boot.zfs.package and boot.zfs.modulePackage.
  withFideduperange = patch [ ];
  # For the ZTS VM test only.
  withFideduperangeTests = patch [ testsPatch ];
}

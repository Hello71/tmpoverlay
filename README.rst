tmpoverlay
==========

tmpoverlay is a small, almost-POSIX shell script to create tmpfs-backed
overlayfs mounts. See tmpoverlay --help for usage information.

One important thing to note is that like any other Linux mount, an overlayfs
mount only affects new directory lookups. If a process has its current
directory or has files open inside the mount point, it continues to access the
original directory, not the overlaid one. Each process also has a cached root
directory pointer, which can only be modified by chroot (internally) or
pivot_root (globally). The pivot_root(2) and pivot_root(8) man pages should be
fully read and understood before using tmpoverlay to overmount root.

POSIX compliance
----------------

With the following exceptions, tmpoverlay is intended to be functional on
POSIX-only shells:

- ``getopt --`` is required for proper handling of options containing spaces
- ``mount -t overlay`` is obviously required
- ``getfattr`` is used for xattr copying but in case of failure, the system is
  assumed to not support xattrs and setfattr is skipped.
- ``stat -c`` is used to obtain upperdir owner and permissions, because parsing
  ls -l is nonsense.

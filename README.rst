tmpoverlay
==========

tmpoverlay is a small, almost-POSIX shell script to create tmpfs-backed
overlayfs mounts.

Features
--------

- minimal requirements (sh, mount, getopt)

Benefits over manually calling ``mkdir /tmp/x; mount ...``

- separate tmpfs allows size limit (``tmpoverlay -t size=SIZE``)
- upperdir and workdir automatically managed
- tmpfs cleanup after mount so that umount frees RAM
- synchronizes owner, permissions, and xattrs (including lowerdir ACL)
- autodetects optimization flags (redirect_dir, metacopy, index, volatile)

Overmounting
------------

Like any other Linux mount, an overlayfs mount only affects new directory
lookups. If a process has its current directory or has files open inside the
mount point, it continues to access the original directory, not the overlaid
one. Each process also has a cached root directory pointer, which can only be
modified by chroot (internally) or pivot_root (globally). The pivot_root(2)_
and pivot_root(8)_ man pages should be fully read and understood before using
tmpoverlay to overmount ``/``.

.. _pivot_root(2): https://man7.org/linux/man-pages/man2/pivot_root.2.html
.. _pivot_root(8): https://man7.org/linux/man-pages/man8/pivot_root.8.html

Changes to underlying filesystems
---------------------------------

Per `the kernel overlayfs documentation`_, changing underlying filesystems
while the overlay is mounted is not supported.

.. _the kernel overlayfs documentation: https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html#changes-to-underlying-filesystems

Pseudo-filesystems
------------------

Pseudo-filesystems like procfs and sysfs are not intended to be used with
overlayfs. Therefore, running commands like ``tmpoverlay /proc`` may have
unexpected results.

POSIX compliance
----------------

With the following exceptions, tmpoverlay is intended to be functional on
POSIX-only shells:

- ``mount -t overlay`` is obviously required
- ``getopt --`` is required for proper handling of options containing spaces
- ``getfattr`` is used for xattr copying but in case of failure, the system is
  assumed to not support xattrs and setfattr is skipped.
- ``realpath`` is required for canonicalizing paths if -c is not provided

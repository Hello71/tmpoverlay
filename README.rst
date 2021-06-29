tmpoverlay
==========

tmpoverlay is a small, almost-POSIX shell script to create tmpfs-backed
overlayfs mounts.

Features
--------

- minimal requirements (sh, mount, getopt)
- single shell script, no compilation required
- small (7 KB, 2 KB after gzip -9)

Benefits over manually calling ``mkdir /tmp/x; mount ...``

- separate tmpfs allows size limit (``tmpoverlay -t size=SIZE``)
- upperdir and workdir automatically managed
- tmpfs cleanup after mount so that umount frees RAM
- synchronizes owner, permissions, and xattrs (including ACLs)
- autodetects optimization flags (redirect_dir, metacopy, index, volatile)

Overmounting
------------

Like any other Linux mount, an overlayfs mount only affects new directory
lookups. If a process has its current directory or has files open inside the
mount point, it continues to access the original directory, not the overlaid
one. Each process also has a cached root directory pointer, which can only be
modified by chroot (internally) or pivot_root (globally). The pivot_root(2)_
and pivot_root(8)_ man pages should be fully read and understood before using
tmpoverlay to overmount ``/``. It is also highly recommended to read `busybox
switch_root comment`_.

.. _pivot_root(2): https://man7.org/linux/man-pages/man2/pivot_root.2.html
.. _pivot_root(8): https://man7.org/linux/man-pages/man8/pivot_root.8.html
.. _busybox switch_root comment: https://git.busybox.net/busybox/tree/util-linux/switch_root.c?id=3b267e99259191eca0865179a56429c4c441e2b2#n289

Changes to underlying filesystems
---------------------------------

Per `the kernel overlayfs documentation`_, changing underlying filesystems
while the overlay is mounted is not supported:

    Changes to the underlying filesystems while part of a mounted overlay
    filesystem are not allowed. If the underlying filesystem is changed, the
    behavior of the overlay is undefined, though it will not result in a crash
    or deadlock.

.. _the kernel overlayfs documentation: https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html#changes-to-underlying-filesystems

Unprivileged operation using user namespaces
--------------------------------------------

Since Linux 5.11, overlayfs can be mounted in unprivileged user namespaces.
This means that it is possible to temporarily place an overlay in a local
context. For example, ``unshare -Umc --keep-caps sh -c 'tmpoverlay . && exec
setpriv --inh-caps=-all $SHELL'`` has a similar effect to ``tmpoverlay .``, but
does not require privileges. In exchange, it only takes effect within the newly
started shell, similar to environment variables.

Note that tmpfs overlay doesn't work properly with unmapped UIDs. In other
words, after running tmpoverlay, only files owned by the current user can be
modified; modifying other files will have unpredictable results.

This issue can be mitigated starting with Linux 5.12 using idmap, but this is
not integrated in tmpoverlay due to a lack of standard utilities.

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

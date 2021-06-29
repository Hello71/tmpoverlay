#!/bin/sh

usage() {
    [ "$1" = 0 ] || exec >&2
    cat << EOF
usage: tmpoverlay [OPTIONS] [SOURCE...] DEST

Create a tmpfs-backed overlayfs at DEST starting with SOURCEs. If no SOURCE is
specified, use DEST as the source. To free the memory, simply umount DEST.

options:
  -c, --no-canonicalize  don't canonicalize paths
  -h, --help             print this help
  -o, --overlayfs OPTS   add overlayfs mount options, e.g. redirect_dir/metacopy
  -n, --no-mtab          don't write to /etc/mtab
  -N, --mount-name NAME  source name for mount (default "overlay")
  -t, --tmpfs OPTS       add tmpfs mount options, e.g. size
  -v, --verbose          verbose mode

examples:
  tmpoverlay / /new_root       # make a thin copy of root
  tmpoverlay /etc              # make read-only /etc writable
  tmpoverlay /a /b /c /merged  # merge /a, /b, /c, and a fresh tmpfs
  tmpoverlay /                 # USE WITH CAUTION, see docs
  unshare -Umc --keep-caps sh -c 'tmpoverlay . && exec \$SHELL' # make cwd writable as non-root
EOF
    exit "$1"
}

log() {
    # not equivalent to printf "tmpoverlay: $@"
    printf 'tmpoverlay: ' >&2
    printf "$@" >&2
    printf '\n' >&2
}

logv() {
    [ -z "$verbose" ] || log "$@"
}

cmd() {
    logv '%s ' "$@"
    "$@"
}

unset tmpdir
die() {
    r=$?
    [ "$r" != 0 ] || r=1
    [ "$#" = 0 ] || log "$@"
    [ -z "$tmpdir" ] || { exec 9>&-; wait; }
    exit $r
}

canon() {
    if [ -n "$no_canon" ]; then
        printf '%s\n' "$1"
    else
        realpath "$1"
    fi
}

my_getopt() {
    getopt \
        -l no-canonicalize \
        -l help \
        -l overlayfs: \
        -l no-mtab \
        -l mount-name: \
        -l tmpfs: \
        -l verbose \
        -n tmpoverlay \
        -- \
        cho:nN:t:v \
        "$@"
}

args=$(my_getopt "$@") || usage 1
eval set -- "$args"
unset args

unset no_canon extra_ovl_opts no_mtab mount_name tmpfs_opts verbose
while true; do
    case "$1" in
        -c|--no-canonicalize) no_canon=-c; shift;;
        -h|--help) usage 0;;
        -o|--overlayfs)
            [ -n "$2" ] && extra_ovl_opts="$extra_ovl_opts,$2"
            shift 2
            ;;
        -n|--no-mtab) no_mtab=-n; shift;;
        -N|--mount-name) mount_name=$2; shift 2;;
        -t|--tmpfs)
            [ -n "$2" ] && tmpfs_opts="${tmpfs_opts:+$tmpfs_opts,}$2"
            shift 2
            ;;
        -v|--verbose) verbose=-v; shift;;
        --) shift; break;;
        *) die "getopt failure"
    esac
done

[ $# != 0 ] || usage 1

unset lowerdir
while [ "$#" != 1 ]; do
    d=$(canon "$1")
    if [ -h "$d" ] || ! [ -d "$d" ]; then
        die 'source "%s" is not a directory' "$d"
    fi
    lowerdir=${lowerdir+:}$d
    shift
done

dest=$(canon "$1")
[ -d "$dest" ] || die 'destination "%s" is not a directory' "$dest"
[ "$dest" != / ] || log 'overmounting root, use with caution'

[ -n "$lowerdir" ] || lowerdir=$dest

logv 'creating tmpdir'
tmpdir=$(cmd umask 077; cmd mktemp -dt tmpoverlay.XXXXXXXXXX) || die
logv 'created tmpdir: %s' "$tmpdir"
# won't trigger on overmounting /, which is actually correct
case "$tmpdir" in
    "$dest"/*) log "warning: tmpdir cannot be cleaned up after overmounting $dest"
esac
cmd mount -t tmpfs ${tmpfs_opts:+-o "$tmpfs_opts"} $verbose tmpfs "$tmpdir" || { cmd rmdir "$tmpdir"; die; }
cmd mkfifo "$tmpdir/fifo" || { cmd umount "$tmpdir"; cmd rmdir "$tmpdir"; die; }
# subshell allows cleanup after overmount /tmp without using realpath source
# subshell also avoids trapping and re-raising signals which is annoying in shell
(
    cmd cd "$tmpdir" || die
    trap '' INT || die
    exec <fifo || die
    # read returns non-zero when write end is closed
    read _
    logv 'unmounting tmpdir'
    # TODO: this *almost* works except umount insists on canonicalizing .
    # shellcheck disable=SC2086
    cmd umount -cil $no_mtab . || die
    logv 'deleting tmpdir'
    cmd cd /
    cmd rmdir "$tmpdir" || die
) &
# should be FD_CLOEXEC but can't do in shell
exec 9>"$tmpdir/fifo"
# starting from here, exiting will cause cleanup

upperdir="$tmpdir/upper"
workdir="$tmpdir/work"
tmpmnt="$tmpdir/tmpmnt"
cmd mkdir "$upperdir" "$workdir" "$tmpmnt" || die

ovl_opts="lowerdir=$lowerdir,upperdir=$upperdir,workdir=$workdir"
logv 'testing overlay options'
cmd mount -n -t overlay -o "$ovl_opts" overlay "$tmpmnt" || die "overlayfs is not supported"
cmd umount "$tmpmnt"
if [ -n "$extra_ovl_opts" ]; then
    ovl_opts="$ovl_opts,$extra_ovl_opts"
    cmd mount -n -t overlay -o "$ovl_opts" overlay "$tmpmnt" || die "invalid extra overlayfs options"
    cmd umount "$tmpmnt" || die
fi
chk_ovl_opt() {
    if [ -n "$2" ]; then
        case ",$ovl_opts," in
            *",$1=$2,"*) return 0
        esac
        [ "$2" = on ] && val=Y || val=N
    else
        val=Y
    fi
    f=/sys/module/overlay/parameters/$1
    [ -e "$f" ] && [ "$(cat "$f")" = "$val" ]
}
try_ovl_opt() {
    # returns 0 iff option is/gets enabled
    case ",$ovl_opts," in
        *",$1=off,"*) return 1;;
        *",$1[=,]"*) return 0
    esac
    if chk_ovl_opt "$1"; then
        logv 'skipping %s' "$1${2+=$2}"
        return
    fi
    logv 'trying %s' "$1${2+=$2}"
    new_ovl_opts="$ovl_opts,$1${2+=$2}"
    logv "mount -n -t overlay -o '$new_ovl_opts' overlay '$tmpmnt'"
    if ! mount -n -t overlay -o "$new_ovl_opts" overlay "$tmpmnt" 2>/dev/null; then
        [ -z "$verbose" ] || echo rejected >&2
        return
    fi
    cmd umount "$tmpmnt" || die
    # clear out workdir/work/incompat/volatile and upperdir index
    cmd rm -r "$workdir" "$upperdir" || die
    cmd mkdir "$upperdir" "$workdir" || die
    ovl_opts="$new_ovl_opts"
}
try_ovl_opt index on
# redirect_dir and metacopy are unsafe with untrusted non-bottom layers
# nfs_export conflicts with metacopy
[ "${lowerdir#*:}" = "$lowerdir" ] && \
    ! chk_ovl_opt userxattr on && \
    try_ovl_opt redirect_dir on && \
    { chk_ovl_opt nfs_export on || try_ovl_opt metacopy on; }
try_ovl_opt volatile

logv 'copying lowerdir owner/perms to upperdir'
lastlowerdir=${lowerdir##*:}
# stat -c isn't posix, but ls is
ls=$(ls -dn "$lastlowerdir/.") || die
[ -n "$ls" ] || die 'empty ls output'
owner=$(printf '%s\n' "$ls" | sed -e 's/^[^ ]* [^ ]* \([^ ]*\) \([^ ]*\).*$/\1:\2/;t;d')
[ -n "$owner" ] || die 'bad ls owner output'
mode=$(printf '%s\n' "$ls" | sed -e 's/^d\(...\)\(...\)\(...\).*/u=\1,g=\2,o=\3/;s/-//g;t;d')
[ -n "$mode" ] || die 'bad ls mode output'
if ! cmd chown "$owner" "$upperdir"; then
    # int sysctl can't be read by read
    [ "$owner" = "$(dd if=/proc/sys/fs/overflowuid bs=16 status=none):$(dd if=/proc/sys/fs/overflowgid bs=16 status=none)" ] || die
    read uid_old uid_new uid_cnt < /proc/self/uid_map
    [ "$uid_old $uid_new" != "0 0" ] || die
    log 'detected user namespace, ignoring chown failure'
fi
cmd chmod "$mode" "$upperdir" || die
# -m - covers ACLs (system.posix_acl_access) and file caps
# (security.capability). theoretically someone might have get/setcap and/or
# get/setfacl but not get/setxattr, but this is unlikely since libcap/acl
# require attr.
logv 'copying root xattrs'
if attrs=$(cd "$lastlowerdir" && getfattr -d -m - . 2>/dev/null); then
    if [ -n "$attrs" ]; then
        printf '%s\n' "$attrs" | (cd "$upperdir"; setfattr --restore=-) || die
    fi
else
    log 'getfattr failed, skipping xattrs/ACLs'
fi

logv 'mounting overlay'
# shellcheck disable=SC2086
cmd mount $no_canon $no_mtab $verbose -t overlay -o "$ovl_opts" "${mount_name-overlay}" "$dest" || die
exec 9>&-
wait || die
logv 'done'

#!/usr/bin/env python3
"""Collect the gta4l parts of a working postmarketOS rootfs for an Arch Linux ARM rootfs.

Usage (as root): gta4l-overlay.py <pmos-root> <stage-dir> <apk>... -- <package>...

Copies the files of the given postmarketOS packages (from the apk database of
<pmos-root>) and the contents of the given .apk files into <stage-dir>, with
/lib, /bin and /sbin folded into /usr. postmarketOS is built against musl, Arch
against glibc: musl programs are moved to /usr/lib/gta4l-musl together with
every musl library they need and the musl loader, and a small wrapper takes
their place, so they run unchanged next to the glibc system.
"""
import os
import shutil
import stat
import struct
import sys
import tarfile

MUSL = '/usr/lib/gta4l-musl'
SKIP_PREFIXES = ('/boot/', '/etc/pam.d/', '/usr/share/mkinitfs/', '/etc/apk/',
                 '/usr/lib/apk/', '/lib/apk/')


def norm(path):
    for old, new in (('/lib/', '/usr/lib/'), ('/bin/', '/usr/bin/'),
                     ('/sbin/', '/usr/bin/'), ('/usr/sbin/', '/usr/bin/')):
        if path.startswith(old):
            return new + path[len(old):]
    return path


def elf_info(path):
    """(is_aarch64, interpreter, needed, soname) or None."""
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError:
        return None
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        return None
    e_machine = struct.unpack_from('<H', data, 18)[0]
    if e_machine != 183:
        return (False, None, [], None)
    phoff, = struct.unpack_from('<Q', data, 32)
    phentsize, phnum = struct.unpack_from('<HH', data, 54)
    interp, dyn, loads = None, None, []
    for i in range(phnum):
        o = phoff + i * phentsize
        p_type, _, p_offset, p_vaddr, _, p_filesz = struct.unpack_from('<IIQQQQ', data, o)
        if p_type == 3:
            interp = data[p_offset:p_offset + p_filesz].rstrip(b'\0').decode()
        elif p_type == 2:
            dyn = (p_offset, p_filesz)
        elif p_type == 1:
            loads.append((p_vaddr, p_offset, p_filesz))
    needed, soname = [], None
    if dyn:
        entries, strtab = [], None
        for o in range(dyn[0], dyn[0] + dyn[1], 16):
            tag, val = struct.unpack_from('<qQ', data, o)
            if tag == 0:
                break
            if tag == 5:
                strtab = val
            entries.append((tag, val))
        if strtab is not None:
            for vaddr, off, size in loads:
                if vaddr <= strtab < vaddr + size:
                    stroff = strtab - vaddr + off
                    break
            else:
                stroff = strtab

            def s(v):
                return data[stroff + v:data.index(b'\0', stroff + v)].decode()
            needed = [s(v) for t, v in entries if t == 1]
            soname = next((s(v) for t, v in entries if t == 14), None)
    return (True, interp, needed, soname)


def packages(root, wanted):
    db = open(os.path.join(root, 'lib/apk/db/installed')).read().split('\n\n')
    files = []
    for blk in db:
        lines = blk.splitlines()
        name = next((l[2:] for l in lines if l.startswith('P:')), None)
        if name not in wanted:
            continue
        d = ''
        for l in lines:
            if l.startswith('F:'):
                d = l[2:]
            elif l.startswith('R:'):
                files.append(f'/{d}/{l[2:]}')
    return files


def put(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.lexists(dst):
        os.remove(dst)
    if os.path.islink(src):
        os.symlink(os.readlink(src), dst)
    else:
        shutil.copy2(src, dst)


def main():
    root, stage = sys.argv[1], sys.argv[2]
    sep = sys.argv.index('--')
    apks, wanted = sys.argv[3:sep], set(sys.argv[sep + 1:])

    for f in packages(root, wanted):
        if f.startswith(SKIP_PREFIXES):
            continue
        src = root + f
        if os.path.lexists(src):
            put(src, stage + norm(f))

    for apk in apks:
        with tarfile.open(apk) as t:
            for m in t.getmembers():
                if m.name.startswith('.') or m.isdir():
                    continue
                f = '/' + m.name
                if f.startswith(SKIP_PREFIXES):
                    continue
                m.name = norm(f).lstrip('/')
                t.extract(m, stage, filter='fully_trusted')

    # Move musl programs and libraries aside and wrap the programs.
    musl_dir = stage + MUSL
    os.makedirs(musl_dir + '/bin', exist_ok=True)
    pending = set()
    for dirpath, _, names in os.walk(stage):
        if dirpath.startswith(musl_dir) or '/firmware' in dirpath or '/share/qcom' in dirpath \
                or '/lib/modules' in dirpath:
            continue
        for n in names:
            p = os.path.join(dirpath, n)
            if os.path.islink(p):
                continue
            info = elf_info(p)
            if not info or not info[0]:
                continue
            _, interp, needed, soname = info
            pending.update(needed)
            rel = p[len(stage):]
            if interp:
                if 'musl' not in interp:
                    continue
                shutil.move(p, f'{musl_dir}/bin/{n}')
                with open(p, 'w') as w:
                    w.write('#!/bin/sh\n# musl program from postmarketOS, see gta4l-overlay.py\n'
                            f'exec {MUSL}/ld-musl-aarch64.so.1 --library-path {MUSL} '
                            f'{MUSL}/bin/{n} "$@"\n')
                os.chmod(p, 0o755)
                print('wrapped', rel)
            elif rel.startswith('/usr/lib/'):
                shutil.move(p, f'{musl_dir}/{n}')
                if soname and soname != n:
                    put_link = f'{musl_dir}/{soname}'
                    if not os.path.lexists(put_link):
                        os.symlink(n, put_link)
                print('moved lib', rel)
    # Drop the now dangling library symlinks left at the old place.
    for dirpath, _, names in os.walk(stage + '/usr/lib'):
        if dirpath.startswith(musl_dir):
            continue
        for n in names:
            p = os.path.join(dirpath, n)
            if os.path.islink(p) and not os.path.exists(p) and '.so' in n:
                os.remove(p)

    # Pull in every musl library the moved files need, from the pmOS rootfs.
    search = [root + '/usr/lib', root + '/lib']
    done = set(os.listdir(musl_dir))
    while pending:
        lib = pending.pop()
        if lib in done or lib.startswith('libc.musl'):
            continue
        for d in search:
            src = os.path.join(d, lib)
            if os.path.exists(src):
                real = os.path.realpath(src)
                shutil.copy2(real, os.path.join(musl_dir, lib))
                done.add(lib)
                info = elf_info(real)
                if info:
                    pending.update(info[2])
                print('musl dep', lib)
                break
        else:
            print('WARNING: musl library not found:', lib)
    ld = os.path.realpath(root + '/lib/ld-musl-aarch64.so.1')
    shutil.copy2(ld, musl_dir + '/ld-musl-aarch64.so.1')
    if not os.path.lexists(musl_dir + '/libc.musl-aarch64.so.1'):
        os.symlink('ld-musl-aarch64.so.1', musl_dir + '/libc.musl-aarch64.so.1')


if __name__ == '__main__':
    main()

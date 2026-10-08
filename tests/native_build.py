"""Compile the production C code for ctypes on POSIX or Windows.

Windows: set CC to a portable zig.exe, or use an x64 Native Tools command
prompt with CC=cl and the Windows SDK installed. POSIX defaults to clang.
No prebuilt binary or Python implementation substitutes for the C code.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys


def build_library(directory, name, source, exports):
    directory = Path(directory)
    compiler = os.environ.get('CC', 'cl' if sys.platform == 'win32' else 'clang')
    cc = [compiler] if Path(compiler).is_file() else shlex.split(compiler)
    msvc = Path(cc[0]).name.lower() in ('cl', 'cl.exe')
    zig = Path(cc[0]).name.lower() in ('zig', 'zig.exe')
    if zig and len(cc) == 1:
        cc.append('cc')
    suffix = '.dll' if sys.platform == 'win32' else '.dylib' if sys.platform == 'darwin' else '.so'
    library = directory / (name + suffix)
    if msvc:
        command = cc + ['/nologo', '/std:c11', '/W3', '/WX', '/wd4244', '/O2',
                   '/D_CRT_SECURE_NO_WARNINGS', '/LD', str(source),
                   '/Fo' + str(directory / (name + '.obj')), '/link',
                   '/OUT:' + str(library), '/IMPLIB:' + str(directory / (name + '.lib'))]
        command.extend('/EXPORT:' + symbol for symbol in exports)
    else:
        command = cc + ['-std=c11', '-D_POSIX_C_SOURCE=200809L',
                   '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC', '-O2',
                   str(source), '-o', str(library)]
        if zig and sys.platform == 'win32':
            command.extend(['-target', 'x86_64-windows-gnu', '-Wl,--export-all-symbols'])
    subprocess.run(command, cwd=directory, check=True)
    return library


def unload_library(library):
    # Windows locks a loaded DLL. Explicit release lets TemporaryDirectory clean
    # up after the last test, with no lingering binaries in the user workspace.
    if sys.platform == 'win32':
        import _ctypes
        _ctypes.FreeLibrary(library._handle)

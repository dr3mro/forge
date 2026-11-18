"""Restart Forge build-and-run when workspace build inputs change."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import time


IGNORED_DIRECTORIES = {".forge", ".git", ".hg", ".svn", "target"}
INPUT_SUFFIXES = {
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".inl", ".ipp",
    ".cppm", ".ixx", ".s", ".asm", ".cmake", ".in",
}
INPUT_NAMES = {
    "Forge.toml", "CMakeLists.txt", "CMakePresets.json", "CMakeUserPresets.json",
    "conanfile.txt", "conan.lock", "vcpkg.json", "vcpkg-configuration.json",
}


def snapshot(root):
    files = {}
    for directory, children, names in os.walk(root):
        children[:] = [name for name in children if name not in IGNORED_DIRECTORIES]
        for name in names:
            path = Path(directory) / name
            if name not in INPUT_NAMES and path.suffix.lower() not in INPUT_SUFFIXES:
                continue
            try:
                stat = path.stat()
            except FileNotFoundError:
                continue
            files[path] = (stat.st_mtime_ns, stat.st_size, stat.st_ino)
    return files


def signal_child(child, sig):
    """Signal the child's process group, falling back to the child itself.

    Some macOS runners reject killpg for a reparented or already-reaped group
    with EPERM. Signaling the tracked process directly is still permitted and
    keeps the watcher alive instead of crashing on a source change.
    """
    try:
        os.killpg(child.pid, sig)
    except ProcessLookupError:
        return
    except PermissionError:
        try:
            child.send_signal(sig)
        except ProcessLookupError:
            pass


def stop(child):
    if child.poll() is not None:
        return
    signal_child(child, signal.SIGTERM)
    try:
        child.wait(timeout=3)
    except subprocess.TimeoutExpired:
        signal_child(child, signal.SIGKILL)
        child.wait()


def terminate(_signal, _frame):
    raise SystemExit(143)


def watch(root, command):
    signal.signal(signal.SIGTERM, terminate)
    previous = snapshot(root)
    child = None
    try:
        child = subprocess.Popen(command, start_new_session=True, stdin=subprocess.DEVNULL)
        while True:
            time.sleep(0.25)
            current = snapshot(root)
            if current != previous:
                previous = current
                stop(child)
                child = subprocess.Popen(command, start_new_session=True, stdin=subprocess.DEVNULL)
            else:
                child.poll()
    except KeyboardInterrupt:
        return 130
    finally:
        if child is not None:
            stop(child)


if __name__ == "__main__":
    sys.exit(watch(Path(sys.argv[1]), sys.argv[2:]))

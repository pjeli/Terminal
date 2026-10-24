"""The harness expects the addon at ./Terminal relative to the working directory.
Make a scratch directory with a Terminal -> repo symlink and work from there."""
import os, tempfile, atexit, shutil, locale

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def enter():
    # (Windows: Python sets LC_CTYPE to the system's code page, and Lua's string.lower then folds UTF-8 bytes as
    # Latin-1 letters, garbling every accented name; the game runs Lua in the C locale)
    locale.setlocale(locale.LC_CTYPE, "C")
    work = tempfile.mkdtemp(prefix="terminal-tests-")
    os.symlink(REPO, os.path.join(work, "Terminal"))
    os.chdir(work)
    atexit.register(_cleanup, work) # (the scratch directory went when the run ended, not left in /tmp)
    return REPO

def _cleanup(work):
    os.chdir(REPO) # (a removed working directory can't be left as the current one)
    shutil.rmtree(work, ignore_errors=True)

"""The harness expects the addon at ./Terminal relative to the working directory.
Make a scratch directory with a Terminal -> repo symlink and work from there."""
import os, tempfile, atexit, shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def enter():
    work = tempfile.mkdtemp(prefix="terminal-tests-")
    os.symlink(REPO, os.path.join(work, "Terminal"))
    os.chdir(work)
    atexit.register(_cleanup, work) # (the scratch directory went when the run ended, not left in /tmp)
    return REPO

def _cleanup(work):
    os.chdir(REPO) # (a removed working directory can't be left as the current one)
    shutil.rmtree(work, ignore_errors=True)

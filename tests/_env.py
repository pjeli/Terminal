"""The harness expects the addon at ./Terminal relative to the working directory.
Make a scratch directory with a Terminal -> repo symlink and work from there."""
import os, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def enter():
    work = tempfile.mkdtemp(prefix="terminal-tests-")
    os.symlink(REPO, os.path.join(work, "Terminal"))
    os.chdir(work)
    return REPO

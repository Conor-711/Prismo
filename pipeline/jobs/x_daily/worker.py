"""Isolated process so legacy module-global DB engines use the chosen database."""
import json
import sys
from pathlib import Path

from . import _process


if __name__ == "__main__":
    state_path = Path(sys.argv[1])
    _process(json.loads(state_path.read_text()), state_path, Path(sys.argv[2]),
             state_path.parent, int(sys.argv[3]), int(sys.argv[4]))

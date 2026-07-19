#!/usr/bin/env python3
from __future__ import annotations
import argparse, shutil
from pathlib import Path
def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument("target", type=Path); p.add_argument("--replace", action="store_true"); a=p.parse_args()
    source=Path(__file__).resolve().parent.parent/"skills"; target=a.target.expanduser().resolve(); target.mkdir(parents=True, exist_ok=True)
    for skill in sorted(source.iterdir()):
        if not skill.is_dir(): continue
        dest=target/skill.name
        if dest.exists():
            if not a.replace: raise SystemExit(f"target exists: {dest}")
            shutil.rmtree(dest)
        shutil.copytree(skill,dest)
    print(f"installed skills into {target}"); return 0
if __name__=="__main__": raise SystemExit(main())

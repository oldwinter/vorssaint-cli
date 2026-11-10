#!/usr/bin/env python3
"""Check source provenance, run actual-source replays, then check finite TLA+ models."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.request

from replay import replay

ROOT = Path(__file__).resolve().parent.parent
JAR_SHA = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
JAR_URL = "https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar"


def toolchain() -> tuple[str, Path]:
    cache = Path.home() / ".cache/vorssaint-formal/tlc-1.7.4"
    jar = Path(os.environ.get("TLA2TOOLS", str(cache / "tla2tools.jar")))
    if not jar.exists():
        if os.environ.get("TLA2TOOLS"):
            raise RuntimeError(f"TLA2TOOLS does not exist: {jar}")
        cache.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(JAR_URL, timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != JAR_SHA:
            raise RuntimeError("downloaded TLC jar checksum mismatch")
        cache.joinpath("tla2tools.jar").write_bytes(data)
        jar = cache / "tla2tools.jar"
    if hashlib.sha256(jar.read_bytes()).hexdigest() != JAR_SHA:
        raise RuntimeError(f"TLC jar checksum mismatch: {jar}")
    java = os.environ.get("JAVA", shutil.which("java") or "")
    if java and subprocess.run([java, "-version"], capture_output=True, timeout=15).returncode and shutil.which("mise"):
        found = subprocess.run(
            ["mise", "which", "java", "--tool", "java@temurin-25.0.5+8.0.LTS"],
            capture_output=True, text=True,
        )
        java = found.stdout.strip() if found.returncode == 0 else ""
    if not java:
        raise RuntimeError("Java 11+ is required; set JAVA or run mise install java@temurin-25.0.5+8.0.LTS")
    return java, jar


def tlc(java: str, jar: Path, model: str, config: Path, folder: Path) -> dict:
    folder.mkdir()
    shutil.copy(ROOT / "formal/models" / f"{model}.tla", folder)
    shutil.copy(config, folder / f"{model}.cfg")
    result = subprocess.run(
        [java, "-XX:+UseParallelGC", "-cp", str(jar), "tlc2.TLC", "-workers", "1",
         "-seed", "1", "-config", f"{model}.cfg", model],
        cwd=folder, capture_output=True, text=True, timeout=90,
    )
    text = result.stdout + result.stderr
    (folder / "tlc.out").write_text(text)
    if result.returncode == 0 and "No error has been found" in text:
        return {"status": "pass"}
    if result.returncode in (11, 12, 13) and (
        "is violated" in text or "Temporal properties were violated" in text
    ):
        return {"status": "finding", "log": str(folder / "tlc.out")}
    raise RuntimeError(f"TLC infrastructure/model error ({result.returncode}): {folder / 'tlc.out'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subsystem", help="one key from formal/coverage.json")
    parser.add_argument("--mutations", action="store_true", help="also replay scratch Swift regressions")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "formal/coverage.json").read_text())
    entries = manifest["subsystems"]
    if args.subsystem:
        if args.subsystem not in entries:
            parser.error(f"unknown subsystem: {args.subsystem}")
        entries = {args.subsystem: entries[args.subsystem]}
    scratch = Path(tempfile.mkdtemp(prefix="vorssaint-formal-"))
    print(f"Receipts: {scratch}", flush=True)
    summary = {}
    try:
        java, jar = toolchain()
        for name, entry in entries.items():
            for path, expected in entry["source_hashes"].items():
                actual = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                if actual != expected:
                    raise RuntimeError(f"{name}: source drift in {path}; review model and sync record")
            replay_result = replay(ROOT, scratch, name, args.mutations)
            models = {}
            for model in entry["models"]:
                # Check each invariant separately so one known finding cannot mask another.
                cfg = (ROOT / "formal/models" / f"{model}.cfg").read_text()
                rules = [line.split()[1] for line in cfg.splitlines()
                         if line.startswith(("INVARIANT ", "PROPERTY "))]
                for rule in rules:
                    selected = "\n".join(line for line in cfg.splitlines()
                                         if not line.startswith(("INVARIANT ", "PROPERTY "))
                                         or line.split()[1] == rule) + "\n"
                    config = scratch / f"{model}-{rule}.cfg"
                    config.write_text(selected)
                    result = tlc(java, jar, model, config, scratch / f"{model}-{rule}")
                    expected = "finding" if rule in entry["findings"] else "pass"
                    if result["status"] != expected:
                        raise RuntimeError(f"{model}.{rule}: expected {expected}, got {result['status']}")
                    models[f"{model}.{rule}"] = result
                if args.mutations:
                    rule = entry["mutation_rule"]
                    selected = "\n".join(
                        line.replace("Mutation = FALSE", "Mutation = TRUE")
                        for line in cfg.splitlines()
                        if not line.startswith(("INVARIANT ", "PROPERTY ")) or line.split()[1] == rule
                    ) + "\n"
                    config = scratch / f"{model}-mutation.cfg"
                    config.write_text(selected)
                    result = tlc(java, jar, model, config, scratch / f"{model}-mutation")
                    if result["status"] != "finding":
                        raise RuntimeError(f"{model}: model mutation did not break {rule}")
            summary[name] = {"replay": replay_result, "checks": models}
            print(f"{name}: {sum(v['status'] == 'finding' for v in models.values())} findings; "
                  f"{len(models)} rules checked; source replay passed", flush=True)
        (scratch / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        return 1 if any(v["status"] == "finding" for s in summary.values()
                        for v in s["checks"].values()) else 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

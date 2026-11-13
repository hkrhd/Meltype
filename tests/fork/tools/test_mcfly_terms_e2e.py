"""McFlyの代わりに合成JSONを返し、公開CLIの出力だけを検証する。

python3 tests/fork/tools/test_mcfly_terms_e2e.py
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

collector = Path(__file__).resolve().parents[3] / "tools/mcfly-terms.py"
with tempfile.TemporaryDirectory(prefix="mcfly-terms-e2e-") as directory:
    root = Path(directory)
    binary = root / "mcfly"
    binary.write_text('#!/bin/sh\ncat "$MCFLY_TEST_OUTPUT"\n', encoding="utf-8")
    binary.chmod(0o700)
    fixture = root / "fixture.json"
    commands = [
        "jj bookmark list --revision=@ --dry-run --dry-run",
        "jj bookmark list --revision=@ --dry-run",
        "jj bookmark list --revision=@ --dry-run",
        'git commit -m "--fixturetext"',
        'git commit -m "--fixturetext"',
        'git commit -m "--fixturetext"',
        "rg --ignore-case -- example.txt",
        "rg --ignore-case -- example.txt",
        "rg --ignore-case -- example.txt",
        'print "$(touch sentinel)"',
    ]
    fixture.write_text(
        json.dumps([{"cmd": command, "when_run": "fixture-date"} for command in commands]),
        encoding="utf-8",
    )
    environment = {
        **os.environ,
        "PATH": str(root) + os.pathsep + os.environ["PATH"],
        "MCFLY_TEST_OUTPUT": str(fixture),
    }
    # 実行環境の自作コマンド定義に左右されないよう、空のディレクトリを指定する。
    options = ["--min-count", "3", "--shell-dir", str(root / "shell")]
    result = subprocess.run(
        [sys.executable, str(collector), *options],
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert {
        "jj",
        "bookmark",
        "list",
        "revision",
        "dry",
        "run",
        "git",
        "commit",
        "rg",
        "ignore",
        "case",
    } <= set(payload["words"])
    for excluded in ["fixturetext", "example.txt", "fixture-date", "sentinel"]:
        assert excluded not in result.stdout, excluded
    options_by_token = {
        item["token"]: item["count"] for item in payload["candidates"] if item["kind"] == "option"
    }
    assert options_by_token["--dry-run"] == 3
    assert payload["complex_entries_excluded"] == 1
    assert not Path("sentinel").exists()
    fixture.write_text("invalid JSON with fixturetext", encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(collector)],
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 1
    assert "fixturetext" not in result.stdout + result.stderr
    fixture.write_text("McFly: No history\n", encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(collector)],
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["words"] == []

print("McFly語彙集計のE2E: PASS（頻度・値の除外・非実行・異常出力・空DB）")

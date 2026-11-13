#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 hkrhd
"""McFlyを内部で読み、履歴本文を出さずにコマンド・オプションの頻度を返す。

dictionaries/english.txt や利用者の英語辞書へ足す語を探すための補助。
履歴本文は出力しないが、コマンド名やオプション名に機密情報が含まれる場合がある。
抽出は簡易解析なので、引数が誤って候補に混ざる可能性もある。公開前に結果を確認する。
自作コマンドの宣言は --shell-dir (既定: ~/.config/zfunc) と ~/.zshrc から名前だけ読む。

  python3 tools/mcfly-terms.py --min-count 3
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

WORD = re.compile(r"[a-z]{2,}\Z")
NAME = re.compile(r"[A-Za-z][A-Za-z0-9_.+-]*\Z")
OPTION = re.compile(r"-{1,2}[A-Za-z][A-Za-z0-9_:-]*(?:=.*)?\Z")
WRAPPERS = {"sudo", "doas", "env", "command", "builtin", "nohup", "time"}
SEPARATORS = {";", "&&", "||", "|", "|&", "&", "\n", "(", ")", "{", "}"}
CONTROLS = {"if", "then", "elif", "else", "fi", "while", "until", "do", "done", "!"}

# サブコマンドと引数を混同しないため、既知のCLI文法に限定する。
SUBCOMMANDS = {
    "jj": "abandon absorb backout bookmark branch commit config describe diff duplicate edit evolog file fix git help interdiff log new next op parallelize prev rebase resolve restore revert root show simplify-parents sparse split squash status undo util workspace",
    "git": "add am apply archive bisect blame branch bundle checkout cherry-pick clean clone commit config describe diff fetch format-patch fsck gc grep help init log merge mv notes pull push range-diff rebase reflog remote reset restore revert rm show sparse-checkout stash status submodule switch tag worktree",
    "uv": "add auth build cache export help init lock pip publish python remove run self sync tool tree venv version",
    "pnpm": "add approve-builds audit bin build cache config create deploy dlx env exec fetch help import init install link list outdated patch patch-commit prune publish rebuild remove run setup start store test unlink update why",
    "bun": "add build create init install link outdated pm publish remove run test unlink update upgrade x",
    "gh": "alias api auth browse cache codespace completion config extension gist gpg-key issue label org pr project release repo ruleset run search secret ssh-key status variable workflow",
    "docker": "attach build builder buildx compose container context cp create diff events exec export history image images info inspect kill load login logout logs network node pause plugin port ps pull push rename restart rm rmi run save search secret service stack start stats stop swarm system tag top trust unpause update version volume wait",
    "podman": "build compose container exec image images info inspect kube logs machine network pod ps pull push rm rmi run start stop system volume",
    "kubectl": "annotate api-resources api-versions apply attach auth autoscale certificate cluster-info completion config cordon cp create debug delete describe diff drain edit exec explain expose get kustomize label logs patch plugin port-forward proxy replace rollout run scale set taint top uncordon version wait",
    "brew": "analytics autoremove bundle cleanup commands config deps desc doctor edit fetch help home info install leaves link list livecheck log missing options outdated pin postinstall reinstall search services shellenv tap uninstall unlink unpin untap update upgrade uses",
    "systemctl": "cat daemon-reexec daemon-reload disable edit enable help is-active is-enabled is-failed kill list-dependencies list-jobs list-sockets list-timers list-unit-files list-units mask reboot reload reload-or-restart reset-failed restart show start status stop unmask",
    "dinitctl": "enable disable list reload restart signal start status stop unpin wake",
    "tmux": "attach attach-session capture-pane display-message has-session kill-pane kill-session kill-window list-clients list-panes list-sessions list-windows new new-session new-window rename-session resize-pane select-pane select-window send-keys set set-option source-file split-window switch-client",
    "zellij": "action attach convert-config delete-all-sessions delete-session edit list-sessions options run setup",
    "agent-browser": "open snapshot click fill type press scroll screenshot get wait eval close tabs tab",
}
CHILDREN = {
    ("jj", "bookmark"): "create delete forget list move rename set track untrack",
    ("jj", "git"): "clone export fetch import init push remote",
    ("jj", "config"): "edit get list path set unset",
    ("jj", "op"): "abandon diff log restore show undo",
    ("jj", "file"): "annotate chmod list show track untrack",
    ("jj", "workspace"): "add forget list root update-stale",
    ("jj", "util"): "completion exec gc install-man-pages mangen",
    ("uv", "tool"): "dir install list run uninstall update-shell upgrade",
    ("uv", "python"): "dir find install list pin uninstall update-shell upgrade",
    ("uv", "pip"): "check compile freeze install list show sync tree uninstall",
    ("uv", "cache"): "clean dir prune size",
    ("git", "stash"): "apply branch clear create drop list pop push show store",
    ("git", "remote"): "add get-url prune remove rename set-head set-url show update",
    ("git", "worktree"): "add list lock move prune remove repair unlock",
    (
        "gh",
        "pr",
    ): "checkout checks close comment create diff edit list lock merge ready reopen review status unlock view",
    (
        "gh",
        "issue",
    ): "close comment create delete develop edit list lock pin reopen status transfer unlock unpin view",
    (
        "gh",
        "repo",
    ): "archive clone create delete deploy-key edit fork list rename set-default sync unarchive view",
    ("gh", "run"): "cancel delete download list rerun view watch",
    ("gh", "auth"): "login logout refresh setup-git status switch token",
    (
        "docker",
        "compose",
    ): "build config cp create down events exec images kill logs ls pause port ps pull push restart rm run start stats stop top unpause up version wait watch",
    (
        "docker",
        "image",
    ): "build history import inspect load ls prune pull push rm save tag",
    ("brew", "services"): "cleanup info kill list restart run start stop",
    ("pnpm", "store"): "add path prune status",
}
VALUE_OPTIONS = {
    "--color",
    "--config",
    "--config-file",
    "--cwd",
    "--directory",
    "--project",
    "--repository",
    "--repo",
    "--revision",
    "--namespace",
    "--context",
    "--profile",
    "--host",
    "--format",
    "--output",
    "--message",
    "--query",
    "--filter",
    "--header",
    "--data",
    "--data-raw",
    "--data-binary",
    "--form",
    "--execute",
    "--password",
    "--token",
    "--api-key",
    "--secret",
    "-C",
    "-c",
    "-R",
    "-r",
    "-n",
    "-m",
    "-H",
    "-d",
    "-F",
    "-e",
    "-u",
    "-p",
}


def database_path():
    legacy = Path.home() / ".mcfly"
    if legacy.is_dir():
        return legacy / "history.db"
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/McFly/history.db"
    if sys.platform.startswith("linux"):
        # Linux/WSLではMcFlyのProjectDirsと同じXDGデータディレクトリを使う。
        data_home = (
            Path(os.environ["XDG_DATA_HOME"])
            if "XDG_DATA_HOME" in os.environ
            else Path.home() / ".local/share"
        )
        return data_home / "mcfly/history.db"
    raise RuntimeError("このOSのMcFlyデータ配置には対応していません。")


def command_names(shell_dir):
    # 設定をsourceせず、宣言名だけ読む。エイリアス値は結果へ含めない。
    names = set(SUBCOMMANDS) | WRAPPERS | {"z", "zi"}
    for file in shell_dir.rglob("*"):
        if file.is_file() and NAME.fullmatch(file.name):
            names.add(file.name)
    files = list(shell_dir.rglob("*.zsh")) + [Path.home() / ".zshrc"]
    declaration = re.compile(
        r"(?:\bfunction\s+|^\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)|^\s*alias\s+(?:-[gs]\s+)?([A-Za-z_][A-Za-z0-9_-]*)=",
        re.MULTILINE,
    )
    for file in files:
        if file.is_file():
            for match in declaration.finditer(file.read_text(encoding="utf-8")):
                names.add(match[1] or match[2])
    proc = subprocess.run(
        ["zsh", "-f", "-c", "print -rl -- ${(k)builtins}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode:
        raise RuntimeError("シェルのコマンド名を確認できませんでした。")
    names.update(proc.stdout.splitlines())
    return names


def tokenize(records):
    # (z)は字句解析、(Q)は引用符の除去だけを行う。eval/sourceしない。
    program = r"""while IFS= read -r -d '' entry; do
      tokens=( ${(z)entry} )
      for token in "${tokens[@]}"; do
        print -rn -- "$token"$'\0'"${(Q)token}"$'\0'
      done
      print -rn -- $'\0'
    done"""
    proc = subprocess.run(
        ["zsh", "-f", "-c", program],
        input="\0".join(records) + "\0",
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode:
        raise RuntimeError("zshでの字句解析に失敗しました。履歴本文は表示しません。")
    fields = iter(proc.stdout.split("\0"))
    groups, group = [], []
    for raw in fields:
        if not raw:
            groups.append(group)
            group = []
        else:
            group.append((raw, next(fields)))
    return groups[: len(records)]


def english_parts(token):
    return sorted(set(re.findall(r"[a-z]{2,}", token.lower())))


def extract(tokens, shell_commands):
    found = set()
    command, chain, expect_command, option_value, options_ended = (
        None,
        (),
        True,
        False,
        False,
    )
    for raw, value in tokens:
        if raw.startswith("#"):
            break
        if raw in SEPARATORS or raw in CONTROLS:
            command, chain, expect_command, option_value, options_ended = (
                None,
                (),
                True,
                False,
                False,
            )
            continue
        if raw.startswith((">", "<")):
            option_value = True
            continue
        if option_value:
            option_value = False
            continue
        if expect_command:
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", raw):
                continue
            if value in WRAPPERS:
                found.add(("command", value))
                continue
            if OPTION.fullmatch(value):
                option_value = value in VALUE_OPTIONS
                continue
            name = Path(value).name
            if NAME.fullmatch(name) and (name in shell_commands or shutil.which(value)):
                command, chain = name, (name,)
                found.add(("command", name))
            expect_command = False
            continue
        if not command or options_ended:
            continue
        if value == "--":
            options_ended = True
            continue
        if OPTION.fullmatch(value):
            found.add(("option", value.split("=", 1)[0]))
            option_value = value in VALUE_OPTIONS
            continue
        # 未知のCLI文法は位置引数を誤登録しないよう、子コマンドなしとして扱う。
        if len(chain) == 1:
            children = SUBCOMMANDS.get(
                command, ""
            )  # 未定義CLIの位置引数を誤登録しないため、候補なしを既定値にする。
        else:
            children = CHILDREN.get(chain, "")  # 子コマンド定義がない階層では位置引数を除外する。
        if value in children.split():
            found.add(("subcommand", value))
            chain += (value,)
        else:
            # 最初の位置引数以降をサブコマンドとみなさない。
            chain = ()
    return found


def aggregate(rows, minimum, shell_dir):
    records = [row["cmd"] for row in rows]
    if any(not isinstance(record, str) for record in records):
        raise ValueError("McFlyの出力形式が不正です。")
    simple = [r for r in records if not any(s in r for s in ("<<", "$(", "`", "<(", ">(", "\x00"))]
    counts = Counter()
    names = command_names(shell_dir)
    for group in tokenize(simple):
        counts.update(extract(group, names))
    candidates = [
        {"kind": kind, "token": name, "count": count, "words": english_parts(name)}
        for (kind, name), count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
        if count >= minimum
    ]
    return {
        "source": "mcfly",
        "minimum": minimum,
        "entries": len(records),
        "complex_entries_excluded": len(records) - len(simple),
        "candidates": candidates,
        "words": sorted({word for item in candidates for word in item["words"]}),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-count", type=int, default=3, help="採用する回数の目安（既定: 3）")
    parser.add_argument(
        "--shell-dir",
        type=Path,
        default=Path.home() / ".config/zfunc",
        help="自作コマンドの宣言を探すディレクトリ（既定: ~/.config/zfunc）",
    )
    args = parser.parse_args()
    if args.min_count < 1:
        parser.error("--min-count は1以上にしてください。")
    try:
        if not database_path().is_file():
            raise RuntimeError("McFlyの既存DBがありません。自動取り込みはしません。")
        proc = subprocess.run(
            ["mcfly", "dump", "--format", "json"],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode:
            raise RuntimeError("McFlyの出力を取得できませんでした。")
        # McFlyの空DB時はJSONではなく、この固定メッセージを返す。
        rows = [] if proc.stdout.strip() == "McFly: No history" else json.loads(proc.stdout)
        if not isinstance(rows, list):
            raise TypeError("McFlyの出力形式が不正です。")
        result = aggregate(rows, args.min_count, args.shell_dir)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError):
        # 例外本文・stderrにコマンドや資格情報が混ざるため、それらは出力しない。
        print("McFlyの集計に失敗しました。履歴本文は表示していません。", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

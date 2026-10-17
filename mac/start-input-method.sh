#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 hrmcngs

# Start in the GUI launchd session so terminal teardown cannot stop the IME.
set -euo pipefail
app="${1:?Usage: start-input-method.sh /path/to/Meltype.app}"
label=io.github.yksr-melt.Meltype.manual
log_dir="${MELTYPE_START_LOG_DIR:-$HOME/Library/Logs}"
mkdir -p "$log_dir"
input_server_ready() {
    local job state
    while IFS= read -r job; do
        state="$(launchctl list "$job" 2>/dev/null || true)"
        if [[ "$state" == *'"PID" ='* && "$state" == *'Meltype_Connection'* &&
              "$state" == *"\"$app/Contents/MacOS/Meltype\""* ]]; then
            return 0
        fi
    done < <(launchctl list | awk -v manual="$label" \
        '$1 ~ /^[0-9]+$/ && ($3 == manual || index($3, "application.io.github.yksr-melt.inputmethod.Meltype.") == 1) { print $3 }')
    return 1
}
# 登録後にmacOSが先に起動したサーバーも認識する。二重起動すると接続名の登録に失敗する。
if input_server_ready; then
    echo "Meltype input server is already running."
    exit 0
fi
launchctl remove "$label" 2>/dev/null || true
for attempt in {1..3}; do
    if launchctl submit -l "$label" -o "$log_dir/Meltype.stdout.log" -e "$log_dir/Meltype.stderr.log" -- "$app/Contents/MacOS/Meltype"; then
        for _ in {1..30}; do
            if input_server_ready; then
                echo "Meltype input server is running."
                exit 0
            fi
            sleep 0.2
        done
    fi
    echo "Meltype startup attempt $attempt did not become ready." >&2
    launchctl remove "$label" 2>/dev/null || true
    sleep 0.2
done
echo "Meltype input server did not become ready. Keep the standard input source selected." >&2
exit 1

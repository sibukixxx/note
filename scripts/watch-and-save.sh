#!/bin/bash
#
# Claude Code 会話をObsidianに自動保存するスクリプト
# 参考: https://zenn.dev/pepabo/articles/ffb79b5279f6ee
#

set -euo pipefail

# 設定
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
OUTPUT_DIR="/Users/yuichi.takada/workspace/sibukixxx/note/notes/claude"
STATE_DIR="$HOME/.claude/obsidian-sync"
LOG_FILE="$HOME/.claude/logs/obsidian-sync.log"
INTERVAL=5

# 初期化
mkdir -p "$OUTPUT_DIR" "$STATE_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "スクリプト開始"

# メッセージをMarkdown形式に変換
format_message() {
    local type="$1"
    local content="$2"
    local timestamp="$3"

    # タイムスタンプを日本時間に変換（HH:MM形式）
    local time_str
    time_str=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%.*}" "+%H:%M" 2>/dev/null || echo "")

    case "$type" in
        user)
            echo -e "\n### User [$time_str]\n\n$content\n"
            ;;
        assistant)
            echo -e "\n### Claude [$time_str]\n\n$content\n"
            ;;
    esac
}

# JSONLファイルを処理
process_jsonl() {
    local jsonl_file="$1"
    local state_file="$STATE_DIR/$(basename "$jsonl_file" .jsonl).state"

    # 前回処理した行数を取得
    local last_line=0
    if [[ -f "$state_file" ]]; then
        last_line=$(cat "$state_file")
    fi

    # 現在の行数を取得
    local current_lines
    current_lines=$(wc -l < "$jsonl_file" | tr -d ' ')

    # 新しい行がなければスキップ
    if [[ "$current_lines" -le "$last_line" ]]; then
        return
    fi

    log "処理中: $jsonl_file (行 $((last_line + 1)) から $current_lines)"

    # 新しい行を処理
    tail -n +"$((last_line + 1))" "$jsonl_file" | while IFS= read -r line; do
        # JSONをパース
        local msg_type subtype content timestamp date_str

        msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null)
        timestamp=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null)

        # ノイズをスキップ
        [[ "$msg_type" == "system" ]] && continue
        [[ "$msg_type" == "file-history-snapshot" ]] && continue
        [[ -n "$subtype" && "$subtype" == "local_command" ]] && continue

        # メッセージ内容を取得
        if [[ "$msg_type" == "user" ]]; then
            content=$(echo "$line" | jq -r '.message.content // empty' 2>/dev/null)
            # system-reminderを除去
            content=$(echo "$content" | sed 's/<system-reminder>.*<\/system-reminder>//g')
        elif [[ "$msg_type" == "assistant" ]]; then
            # アシスタントメッセージはcontentの配列から取得
            content=$(echo "$line" | jq -r '
                .message.content // [] |
                map(select(.type == "text") | .text) |
                join("\n")
            ' 2>/dev/null)

            # thinkingブロックを除外したテキストがあるか確認
            if [[ -z "$content" || "$content" == "null" ]]; then
                continue
            fi
        else
            continue
        fi

        # 空のコンテンツはスキップ
        [[ -z "$content" || "$content" == "null" ]] && continue

        # 日付を抽出（YYYY-MM-DD形式）
        date_str=$(echo "$timestamp" | cut -d'T' -f1)
        [[ -z "$date_str" ]] && continue

        # 出力ファイル
        local output_file="$OUTPUT_DIR/${date_str}.md"

        # ファイルが存在しなければヘッダーを追加
        if [[ ! -f "$output_file" ]]; then
            echo "# Claude Code 会話ログ - $date_str" > "$output_file"
            echo "" >> "$output_file"
        fi

        # メッセージを追記
        format_message "$msg_type" "$content" "$timestamp" >> "$output_file"

    done

    # 状態を保存
    echo "$current_lines" > "$state_file"
}

# Git自動コミット
git_commit() {
    cd "$OUTPUT_DIR/.." || return

    if [[ -n $(git status --porcelain "$OUTPUT_DIR" 2>/dev/null) ]]; then
        git add "$OUTPUT_DIR"
        git commit -m "Auto-save Claude Code conversations - $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
        log "Git commit 完了"
    fi
}

# メインループ
main() {
    while true; do
        # すべてのJSONLファイルを処理
        for jsonl_file in "$CLAUDE_PROJECTS_DIR"/*/*.jsonl; do
            [[ -f "$jsonl_file" ]] || continue
            process_jsonl "$jsonl_file"
        done

        # Git コミット（10分ごと）
        if [[ $(($(date +%s) % 600)) -lt $INTERVAL ]]; then
            git_commit
        fi

        sleep "$INTERVAL"
    done
}

# シグナルハンドラ
cleanup() {
    log "スクリプト終了"
    exit 0
}

trap cleanup SIGTERM SIGINT

main

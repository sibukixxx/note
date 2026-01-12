#!/bin/bash
#
# Claude Code → Obsidian 自動同期 インストーラー
#
# 使い方:
#   curl -sL https://raw.githubusercontent.com/YOUR_REPO/main/scripts/install.sh | bash
#   または
#   ./install.sh [保存先ディレクトリ]
#
# 例:
#   ./install.sh ~/obsidian/vault/claude
#   ./install.sh ~/notes/claude-logs
#

set -euo pipefail

# 色付け
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# デフォルト設定
DEFAULT_OUTPUT_DIR="$HOME/Documents/claude-logs"
SCRIPT_DIR="$HOME/.claude/scripts"
PLIST_NAME="com.claude.obsidian-sync"
LOG_DIR="$HOME/.claude/logs"
STATE_DIR="$HOME/.claude/obsidian-sync"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Claude Code → Obsidian 自動同期 インストーラー            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 前提条件チェック
print_step "前提条件をチェック中..."

# macOS チェック
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "このスクリプトは macOS 専用です"
    exit 1
fi
print_success "macOS 確認"

# jq チェック
if ! command -v jq &> /dev/null; then
    print_warning "jq がインストールされていません"
    read -p "Homebrew で jq をインストールしますか? (y/n): " install_jq
    if [[ "$install_jq" == "y" ]]; then
        brew install jq
        print_success "jq インストール完了"
    else
        print_error "jq が必要です: brew install jq"
        exit 1
    fi
else
    print_success "jq 確認: $(jq --version)"
fi

# Git チェック
if ! command -v git &> /dev/null; then
    print_error "Git がインストールされていません"
    exit 1
fi
print_success "git 確認"

echo ""

# 保存先ディレクトリの設定
if [[ -n "${1:-}" ]]; then
    OUTPUT_DIR="$1"
else
    print_step "保存先ディレクトリを設定"
    echo "  会話ログを保存するディレクトリを指定してください。"
    echo "  Obsidian の vault 内のディレクトリを推奨します。"
    echo ""
    read -p "  保存先 [$DEFAULT_OUTPUT_DIR]: " user_input
    OUTPUT_DIR="${user_input:-$DEFAULT_OUTPUT_DIR}"
fi

# パスを絶対パスに変換
OUTPUT_DIR=$(cd "$(dirname "$OUTPUT_DIR")" 2>/dev/null && pwd)/$(basename "$OUTPUT_DIR") || OUTPUT_DIR="$OUTPUT_DIR"

echo ""
print_step "設定確認"
echo "  保存先: $OUTPUT_DIR"
echo ""
read -p "この設定でインストールしますか? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "キャンセルしました"
    exit 0
fi

echo ""

# ディレクトリ作成
print_step "ディレクトリを作成中..."
mkdir -p "$OUTPUT_DIR"
mkdir -p "$SCRIPT_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"
print_success "ディレクトリ作成完了"

# 監視スクリプトを生成
print_step "監視スクリプトを生成中..."

cat > "$SCRIPT_DIR/watch-and-save.sh" << 'SCRIPT_EOF'
#!/bin/bash
#
# Claude Code 会話をObsidianに自動保存するスクリプト
#

set -euo pipefail

# 設定（インストーラーで置換される）
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
OUTPUT_DIR="__OUTPUT_DIR__"
STATE_DIR="$HOME/.claude/obsidian-sync"
LOG_FILE="$HOME/.claude/logs/obsidian-sync.log"
INTERVAL=5
GIT_COMMIT_ENABLED=true
GIT_COMMIT_INTERVAL=600  # 10分

# 初期化
mkdir -p "$OUTPUT_DIR" "$STATE_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "スクリプト開始 (出力先: $OUTPUT_DIR)"

# メッセージをMarkdown形式に変換
format_message() {
    local type="$1"
    local content="$2"
    local timestamp="$3"

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

    local last_line=0
    if [[ -f "$state_file" ]]; then
        last_line=$(cat "$state_file")
    fi

    local current_lines
    current_lines=$(wc -l < "$jsonl_file" | tr -d ' ')

    if [[ "$current_lines" -le "$last_line" ]]; then
        return
    fi

    log "処理中: $jsonl_file (行 $((last_line + 1)) から $current_lines)"

    tail -n +"$((last_line + 1))" "$jsonl_file" | while IFS= read -r line; do
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
            content=$(echo "$content" | sed 's/<system-reminder>.*<\/system-reminder>//g')
        elif [[ "$msg_type" == "assistant" ]]; then
            content=$(echo "$line" | jq -r '
                .message.content // [] |
                map(select(.type == "text") | .text) |
                join("\n")
            ' 2>/dev/null)

            if [[ -z "$content" || "$content" == "null" ]]; then
                continue
            fi
        else
            continue
        fi

        [[ -z "$content" || "$content" == "null" ]] && continue

        date_str=$(echo "$timestamp" | cut -d'T' -f1)
        [[ -z "$date_str" ]] && continue

        local output_file="$OUTPUT_DIR/${date_str}.md"

        if [[ ! -f "$output_file" ]]; then
            echo "# Claude Code 会話ログ - $date_str" > "$output_file"
            echo "" >> "$output_file"
        fi

        format_message "$msg_type" "$content" "$timestamp" >> "$output_file"

    done

    echo "$current_lines" > "$state_file"
}

# Git自動コミット
git_commit() {
    [[ "$GIT_COMMIT_ENABLED" != "true" ]] && return

    cd "$OUTPUT_DIR" 2>/dev/null || return

    # Gitリポジトリ内かチェック
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return
    fi

    if [[ -n $(git status --porcelain . 2>/dev/null) ]]; then
        git add .
        git commit -m "Auto-save Claude Code conversations - $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
        log "Git commit 完了"
    fi
}

# メインループ
main() {
    local last_commit_time=0

    while true; do
        for jsonl_file in "$CLAUDE_PROJECTS_DIR"/*/*.jsonl; do
            [[ -f "$jsonl_file" ]] || continue
            process_jsonl "$jsonl_file"
        done

        # Git コミット（指定間隔ごと）
        local current_time
        current_time=$(date +%s)
        if [[ $((current_time - last_commit_time)) -ge $GIT_COMMIT_INTERVAL ]]; then
            git_commit
            last_commit_time=$current_time
        fi

        sleep "$INTERVAL"
    done
}

cleanup() {
    log "スクリプト終了"
    exit 0
}

trap cleanup SIGTERM SIGINT

main
SCRIPT_EOF

# OUTPUT_DIR を置換
sed -i '' "s|__OUTPUT_DIR__|$OUTPUT_DIR|g" "$SCRIPT_DIR/watch-and-save.sh"
chmod +x "$SCRIPT_DIR/watch-and-save.sh"
print_success "監視スクリプト作成: $SCRIPT_DIR/watch-and-save.sh"

# LaunchAgent plist を生成
print_step "LaunchAgent を設定中..."

cat > "$HOME/Library/LaunchAgents/$PLIST_NAME.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/watch-and-save.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/obsidian-sync-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/obsidian-sync-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
PLIST_EOF

print_success "LaunchAgent 作成: ~/Library/LaunchAgents/$PLIST_NAME.plist"

# 既存のLaunchAgentを停止
if launchctl list | grep -q "$PLIST_NAME"; then
    print_step "既存の LaunchAgent を停止中..."
    launchctl unload "$HOME/Library/LaunchAgents/$PLIST_NAME.plist" 2>/dev/null || true
fi

# LaunchAgent を起動
print_step "LaunchAgent を起動中..."
launchctl load "$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
print_success "LaunchAgent 起動完了"

# 動作確認
sleep 2
if launchctl list | grep -q "$PLIST_NAME"; then
    print_success "LaunchAgent が正常に動作中"
else
    print_warning "LaunchAgent の起動に問題がある可能性があります"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   インストール完了！                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  保存先: $OUTPUT_DIR"
echo ""
echo "  ログ確認:"
echo "    tail -f ~/.claude/logs/obsidian-sync.log"
echo ""
echo "  管理コマンド:"
echo "    停止:   launchctl unload ~/Library/LaunchAgents/$PLIST_NAME.plist"
echo "    再起動: launchctl unload ~/Library/LaunchAgents/$PLIST_NAME.plist && \\"
echo "            launchctl load ~/Library/LaunchAgents/$PLIST_NAME.plist"
echo ""
echo "  アンインストール:"
echo "    launchctl unload ~/Library/LaunchAgents/$PLIST_NAME.plist"
echo "    rm ~/Library/LaunchAgents/$PLIST_NAME.plist"
echo "    rm -rf ~/.claude/scripts ~/.claude/obsidian-sync"
echo ""

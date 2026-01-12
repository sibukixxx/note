# Claude Code → Obsidian 自動同期

Claude Codeとの会話を自動的にMarkdownファイルとして保存し、Obsidianのナレッジベースに統合するシステム。

参考: [Claude Codeの会話をObsidianに自動保存する](https://zenn.dev/pepabo/articles/ffb79b5279f6ee)

## クイックスタート（別プロジェクトで使う場合）

### ワンライナーインストール

```bash
# このリポジトリから直接インストール
curl -sL https://raw.githubusercontent.com/sibukixxx/note/main/scripts/install.sh | bash
```

### ローカルからインストール

```bash
# 1. このリポジトリをクローン（または install.sh をダウンロード）
git clone https://github.com/sibukixxx/note.git
cd note

# 2. インストーラーを実行（対話式）
./scripts/install.sh

# または、保存先を指定して実行
./scripts/install.sh ~/obsidian/vault/claude
./scripts/install.sh ~/Documents/my-claude-logs
```

インストーラーが自動で以下を行います：
- jq のインストール確認
- 監視スクリプトの生成（`~/.claude/scripts/`）
- LaunchAgent の設定・起動
- 必要なディレクトリの作成

## 概要

```
Claude Code セッション
    ↓
~/.claude/projects/*/session.jsonl
    ↓
監視スクリプト（5秒ごと）
    ↓
notes/claude/YYYY-MM-DD.md
    ↓
Git自動コミット（10分ごと）
```

## 特徴

- **ノイズ除去**: `<system-reminder>`、ローカルコマンド出力、システムメッセージを自動フィルタリング
- **日付別整理**: 会話をその日のMarkdownファイルに自動分類
- **LaunchAgent常駐**: macOS起動時に自動開始、常時バックグラウンド監視
- **Git自動コミット**: 変更を定期的に自動コミット
- **追記モード**: クラッシュ時のデータ損失を防止

## ファイル構成

```
scripts/
├── README.md                      # このファイル
├── install.sh                     # 汎用インストーラー（別プロジェクト用）
├── watch-and-save.sh              # 監視・変換スクリプト（このリポジトリ用）
└── com.claude.obsidian-sync.plist # LaunchAgent設定（このリポジトリ用）

notes/claude/
└── YYYY-MM-DD.md                  # 日付別会話ログ

# インストーラー使用時に生成されるファイル
~/.claude/
├── scripts/
│   └── watch-and-save.sh          # 監視スクリプト
├── obsidian-sync/
│   └── *.state                    # 処理済み行数の状態
└── logs/
    ├── obsidian-sync.log          # メインログ
    ├── obsidian-sync-stdout.log   # 標準出力
    └── obsidian-sync-stderr.log   # エラー出力

~/Library/LaunchAgents/
└── com.claude.obsidian-sync.plist # LaunchAgent設定
```

## 前提条件

- macOS
- jq (`brew install jq`)
- Git

## セットアップ

### 1. ディレクトリ作成

```bash
mkdir -p ~/.claude/logs ~/.claude/obsidian-sync
```

### 2. LaunchAgentをインストール

```bash
cp scripts/com.claude.obsidian-sync.plist ~/Library/LaunchAgents/
```

### 3. LaunchAgentを有効化

```bash
launchctl load ~/Library/LaunchAgents/com.claude.obsidian-sync.plist
```

### 4. 動作確認

```bash
# プロセス確認
launchctl list | grep claude

# ログ確認
tail -f ~/.claude/logs/obsidian-sync.log
```

## 管理コマンド

### 停止

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.obsidian-sync.plist
```

### 再起動

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.obsidian-sync.plist
launchctl load ~/Library/LaunchAgents/com.claude.obsidian-sync.plist
```

### ログ確認

```bash
# メインログ
tail -f ~/.claude/logs/obsidian-sync.log

# 標準出力
tail -f ~/.claude/logs/obsidian-sync-stdout.log

# エラー出力
tail -f ~/.claude/logs/obsidian-sync-stderr.log
```

### 手動実行（デバッグ用）

```bash
./scripts/watch-and-save.sh
```

## 出力形式

保存されるMarkdownファイルの形式:

```markdown
# Claude Code 会話ログ - 2026-01-12

### User [11:07]

Claude Codeとの会話、全部Obsidianに自動保存！

### Claude [11:07]

興味深い記事ですね。Claude Codeの会話をObsidianに自動保存する仕組みについての記事を見てみます。
```

## カスタマイズ

### 保存先の変更

`watch-and-save.sh` の `OUTPUT_DIR` を編集:

```bash
OUTPUT_DIR="/path/to/your/obsidian/vault/claude"
```

### 監視間隔の変更

`watch-and-save.sh` の `INTERVAL` を編集:

```bash
INTERVAL=10  # 10秒ごと
```

### Git自動コミットの無効化

`watch-and-save.sh` の `git_commit` 関数呼び出しをコメントアウト:

```bash
# Git コミット（10分ごと）
# if [[ $(($(date +%s) % 600)) -lt $INTERVAL ]]; then
#     git_commit
# fi
```

## トラブルシューティング

### LaunchAgentが起動しない

```bash
# 設定ファイルの構文チェック
plutil -lint ~/Library/LaunchAgents/com.claude.obsidian-sync.plist

# スクリプトの実行権限確認
ls -la scripts/watch-and-save.sh

# 権限付与
chmod +x scripts/watch-and-save.sh
```

### 会話が保存されない

1. セッションファイルの存在確認:
```bash
ls ~/.claude/projects/*/
```

2. jqのインストール確認:
```bash
which jq
```

3. 状態ファイルをリセット（再処理）:
```bash
rm ~/.claude/obsidian-sync/*.state
```

### ログにエラーが出る

エラーログを確認:
```bash
cat ~/.claude/logs/obsidian-sync-stderr.log
```

## アンインストール

### インストーラーで導入した場合

```bash
# LaunchAgentを停止・削除
launchctl unload ~/Library/LaunchAgents/com.claude.obsidian-sync.plist
rm ~/Library/LaunchAgents/com.claude.obsidian-sync.plist

# スクリプトを削除
rm -rf ~/.claude/scripts

# 状態ファイルを削除
rm -rf ~/.claude/obsidian-sync

# ログを削除（オプション）
rm ~/.claude/logs/obsidian-sync*.log
```

### このリポジトリのセットアップを使っている場合

```bash
# LaunchAgentを停止・削除
launchctl unload ~/Library/LaunchAgents/com.claude.obsidian-sync.plist
rm ~/Library/LaunchAgents/com.claude.obsidian-sync.plist

# 状態ファイルを削除（オプション）
rm -rf ~/.claude/obsidian-sync

# ログを削除（オプション）
rm ~/.claude/logs/obsidian-sync*.log
```

## ライセンス

MIT

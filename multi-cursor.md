
```
Devinは心許ないし、Cursor/Windsurf両刀使いはコンフリクトが気になる。

じゃあPC二台使えばええやん。

と、今のび太の顔してる。

同じPC上で同じリポジトリを別でクローンして、それぞれでIDE走らせてPR出したらいいですよ！


具体的にどうやるの？
```


以下の 1 行で OK です 👇

```bash
git switch -c feat/aws-waf-log-service --track origin/feature/WCDEV-545_AwsWafLogService
```

### コマンドの意味
| オプション | 説明 |
|------------|------|
| `git switch -c <新ブランチ名>` | ローカルに新しいブランチを切って即チェックアウトする（旧 `git checkout -b` と同義） |
| `--track origin/<元ブランチ>` | そのローカルブランチの upstream を指定したリモートブランチに設定する |

---

## もう少し丁寧にやる場合

```bash
# ① 最新の状態を取得
git fetch origin

# ② 新しいブランチ名で切り替え
git switch -c feat/aws-waf-log-service origin/feature/WCDEV-545_AwsWafLogService
```

> **ポイント**  
> * `origin/feature/WCDEV-545_AwsWafLogService` はフェッチ直後にしか存在しない “リモート追跡ブランチ”。  
> * `switch -c` にそのリモート追跡ブランチを渡すと、チェックアウトと同時に `--track` が暗黙的に付くので upstream 設定も完了。

---

## プッシュするとき

```bash
git push -u origin feat/aws-waf-log-service
```

`-u` を付ければ、以降は `git pull / git push` だけで自動的にリモートの同名ブランチと同期できます。



## 1. 全体フロー（10,000 社 × 業界別リストを 4 週間で整備する例）

| フェーズ | 目的 | 代表ツール／サービス | 目安期間 |
|----------|------|--------------------|----------|
| ① 要件定義 | ターゲット業界コード・項目定義・法令確認 | NAICS／日本標準産業分類、特定電子メール法チェックリスト | 0.5 週 |
| ② ソース収集 | 既存データセット＋公開レジストリを取得 | 法人番号公表サイト（CSV DL）、EDINET、帝国DB API、業界団体名簿 | 1 週 |
| ③ Web クローリング | 公式 HP URL・問い合わせページ URL を発掘 | **Scrapy‑Playwright**, **Apify**, **crawler‑crawler** | 1 週 |
| ④ AI 抽出 & 業界分類 | 住所、電話、設立年、役員名などを HTML→JSON へ変換 | **OpenAI GPT + Function‑Calling**、Diffbot、Smart‑Scrape | 0.5 週 |
| ⑤ データ整形 & 検証 | 重複排除・表記ゆれ統合・メール検証 | Pandas, Postgres + pgtrgm, NeverBounce API | 0.5 週 |
| ⑥ 配信基盤準備 | 自動コンタクトフォーム送信／CTR 計測 | Playwright(ヘッドレス) or Browserless, Zapier, gmails API | 0.5 週 |

---

## 2. 代表的データソース

| 種別 | ソース | 取得方法 | メリット |
|------|--------|----------|----------|
| **公的** | 法人番号公表サイト | 1 日 1 回 CSV 全量 DL（約 500 MB） | 無償／更新早い・重複判定キーに使える |
| | EDINET & JPx 上場会社一覧 | API / ZIP | 上場企業は IR 電話・メール記載率が高い |
| **準公的** | 経済産業省・業界団体会員名簿 | PDF → Tabula, 議事録 HTML → クローラ | 特定業界だけなら精度高 |
| **商用** | Teikoku Databank API, TDB Company View | 有償だが取引属性が詳細 | e‑mail 欄の保有率が高い |
| **OSINT** | Kaggle Datasets, Crunchbase Daily Export | CSV / API | スタートアップ系に強い |
| **検索エンリッチ** | Google Custom Search API、Bing Search API | “site:co.jp + 業界キーワード” で 1000 ドメイン収集 | 機械的に足りない分を補完 |

---

## 3. クローラ実装の骨格（Scrapy + Playwright）

```python
# scrapy.cfg で PLAYWRIGHT_BROWSER_TYPE = "chromium" を指定
import scrapy, re, json
from scrapy_playwright.page import PageCoroutine
from bs4 import BeautifulSoup

class CompanySpider(scrapy.Spider):
    name = "company"
    start_urls = [*seed_urls]   # ① 法人番号CSVに含まれた domain を起点に

    def start_requests(self):
        for url in self.start_urls:
            yield scrapy.Request(
                url, meta={"playwright": True,
                           "playwright_page_coroutines": [
                               PageCoroutine("wait_for_load_state", "networkidle")]})

    async def parse(self, response):
        soup = BeautifulSoup(response.text, "lxml")
        text   = soup.get_text(" ", strip=True)
        script = soup.find_all("script", type="application/ld+json")
        ld     = json.loads(script[0].text) if script else {}
        data = {
            "url": response.url,
            "name": ld.get("name") or soup.title.string[:80],
            "phone": re.search(r"0\d{1,3}-\d{1,4}-\d{4}", text) and _.group(),
            "email": re.search(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text),
            "address": ld.get("address", {}),
            "html": response.text[:50_000]  # GPT 抽出用
        }
        yield data
```

- 取得した `html` は **OpenAI ChatCompletion** の function‑calling で以下 JSON スキーマを返すように依頼  
  ```json
  { "companyName": "", "industry": "", "email": "", "phone": "", "prefecture": "" }
  ```
- **LangChain** の `StructuredTool` を噛ませるとバッチ抽出が楽。

---

## 4. 業界分類（自動タグ付け）

```python
prompt = f"""次の会社概要から主業種を
NAICS コードか日本標準産業分類中分類名で答えて:
```
{summary_text}
```"""

label = openai.ChatCompletion.create(
  model="gpt-4o", messages=[{"role":"user","content": prompt}],
  functions=[{"name":"set_industry","parameters":{"type":"object","properties":{
       "naics":{"type":"string"},"japanese":{"type":"string"}},"required":["naics"]}}]
)
```

*インダストリ辞書* と **Cosine‑Sim (sentence‑transformers)** のダブルチェックで誤ラベルを減らす。

---

## 5. 100 % フォーム送信を狙う自動化

| 工程 | ツール | ポイント |
|------|--------|----------|
| HTML フォーム検出 | `querySelectorAll("form")` + GPT でラベル推定 | “ご用件”＝ message, “お名前”＝ company などを AI でマッピング |
| 自動入力 | **Playwright** `page.fill`, `page.select_option` | reCAPTCHA v2 は turnstile/bypass用に 2captcha API |
| 送信結果ログ | Azure Table / BigQuery | `page.waitForResponse` で HTTP 200-> 成功 |

> **注意:** 日本では「特定電子メール法」「景表法」等で広告送信規制があります。<br>
> 1) オプトアウト情報の記載、2) 宛先管理（除外リスト）、3) 送信者情報明示 を必須にしてください。

---

## 6. 成功した案件のベストプラクティス

| 施策 | 効果 |
|------|------|
| **プロキシローテーション** (BrightData / ScraperAPI) | 大量クロールでも 429/403 を抑制 |
| **Retry‑After Respect** ＆ crawl‑delay | ドメイン Ban リスク低減 |
| **Prefetch→Queue→Async Extract** | I/O と GPT API 待ちを並列化、10k 社でも 2–3 h |
| **Postgres + pgvector で類似検索** | 類似企業の重複判定が高速 |

---

### まとめ

1. **公的 CSV＋商用 API＋検索クロール** をミックスして 10,000 社分の **確度 80 % 以上** の元データを 1 週間で確保。  
2. **Scrapy‑Playwright + GPT 抽出** で連絡先／業界タグを自動構造化。  
3. **フォーム自動送信** は Playwright＋2captcha、**コンプライアンスフラグ** を別カラムで管理。  

こうしたパイプラインを CI/CD（GitHub Actions）に載せれば、常に “最新で動く” リスト生成フローを維持できます。


以下は **「企業情報 1 万社リスト生成パイプライン」** を GitHub Actions に載せる想定のサンプルです。  
構成は **Python スクリプト群**（`pipeline/` 配下）を実行し、成果物 `dist/companies.csv` を生成してアーティファクトとして保存、  
オプションで `gh-pages` ブランチへコミット or S3 へアップロードする例になっています。

```yaml
# .github/workflows/company-crawler.yml
name: company-crawler

# ────────────────
# 1. トリガ
# ────────────────
on:
  workflow_dispatch:               # 手動実行
  schedule:                        # 毎日 03:30 (JST ≒ 18:30 UTC) に自動実行
    - cron:  '30 18 * * *'
  push:                            # スクリプト更新時に検証
    paths:
      - "pipeline/**.py"
      - ".github/workflows/company-crawler.yml"

# ────────────────
# 2. 共通 env（API キーなどは Secrets に）
# ────────────────
env:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  PROXY_URL:      ${{ secrets.RESIDENTIAL_PROXY }}
  PG_CONN:        ${{ secrets.POSTGRES_URL }}      # 重複チェック用
  TZ: "Asia/Tokyo"

# ────────────────
# 3. ジョブ定義
# ────────────────
jobs:
  build-list:
    runs-on: ubuntu-latest
    concurrency:
      group: company-crawler              # 同時実行を 1 本に制限
      cancel-in-progress: false

    steps:
    # 3‑1. リポジトリ取得
    - uses: actions/checkout@v4

    # 3‑2. Python セットアップ & キャッシュ
    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.12'
        cache: 'pip'                      # requirements.txt で自動キャッシュ

    - name: Install dependencies
      run: |
        pip install -r requirements.txt
        playwright install --with-deps chromium    # Scrapy‑Playwright 用

    # 3‑3. 企業 URL シード取得（法人番号 CSV → domain 一覧）
    - name: Prepare seed list
      run: |
        python pipeline/get_seeds_from_houjin_csv.py \
          --csv-url "https://www.houjin-bangou.nta.go.jp/download/[yyyyMMdd]zenken_all.csv" \
          --out seeds.txt

    # 3‑4. クローリング & HTML 保存（shard 並列化例）
    - name: Crawl company sites
      run: |
        python pipeline/run_scrapy.py \
          --seeds seeds.txt \
          --output raw_data.jl \
          --shards 4 --shard-id ${{ strategy.job-index }}
      strategy:
        matrix:
          shard: [0, 1, 2, 3]              # 4 並列
        fail-fast: false

    # 3‑5. AI で構造化抽出
    - name: Extract & classify via GPT
      run: |
        python pipeline/extract_with_gpt.py \
          --input raw_data.jl \
          --out extracted.parquet

    # 3‑6. 重複排除・データクレンジング
    - name: Deduplicate & cleanse
      run: |
        python pipeline/deduplicate.py \
          --input extracted.parquet \
          --out dist/companies.csv

    # 3‑7. CSV をアーティファクトとして保存
    - uses: actions/upload-artifact@v4
      with:
        name: companies-${{ github.run_number }}.csv
        path: dist/companies.csv
        if-no-files-found: error
        retention-days: 14

    # 3‑8. （任意）gh-pages へ自動コミット
    - name: Deploy to gh-pages
      if: ${{ github.ref == 'refs/heads/main' }}
      uses: peaceiris/actions-gh-pages@v4
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        publish_dir: dist
        publish_branch: gh-pages
        commit_message: "update companies list (run ${{ github.run_number }})"

    # 3‑9. （任意）S3 へアップロード
    # - uses: jakejarvis/s3-sync-action@v0.11.0
    #   with:
    #     args: --acl private --follow-symlinks
    #   env:
    #     AWS_S3_BUCKET: ${{ secrets.S3_BUCKET }}
    #     AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    #     AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    #     AWS_REGION: ap-northeast-1
```


### 解説ポイント

| 箇所 | 内容 |
|------|------|
| **トリガ** | `schedule` で定期実行、`workflow_dispatch` で手動、スクリプト更新で自動検証。 |
| **環境変数** | `OPENAI_API_KEY` などは **Secrets** 管理。`TZ` を JST に合わせてログが読みやすい。 |
| **依存インストール** | `playwright install --with-deps chromium` を忘れず追加。 |
| **並列クローラ** | `strategy.matrix` でシャード並列。`run_scrapy.py --shards 4 --shard-id N` のように分割クロール。 |
| **抽出ステップ** | GPT function‑calling で JSON 化 → Parquet 保持 → Pandas → CSV へ。 |
| **成果物管理** | `upload-artifact` で毎回保存＋保管日数 14。main ブランチなら `gh-pages` へ公開する例も。 |
| **同時実行制御** | `concurrency` で前ジョブが動いていれば次を待たせる＝API レート超過や重複実行防止。 |

> **運用のコツ**  
> - GPT API は高コストなので、`extracted.parquet` に *already_processed* フラグを書いて再実行時はスキップ。  
> - 大量リストの場合は **ジョブ → 分割ワークフロー呼び出し (`workflow_call`)** 構成で水平スケールも可能。  
> - reCAPTCHA バイパス用 2captcha キーやプロキシ情報も Secrets に。  

この YAML をベースに、自身のスクリプト／ストレージ／セキュリティ要件へ合わせて調整すれば「**常に動く・更新される企業リスト生成パイプライン**」を GitHub Actions 上で再現できます。

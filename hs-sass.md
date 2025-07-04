以下は 「HSコード自動判定＋輸出入書類生成 SaaS」 の要件定義と機能一覧、およびそれぞれを Webエンジニア視点でどう実装するか を“コードレベル”に踏み込んでまとめた設計メモです。
（※NACCS 用品目コード CSV・WCO HS 2022改訂情報を一次データとし、差分検知で自動更新する前提）  ￼ ￼ ￼

⸻

1. サービス概要

| 項目 | 内容 |
|------|------|
| **目的** | 輸出入事業者・フォワーダー・越境EC事業者向けに「商品説明 → HS候補 → 税率 → NACCS様式」までワンストップ提供。罰則リスク（誤判定課徴金・罰金）を削減し、担当者の手入力を 80% 省力化する。 |
| **提供形態** | ① Webアプリ (Next.js + Supabase Auth)<br>② REST/GraphQL API + Function Calling (JSON Schema)<br>③ Shopify / WooCommerce アドオン |
| **課金** | 月額基本料 + API従量／PDF出力従量（従量課金は Stripe Metered Billing） |
| **非機能** | 平均応答 3 秒以下, 推論精度 > 85%（Top-3内）, HS改訂反映 < 72h, ISMS相当のログ保全5年 |




⸻

2. ステークホルダー & ユースケース

| ロール | 代表ユースケース |
|--------|------------------|
| **通関担当者** | ① 商品名・仕様を貼り付け → HS候補＋根拠表示<br>② NACCS CSV (輸入･輸出) をダウンロード／税関へ電子申請 |
| **越境ECオペレーター** | Shopify 受注データを一括送信 → HSコード・税率を受信し、インボイスへ差し込み |
| **監査担当** | 過去判定結果とバージョン（当時のHS／EPA税率）を検索し、PDFでエクスポート |
| **管理者** | ユーザ／APIキー管理、料金プラン変更、HSデータ更新の差分マージを確認 |




⸻

3. 機能一覧と実現方法

#	機能	詳細	実装アイデア（具体）

| 機能 | 概要 | 技術構成 |
|------|------|----------|
| **F1 商品説明 → HS候補推論** | ・自然文/CSV/画像📷から特徴抽出<br>・HS6桁候補を確率付きで3件返却 | 1. **LLM-Router:** OpenAI o3 function calling で `title`, `material`, `use` を JSON へ正規化<br>2. **類義検索:** HS Explanatory Notes を Faiss ベクトルDB化 → embedding cosine 類似<br>3. **ルールベース補正:** 正則表現（素材・含有率）／XGBoost → 最終スコアリング |
| **F2 国別10桁拡張 & 税率出力** | ・EPA/FTA適用可否、基本税率、特恵税率 | JBIC/Tariff Database を週次クローリング → PostgreSQL 更新<br>税率ロジックは SQL で保持し GraphQL リゾルバが計算 |
| **F3 NACCS様式CSV / PDF生成** | ・輸出(OUTS – 0500)／輸入(INIM – 0400) 用 CSV<br>・税関署名 PAdES, 電子帳簿保存法タイムスタンプ | 🤖 `playwright-pdf` で官公庁PDFテンプレに自動入力<br>CSV は `@fast-csv/format` で BOM付 SJIS 出力 |
| **F4 バッチ／API連携** | ・GraphQL + Webhook (結果非同期)<br>・Shopify Admin API App Bridge | `Hono (Bun)` Edge Functions → Redis Queue<br>Supabase Edge Functions で Webhook 署名検証 |
| **F5 ユーザーフィードバック学習** | ・確定HS番号をユーザが選択 → 再学習 | 選択イベントを Kafka Topic に蓄積 → 夜間に LoRA Fine-Tune<br>失敗時ロールバック用にモジュール化 |
| **F6 データ差分監視 & ロールバック** | ・WCO/NACCSサイトの CSV 更新検知<br>・スキーマ差分で自動マイグレーション | GitHub Actions 定期ジョブ → `puppeteer` で CSV 日付スクレイプ → 差分 PR、自動テスト → `main` マージ & 本番 RDS 移行 |
| **F7 監査ログ / バージョン管理** | ・HS推論モデルID<br>・データ版数<br>・入力全文を Hash 化保存 | Supabase Row Level Security + `pgcrypto` で SHA256<br>Cloud Object Storage へ暗号化バックアップ |
| **F8 料金・メータード課金** | ・APIコール数、PDF生成数を従量計測 | Stripe Billing → Usage Records API + Webhook Verify |
| **F9 管理ダッシュボード** | ・ユーザ／請求／モデル精度メトリクス | `tRPC` + TanStack Table<br>Grafana Cloud で PromQL 可視化 |




⸻

4. システム構成イメージ

┌────────────┐   GraphQL  ┌─────────────┐  Queue  ┌─────────────┐
│  Next.js UI │◀──────────▶│  API Edge    │◀──────▶│ Job Worker  │
└────────────┘            │ (Hono/Bun)  │         │  (Python)  │
        ▲                 └────┬────────┘         └────┬────────┘
        │                        │                       │
 Webhooks│                        ▼                       ▼
─────────┤                ┌─────────────┐        ┌─────────────┐
 Shopify  │                │ Postgres    │        │  VectorDB   │
 Woo etc. │                │ (Supabase)  │        │  (Faiss)    │
─────────┘                └─────────────┘        └─────────────┘

	•	エッジファースト: 軽量な判定 (Top-3 推論) は Hono Edge で即時返却、詳細税率取得や PDF 生成はジョブワーカーへ。
	•	モデル分離: LLM API を直接叩く microservice を Worker 内に隔離し、バージョン pin とコスト監視を独立。

⸻

5. MVPロードマップ（8週想定）

Week 1-2
F1 コア (LLM 推論 + ベクトル検索) POC, Supabase Auth / テーブル設計

Week 3-4
F3 CSV/PDF 生成, Next.js Upload UI, Stripe Test Mode

Week 5-6
Shopify Private App → Webhook 連携, F2 税率DB パイプライン

Week 7-8
監査ログ & 管理ダッシュボード, F5 ユーザーフィードバック学習 1st cut



⸻

6. リスク & 回避策

| リスク | 対策 |
|--------|------|
| **HSコード誤判定の法的責任** | ToS で「最終確認は顧客責任」と明記 + 判定根拠(条文リンク)提示 |
| **モデルコスト急騰** | OpenAI fallback, Ollama / Mistral-7B-Instruct Edge デプロイを並列実装 |
| **HS・税率改訂追随** | GitHub Actions + 自動ユニットテスト。CSV差分を Slack 通知 & 手動承認フロー併設 |



⸻

7. 次のステップ
	1.	スキーマ草案 (OpenAPI+JSON Schema) を作成 – エンドポイント名・型を決める。
    	2.	NACCS CSV / HS Explanatory Notes の初回クローラー を実装し、PostgreSQL に流し込む。
	3.	トップ10 製品カテゴリで精度検証 – 既知サンプル300件で Top-3 Accuracy を測定し、閾値を設定。

⸻

この構成であれば 2–3名体制でも MVP→有料トライアルまで到達可能 です。
「テーブル設計から始めたい」「クローラーのサンプルコードが欲しい」など、さらに深堀りが必要なら気軽にどうぞ！

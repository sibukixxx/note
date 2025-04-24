Rustで企業のバックエンドサービスを開発している人に質問です 
domainのフィールドは公開していますか？

ドメインのフィールドを公開とはどういうこと？

### 1. 文脈整理
Rust で “ドメイン” と言うと、**DDD（Domain-Driven Design）で定義する _domain クレート／module_** を指すケースが多いです。  
ここで **「フィールドを公開する」** とは、Rust の可視性修飾子で

```rust
pub struct Order {
    pub id: OrderId,          // ← ここを「公開」
    pub status: OrderStatus,  // ← ここも「公開」
}
```

のように *外部クレート／モジュール* から直接アクセスできる状態にするか、  
あるいは

```rust
pub struct Order {
    id: OrderId,
    status: OrderStatus,
}
impl Order {
    pub fn id(&self) -> OrderId { self.id }
    pub fn status(&self) -> OrderStatus { self.status }
}
```

のように **フィールド自体は非公開** にして **getter／ドメインメソッド経由でのみ操作させる** か、という話を指します。

---

### 2. どちらを選ぶかの判断基準

| 観点 | フィールドを **公開** (`pub`) | フィールドを **非公開** (メソッド経由) |
|------|-----------------------------|---------------------------------------|
| **ドメイン不変条件の保護** | 難しい（直接書き換え可） | **守りやすい**（setter 不提供で完全 read-only も可） |
| **使用側の記述量** | `order.status` で直接参照でき簡潔 | `order.status()` と呼ぶ必要がある |
| **シリアライズ**<br>(serde など) | そのまま derive で OK | `#[serde(getter = …)]` を書くか DTO を別で用意 |
| **リファクタリング耐性** | 内部実装＝API になるため壊れやすい | フィールド変更しても API 互換を保てる |
| **パフォーマンス** | Getter もゼロコストなので差はほぼ無し | 同左（インライン展開される） |

> **結論**  
> **「不変条件を崩されたら困る値」は非公開、ただの ID や表示用スカラーなら公開でも可**——が実務での落としどころです。  

---

### 3. 代表パターン

#### 3-1. **値オブジェクト／エンティティ ID は公開**
```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct OrderId(Uuid);
// ↑ newtype にしている時点で不正値は作れないため、
//   外部モジュールに公開しても壊れにくい
```

#### 3-2. **振る舞いを伴うエンティティは非公開 + メソッド**
```rust
pub struct Order {
    id: OrderId,
    status: OrderStatus,      // Cancelled → Paid へ勝手に戻されると困る
}
impl Order {
    pub fn pay(&mut self) -> Result<(), DomainErr> {
        ensure!(self.status == OrderStatus::Pending);
        self.status = OrderStatus::Paid;
        Ok(())
    }
    pub fn status(&self) -> OrderStatus { self.status } // 読み取りだけ公開
}
```

#### 3-3. **API 境界用 DTO を分離**
```rust
#[derive(Serialize)]
pub struct OrderDto {
    pub id: String,
    pub status: String,
    pub total: u64,
}
impl From<&Order> for OrderDto { /* … */ }
```
- ドメイン層は **内部表現**、API 層は **DTO** に責任分離

---

### 4. プロジェクト構成の一例

```
crates/
  domain/           -- Order, Customer, 値オブジェクト…
  usecase/          -- Application Service, CQRS, etc.
  infrastructure/   -- DB, 外部 API 実装
  presentation/
     ├─ rest/       -- Axum / Actix
     └─ graphql/    -- async-graphql
```

- **domain クレートは極力 “pub(crate)”** に留め、外からは usecase 経由で操作  
- プレゼンテーション層には `OrderDto` を expose

---

### 5. まとめ

| 策 | いつ採用するか |
|----|----------------|
| **フィールド公開 (`pub`)** | ✔︎ 単なる識別子・表示用スカラー<br>✔︎ 不変条件を型レベルで完全に保証できる場合 (`NonEmptyString`, `PositiveAmount`) |
| **非公開 + メソッド** | ✔︎ 状態遷移を制御したいエンティティ<br>✔︎ 将来のリファクタ容易性を重視したい場合 |
| **DTO を分離** | ✔︎ Web/API 層とドメイン層を明確分離し、スキーマ変更を局所化したい場合 |

**「公開しない＝オーバーヘッド」にはなりません（インライン展開でゼロコスト）。**  
ドメインの整合性がビジネス価値に直結するなら、メソッド経由で守る方が長期的には安全です。

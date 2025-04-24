TypeScript（というかJavaScript系全般）で `try/catch` を安易に使うと、むしろ設計が崩れる元になります。
あなたの言う「非検査例外的に扱う」のは、いわば「**失敗するかもしれないが、それに備える責任は上位レイヤー（ユースケースやエントリーポイント）にある**」という設計哲学ですよね。以下のように整理できると思います。

---

### ◆ try/catch を避けるべき理由（業務ロジック層）

1. **責務の分離を壊す**  
   catch すると、ロジックの中にエラーハンドリングの条件分岐が入って、SRP（単一責任原則）を壊しやすい。

2. **ユースケースの流れを分断する**  
   エラー処理をドメイン内でやると、正常系と異常系が混在して、可読性と保守性が低下。

3. **例外が流れてきてくれない**  
   catch して何もせず握りつぶしたり、ラップして再 throw せずに使うと、上位のロジックで判断できなくなる。

---

### ◆ どう設計すべきか？

#### 1. エラーの起点は「外部」に集約する
- 外部依存（DB, API, ファイルIOなど）はエラーが起きる。
- なので、**infra層（adapter）で try/catch を使い、ドメイン層には `throw` のみを投げるように設計**。

```ts
// infra/repository/UserRepository.ts
async getUser(id: string): Promise<User> {
  try {
    const result = await prisma.user.findUniqueOrThrow({ where: { id } });
    return User.from(result);
  } catch (e) {
    if (e instanceof Prisma.NotFoundError) {
      throw new UserNotFoundError(id);
    }
    throw e; // その他はそのまま上に
  }
}
```

#### 2. アプリケーション（ユースケース）レイヤーで全体ハンドリング

```ts
async function executeSomething() {
  try {
    await usecase.doSomething();
    return { status: "success" };
  } catch (e) {
    if (e instanceof KnownAppError) {
      return { status: "fail", message: e.message };
    }
    throw e; // 不明なエラーはミドルウェア等でログ出し
  }
}
```

#### 3. ドメイン層やサービス層では `try/catch` は書かず、`throw` だけ

```ts
// domain/service/UserService.ts
export function doSomethingRisky(user: User) {
  if (!user.canDoSomething()) {
    throw new BusinessRuleViolation("条件を満たしていません");
  }
  // 通常処理
}
```

---

### ◆ よくあるアンチパターン

- `try/catch` で握り潰してログだけ出して終了 → エラーが検知されず表面化しない。
- `catch` して無理に正常レスポンスを返す → エラー時の挙動が隠蔽されて、デバッグ不能に。

---

### ◆ 結論

> `try/catch` は **infra（外部世界）とのインターフェースで例外をドメイン例外に変換するために使う**。  
> 業務ロジックやドメインの中では、できる限り `throw` のみを使い、ハンドリングは上位責務とする。

これ、まさに **「例外は制御フローではない」** という設計思想ですよね。

必要なら、非同期例外やcatch箇所の戦略レイヤー別ガイドもまとめますよ。

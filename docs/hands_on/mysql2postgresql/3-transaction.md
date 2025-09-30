# トランザクションとロック

1. トランザクション分離レベル
2. ロックの種類 (行 / テーブル代表モード)
3. ALTER (DDL) が取得するロック
4. 外部キー制約とロック挙動

# おすすめ参考記事

- [トランザクション分離レベルのケースと対応方法](https://christina04.hatenablog.com/entry/transaction-isolation-level)
- [トランザクション分離レベルの古典的論文 A Critique of ANSI SQL Isolation Levels を読む](https://developer.hatenastaff.com/entry/2017/06/21/100000)

---

# 1. トランザクション分離レベル

SQL標準の4つの分離レベル

| 分離レベル | ダーティリード | ファジーリード(反復不能読み取り) | ファントムリード | シリアライゼーションアノマリー(直列化異常) |
|------------|----------------|-------------------|------------------|------------|
| リードアンコミッティド | 許容されるが、PostgreSQLでは発生しない | 可能性あり | 可能性あり | 可能性あり |
| リードコミッティド | 安全 | 可能性あり | 可能性あり | 可能性あり |
| リピータブルリード | 安全 | 安全 | 許容されるが、PostgreSQLでは発生しない | 可能性あり |
| シリアライザブル | 安全 | 安全 | 安全 | 安全 |

引用元 : [公式ドキュメント:トランザクションの分離](https://www.postgresql.jp/document/current/html/transaction-iso.html)


一度は読んだ方が良い資料
- [WHERE 条件のフィールドを UPDATE するのって，明示的にロックしてなくても安全？全パターン調べてみました！](https://qiita.com/mpyw/items/14925c499b689a0cbc59?utm_campaign=post_article&utm_medium=twitter&utm_source=twitter_share)
- [MySQL/Postgres におけるトランザクション分離レベルと発生するアノマリーを整理する](https://zenn.dev/mpyw/articles/rdb-transaction-isolations)

アドバイザリーロックについても合わせて読みたい
- [排他制御のためだけに Redis 渋々使ってませんか？データベース単独でアドバイザリーロックできるよ！](https://zenn.dev/mpyw/articles/rdb-advisory-locks)

## PostgreSQL と MySQL の違い

PostgreSQLはデフォルトが READ COMMITTED。
MySQL InnoDBはデフォルトが REPEATABLE READ。
MySQLにはギャップロックがあるが、PostgreSQLにはギャップロックはない。

実行計画におけるロック待ちの可視化（pg_locks / MySQLの performance_schema）

```sql
SHOW default_transaction_isolation;
```

- [PostgreSQLのread committed時におけるUPDATEの挙動について](https://soudai.hatenablog.com/entry/2022/07/03/223915)

# 2. ロックの種類

## 主なロックのレベル

| 種類 | 内容 | 補足 |
|------|------|------|
| 排他ロック (eXcluded lock) | ロック対象へのすべてのアクセスを禁止する | SELECT, INSERT, UPDATE, DELETE、すべて実行できない<br>書き込みロック、X lockと呼ばれることもある |
| 共有ロック (Shared lock) | ロック対象への参照以外のアクセスを禁止する | ほかのトランザクションから参照 (SELECT) でアクセス可能<br>読み込みロック、S lockと呼ばれることもある |

PostgreSQLのロックのモード

| 要求するロックモード | ACCESS SHARE | ROW SHARE | ROW EXCLUSIVE. | SHARE UPDATE EXCLUSIVE. | SHARE | SHARE ROW EXCLUSIVE. | EXCLUSIVE. | ACCESS EXCLUSIVE. |
|---------------------|-------------|-----------|-----------|-------------------|-------|-----------------|-------|-------------|
| ACCESS SHARE        |             |           |           |                   |       |                 |       | X           |
| ROW SHARE           |             |           |           |                   |       |                 | X     | X           |
| ROW EXCL.           |             |           |           |                   | X     | X               | X     | X           |
| SHARE UPDATE EXCL.  |             |           |           | X                 | X     | X               | X     | X           |
| SHARE               |             |           | X         | X                 |       | X               | X     | X           |
| SHARE ROW EXCL.     |             |           | X         | X                 | X     | X               | X     | X           |
| EXCL.               |             | X         | X         | X                 | X     | X               | X     | X           |
| ACCESS EXCL.        | X           | X         | X         | X                 | X     | X               | X     | X           |

※ 表中のXはロックモード間で競合することを示します

| 要求するロックモード | FOR KEY SHARE | FOR SHARE | FOR NO KEY UPDATE | FOR UPDATE |
|---------------------|---------------|-----------|-------------------|------------|
| FOR KEY SHARE       |               |           |                   | X          |
| FOR SHARE           |               |           | X                 | X          |
| FOR NO KEY UPDATE   |               | X         | X                 | X          |
| FOR UPDATE          | X             | X         | X                 | X          |

※ 表中のXはロックモード間で競合することを示します


引用元 : [公式ドキュメント:ロックモードの互換性](https://www.postgresql.jp/document/current/html/explicit-locking.html#TABLE-LOCK-COMPATIBILITY）

## ページロック
MySQLのInnoDBストレージエンジンには、メタデータロックがあるが、PostgreSQLにも同様にページロックがあります。

> テーブルと行ロックに加え、ページレベルの共有/排他ロックがあり、これらは共有バッファプールにあるテーブルページへの読み書きのアクセスを管理するために使用されます。 これらのロックは、行が取得された後や更新された後に即座に解除されます。 アプリケーション開発者は通常ページレベルロックを考慮する必要はありませんが、ロックについて全てを説明したかったためここで取り上げました。
>
引用元： [公式ドキュメント:ページロック](https://www.postgresql.jp/document/current/html/explicit-locking.html#LOCKING-PAGES)

## 主なロックの粒度

| 種類 | 内容 | 補足 |
|------|------|------|
| 表ロック | テーブル（表）を対象にロックするため該当のテーブル内の行はすべて対象になる | テーブルロックと呼ばれることもある |
| 行ロック | 行単位で対象をロックする。1行の場合もあれば複数行にまたがる場合もあり、すべての行を対象にすると表ロックと同義になる | レコードロックと呼ばれることもある |

## 行ロックの取得

行ロックの種類
| 句 | 意味 | 主な競合 | 備考 |
|----|------|----------|------|
## skip locked

```sql
SELECT id FROM accounts
WHERE balance > 0
FOR UPDATE SKIP LOCKED
LIMIT 1;
```

## PostgreSQLのデッドロック

```sql
demo=# BEGIN;
 BEGIN
 demo=# SELECT * FROM demo;-- トランザクションB 
demo=# BEGIN;
 BEGIN
 demo=# SELECT * FROM demo;-- トランザクションA 
demo=# LOCK TABLE demo;
 LOCK TABLE-- トランザクションB 
demo=# LOCK TABLE demo;
 ERROR:  deadlock detected
 DETAIL:  Process 1979 waits for AccessExclusiveLock on relation 160551 
of database 160548; blocked by process 1978.
 Process 1978 waits for AccessExclusiveLock on relation 160551 of 
database 160548; blocked by process 1979.
 HINT:  See server log for query details.
 ```

> 普段MySQLを利用している人からすると驚きだと思いますが、Postgre SQLはSELECTでも「AccessShareLock」という一番小さなレベルのロックを取ります。
> AccessShareLockはLOCK TABLE実行時に取得するロック「ACCESS EXCLUSIVE」とコンフリクトします

引用元: 失敗から学ぶRDBの正しい歩き方:13章 知らないロック

## PostgreSQLのデッドロックの検出

- [PostgreSQLは雰囲気でデッドロックを殺す](https://soudai.hatenablog.com/entry/2017/12/26/080000)
- [PostgreSQL Internals](https://www.postgresqlinternals.org/chapter6/)

## 行ロック待ち観察

セッションA:

```sql
BEGIN; SELECT * FROM accounts WHERE id = 1 FOR UPDATE; -- ロック保持
```

セッションB (ブロック例):

```sql
BEGIN; SELECT * FROM accounts WHERE id = 1 FOR UPDATE; -- 待機
```

別ターミナル (待機確認):

```sql
SELECT pid, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE state <> 'idle';
```

解除:

```sql
-- セッションA
COMMIT; -- B が続行
```

NOWAIT 例:

```sql
BEGIN; SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT; -- 即エラー
ROLLBACK;
```

ロック状況確認:

```sql
SELECT locktype, relation::regclass AS rel, mode, granted
FROM pg_locks
WHERE relation IS NOT NULL;
```

---

## 3. ALTER (DDL) のロック

[ALTER TABLEの各コマンドのロックレベル](https://masahikosawada.github.io/2023/05/08/Lock-Levels-Of-ALTER-TABLE/)


## 4. 外部キー制約とロック

PostgreSQLは外部キー制約を設定しても子テーブル側にインデックスを自動作成しないため、子テーブル側にインデックスが無いと親テーブルの更新時にテーブルスキャンが発生し、ロック競合が増大します。
特に親テーブルに対する範囲の広い更新や削除が発生する場合、子テーブルにインデックスが無いと親テーブルの更新や削除が非常に遅くなります。

MySQLには制約の無効化 (SET FOREIGN_KEY_CHECKS=0) がありますが、PostgreSQLにはありません。
代わりに遅延制約を設定することができ、コミット時に一括検証することができます。
ただし、遅延制約はあとから変更することができず、対象の制約作成時に指定する必要があり、デフォルトでは即時検証 (IMMEDIATE) になるため、自覚的に遅延制約を設定する必要があります。

```sql
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS orders CASCADE;

CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL,
  status  TEXT    NOT NULL DEFAULT 'new'
);

CREATE TABLE payments (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  amount   INTEGER NOT NULL
);

CREATE INDEX ON payments(order_id); -- 子側 FK index
```

セッションA:

```sql
BEGIN; UPDATE orders SET status='processing' WHERE id=1;
```

セッションB:

```sql
INSERT INTO payments(order_id, amount) VALUES (1, 500); -- A COMMIT まで待つ場合
```

遅延検証 (DEFERRABLE) 例:

```sql
ALTER TABLE payments DROP CONSTRAINT payments_order_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_order_id_fkey
  FOREIGN KEY(order_id) REFERENCES orders(id)
  DEFERRABLE INITIALLY DEFERRED;

BEGIN;
INSERT INTO payments(order_id, amount) VALUES (9999, 100); -- 一時不整合許容
INSERT INTO orders(id, user_id, status) VALUES (9999, 1, 'new');
COMMIT; -- コミット時に一括検証
```
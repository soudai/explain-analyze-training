# トランザクションとロック

1. トランザクション分離レベル
2. ロックの種類 (行 / テーブル代表モード)
3. ALTER (DDL) が取得するロック
4. 外部キー制約とロック挙動

# おすすめ参考記事

- [トランザクション分離レベルのケースと対応方法](https://christina04.hatenablog.com/entry/transaction-isolation-level)
- [トランザクション分離レベルの古典的論文 A Critique of ANSI SQL Isolation Levels を読む](https://developer.hatenastaff.com/entry/2017/06/21/100000)
- [PostgreSQLのread committed時におけるUPDATEの挙動について](https://soudai.hatenablog.com/entry/2022/07/03/223915)

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

## PostgreSQL と MySQL の違い

PostgreSQLはデフォルトが READ COMMITTED。
MySQL InnoDBはデフォルトが REPEATABLE READ。
MySQLにはギャップロックがあるが、PostgreSQLにはギャップロックはない。

実行計画におけるロック待ちの可視化（pg_locks / MySQLの performance_schema）

```sql
SHOW default_transaction_isolation;
```

## READ COMMITTED (再読で値が変わる)

todo : ファジーリードとファントムリードを確認する手順を記載する

## REPEATABLE READ

todo : ファジーリードとファントムリードを確認する手順を記載する

# 2. ロックの種類

## 主なロックのレベル

| 種類 | 内容 | 補足 |
|------|------|------|
| 排他ロック (eXcluded lock) | ロック対象へのすべてのアクセスを禁止する | SELECT, INSERT, UPDATE, DELETE、すべて実行できない<br>書き込みロック、X lockと呼ばれることもある |
| 共有ロック (Shared lock) | ロック対象への参照以外のアクセスを禁止する | ほかのトランザクションから参照 (SELECT) でアクセス可能<br>読み込みロック、S lockと呼ばれることもある |

## 主なロックの粒度

| 種類 | 内容 | 補足 |
|------|------|------|
| 表ロック | テーブル（表）を対象にロックするため該当のテーブル内の行はすべて対象になる | テーブルロックと呼ばれることもある |
| 行ロック | 行単位で対象をロックする。1行の場合もあれば複数行にまたがる場合もあり、すべての行を対象にすると表ロックと同義になる | レコードロックと呼ばれることもある |

## 行ロックの取得

| 句 | 意味 | 主な競合 | 備考 |
|----|------|----------|------|
| FOR UPDATE | 更新予定行の排他 | FOR UPDATE/NO KEY UPDATE | 最頻出 |
| FOR NO KEY UPDATE | PK/Unique を変えない更新 | FOR UPDATE/NO KEY UPDATE | UPDATE 内部利用 |
| FOR SHARE | 共有参照 | FOR UPDATE 系 | 読み + 整合参照 |
| FOR KEY SHARE | FK 参照保護 | FOR UPDATE | 親行参照維持 |

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

| 操作 | ロック影響 (概念) | 備考 |
|------|------------------|------|
| ADD COLUMN (NULL) | メタデータのみ | 高速 |
| ADD COLUMN NOT NULL DEFAULT (v14+) | 多くはメタのみ | 旧版は全行書換注意 |
| SET NOT NULL | 全行検証 | 大量行は段階移行 |
| TYPE 変更 (USING) | 行再書き出し | 所要時間計測必須 |

段階的 NOT NULL 手順:

1. 列追加 (NULL 可)
2. バックフィル (バッチ更新)
3. 残 NULL 数確認
4. `ALTER TABLE ... SET NOT NULL`

小テスト (経過差を見る例):

```sql
SELECT now(); ALTER TABLE accounts ADD COLUMN note TEXT; SELECT now();
```

---

## 4. 外部キー制約とロック

親行参照時: 親に KEY SHARE。子側 FK 列にインデックスが無いと全表スキャンで競合増。

セットアップ:

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

参照ロック観察:

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
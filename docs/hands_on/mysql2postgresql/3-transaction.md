# 3. トランザクションとロック (Hands-on)

本ハンズオンは以下の必須 4 項目だけを最短で「手を動かして」理解するためのミニマル版です。不要な周辺概念 (Vacuum / MVCC 深堀り / デッドロック総論 など) は除外しています。

対象 (必須 4 項目):

1. トランザクション分離レベル
2. ロックの種類 (行 / テーブル代表モード)
3. ALTER (DDL) が取得するロック
4. 外部キー制約とロック挙動

推奨: 2 つの psql セッション (A/B) を横に並べて「待ち」「競合」「即時エラー」を観察。

セットアップ (最初に 1 回実行):

```sql
CREATE SCHEMA IF NOT EXISTS txlab;
SET search_path = txlab, public;

DROP TABLE IF EXISTS accounts CASCADE;
CREATE TABLE accounts (
  id       SERIAL PRIMARY KEY,
  name     TEXT    NOT NULL,
  balance  INTEGER NOT NULL DEFAULT 0
);
INSERT INTO accounts(name, balance) VALUES
  ('alice',100),('bob',50),('carol',0);
```

---

## 1. トランザクション分離レベル

PostgreSQL デフォルトは READ COMMITTED (各文で最新コミットを読む)。

| レベル | 特徴 | 防げる主な現象 | 注意点 |
|--------|------|----------------|--------|
| READ COMMITTED | 各文で最新 snapshot | ダーティリード | 再 SELECT で値が変わる |
| REPEATABLE READ | 開始時 snapshot 固定 | Non-repeatable read | 幻影は起こり得る |
| SERIALIZABLE | SSI 競合検出 | 幻影 / 書込スキュー | 40001 をリトライ |

現在値確認:

```sql
SHOW default_transaction_isolation;
```

### 実験 1: READ COMMITTED (再読で値が変わる)

セッションA:

```sql
BEGIN;
SELECT balance FROM accounts WHERE name='alice'; -- 100
```

セッションB:

```sql
UPDATE accounts SET balance = balance - 10 WHERE name='alice';
COMMIT; -- 90
```

セッションA:

```sql
SELECT balance FROM accounts WHERE name='alice'; -- 90 (変化)
COMMIT;
```

### 実験 2: REPEATABLE READ (再読固定)

セッションA:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM accounts WHERE name='bob'; -- 50
```

セッションB:

```sql
UPDATE accounts SET balance = balance + 100 WHERE name='bob';
COMMIT; -- 150
```

セッションA:

```sql
SELECT balance FROM accounts WHERE name='bob'; -- 50 (固定)
COMMIT;
```

### 実験 3: SERIALIZABLE (競合検出)

同一ロジックを 2 セッション同時実行し、片方で以下が出たら成功:

```text
ERROR: could not serialize access due to read/write dependencies among transactions
SQLSTATE: 40001
```

→ アプリ層で指数バックオフなどのリトライポリシー必須。

---

## 2. ロックの種類

### 行ロック (SELECT ... FOR ...)

| 句 | 意味 | 主な競合 | 備考 |
|----|------|----------|------|
| FOR UPDATE | 更新予定行の排他 | FOR UPDATE/NO KEY UPDATE | 最頻出 |
| FOR NO KEY UPDATE | PK/Unique を変えない更新 | FOR UPDATE/NO KEY UPDATE | UPDATE 内部利用 |
| FOR SHARE | 共有参照 | FOR UPDATE 系 | 読み + 整合参照 |
| FOR KEY SHARE | FK 参照保護 | FOR UPDATE | 親行参照維持 |

オプション: NOWAIT (待たず即エラー) / SKIP LOCKED (待たず飛ばす)。

ジョブキュー的取得パターン:

```sql
SELECT id
FROM accounts
WHERE balance > 0
FOR UPDATE SKIP LOCKED
LIMIT 5;
```

### 行ロック待ち観察

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

### テーブルロック (代表モード)

| モード | 主用途 | 強く競合する相手 | 備考 |
|--------|--------|------------------|------|
| ACCESS SHARE | SELECT | ACCESS EXCLUSIVE | 最軽量 |
| ROW EXCLUSIVE | 通常 DML | SHARE/ACCESS EXCLUSIVE | INSERT/UPDATE/DELETE |
| SHARE | CREATE INDEX | ROW EXCLUSIVE | インデックス作成 |
| ACCESS EXCLUSIVE | ALTER/DROP/VACUUM FULL | 全て | 最強ロック |

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

落とし穴と回避:

| 問題 | 原因 | 回避 |
|------|------|------|
| 子 INSERT が遅い | 親探索フルスキャン | 子側 FK インデックス |
| NOT NULL + FK 同時付与が長時間 | 全行検証コスト | 先にデータ投入 → 後から制約 |
| 親大量削除が遅い | 子行存在チェック | 先に子削除 / バッチ |

---

### 学習チェックリスト

| 項目 | 自信度 (○/△/×) |
|------|-----------------|
| 分離レベル差 (READ COMMITTED vs REPEATABLE READ) を再読で確認 | |
| SERIALIZABLE 競合 (40001) を発生させた | |
| 行ロック待ち & NOWAIT / SKIP LOCKED を試した | |
| ALTER (ADD COLUMN / SET NOT NULL) の影響を観察 | |
| FK 待ち (親更新 vs 子挿入) を再現 | |
| DEFERRABLE FK のコミット時検証を体験 | |

---

必要になれば拡張版 (MVCC / Vacuum / デッドロック詳細 等) を別資料で参照してください。フィードバック歓迎です。
| LOCK MODE | 主用途 | 代表的に競合する重いモード |


# スロークエリの見方

　まずはログを出力する必要がある。
ログはテキストに出力する場合とデータベースに出力する場合がある。


# MySQLの場合

## ログの出力

```
slow_query_log = 1 # slow queryログの有効化
slow_query_log_file=/usr/local/mysql/data/slow.log # ファイルパス
long_query_time=< 許容できないレスポンス時間 (秒)>
log_queries_not_using_indexes = 1 # インデックスを使っていないクエリもログに出力する
```

- https://dev.mysql.com/doc/refman/8.0/ja/slow-query-log.html
- https://dev.mysql.com/doc/refman/8.0/ja/log-destinations.html
- https://dev.mysql.com/doc/refman/8.0/ja/sys-innodb-lock-waits.html

## スロークエリの解析
mysqldumpslow 

```
// 同じSQLの実行時間の合計が多い順でソート
$ mysqldumpslow -s t mysql-slow.log

SELCT * FROM slowquery WHERE time > N ORDER BY ~~~ limit 10;

Reading mysql slow query log from mysql-slow.log
Count: 390  Time=0.10s (37s)  Lock=0.00s (0s)  Rows=20.0 (7800), isucon[isucon]@localhost
  SELECT * FROM chair WHERE stock > N ORDER BY price ASC, id ASC LIMIT N

// 同じSQLの平均実行時間が多い順でソート
$ mysqldumpslow -s at mysql-slow.log

Reading mysql slow query log from mysql-slow.log
Count: 261  Time=0.14s (35s)  Lock=0.00s (0s)  Rows=20.0 (5220), isucon[isucon]@localhost
EXPLAIN SELECT * FROM estate WHERE (door_width >= N AND door_height >= N) OR (door_width >= N AND door_height >= N) OR (door_width >= N AND door_height >= N) OR (door_width >= N AND door_height >= N) OR (door_width >= N AND door_height >= N) OR (door_width >= N AND door_height >= N) ORDER BY popularity DESC, id ASC LIMIT N
  

// スロークエリログとして検出された件数が多い順でソート
$ mysqldumpslow -s c mysql-slow.log

Reading mysql slow query log from mysql-slow.log
Count: 390  Time=0.10s (37s)  Lock=0.00s (0s)  Rows=20.0 (7800), isucon[isucon]@localhost
  SELECT * FROM chair WHERE stock > N ORDER BY price ASC, id ASC LIMIT N
```

pt-query-digest

機能がmysqldumpslowより豊富。

https://thinkit.co.jp/article/9617

## performance_schema

様々な便利テーブル（view）がある

- https://thinkit.co.jp/article/9890
- https://thinkit.co.jp/article/10028

## ロック
kitagawaさんの[記事](https://gihyo.jp/dev/serial/01/mysql-road-construction-news/0145)を読もう。

sys.innodb_lock_waitsビューを使う。

```sql
-- ENGINE_TRANSACTION_IDを探す
-- blocking_queryがnullのやつ
select * from sys.innodb_lock_waits\G
-- blockしているTHREAD_ID を探す、INDEX_NAMEを一緒に確認すると良い
select * from performance_schema.data_locks where ENGINE_TRANSACTION_ID = {対象のblocking_trx_idを指定する};
--- 対象のqueryを探す、ブロックしているINDEXがわからない場合はなくても良い
--- ロックの当たりが付いてるならSQL_TEXTにfor shareとかfor updateとかで検索してもよい
--- 全くわからないならSQL_TEXTはなくてもよい
select * from performance_schema.events_statements_history where THREAD_ID = {対象のthread_id } and SQL_TEXT like '%ブロックしているindexの対象のカラム名%'\G
--- 対象のSQLがどれくらいロックで待たされているか
select * from performance_schema.events_statements_summary_by_digest where QUERY_SAMPLE_TEXT like '%検索したいクエリ%'\G
```

この記事が丁寧に解説している

https://blog.kinto-technologies.com/posts/2024-03-05-aurora-mysql-stats-collector-for-blocking/

# PostgreSQLの場合

```
logging_collector=on # log の有効化
log_line_prefix='[%t]%u %d %p[%l] %h[%i]' # log の出力時のフォーマットの指定
log_min_duration_statement=< 許容できないレスポンス時間 (ミリ秒)>
```

```
session_preload_libraries = 'auto_explain'
# 100ms以上かかっているクエリを自動でEXPLAINする
auto_explain.log_min_duration = 許容できないレスポンス時間(ミリ秒)
auto_explain.log_analyze = on
auto_explain.log_nested_statements = on
auto_explain.log_triggers = on
```

実行計画はこれを見ると全部書いてある
https://speakerdeck.com/keiko713/explain-explain

## pg_stat_statements

```
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 1000
# topが一番表層のSQLのみ、allは入れ子されたSQLも見る
pg_stat_statements.track = top or all or none
# ユーティリティコマンド（DML以外）も保存するかどうか
pg_stat_statements.track_utilit = on
pg_stat_statements.save = on
```

```sql
-- RDSとかAuroraはこれだけでいける
CREATE EXTENSION pg_stat_statements;
```

# pg_stat_activity

```sql
SELECT pid, state, wait_event, wait_event_type, (NOW() - xact_start)::INTERVAL(3) AS tx_duration, (NOW() - query_start)::INTERVAL(3) AS sql_duration, query 
FROM pg_stat_activity 
WHERE pid <> pg_backend_pid();
```


## ロック
スロークエリの注意点、ロック待ちはスロークエリに含まれない。
これはMySQLにも言える。

pg_locks＋pg_stat_activity

```sql
SELECT l.locktype, c.relname, l.pid, l.mode,
         substring(a.current_query, 1, 6) AS query,
         (current_timestamp - xact_start)::interval(3) AS duration
   FROM   pg_locks l LEFT OUTER JOIN pg_stat_activity a
          ON l.pid = a. procpid
          LEFT OUTER JOIN pg_class c ON l.relation = c.oid
   WHERE  NOT l.granted ORDER BY l.pid;
```

pg_blocking_pidsで出すパターンもある。

```sql
SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity;
SELECT * FROM pg_locks WHERE pid = {見つけたpg_blocking_pids};
```

```
# デッドロックの精査時間
deadlock_timeout=1
log_lock_waites=on
```

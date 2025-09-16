# 実行計画とスロークエリとパフォーマンスチューニング
このドキュメントでは、MySQLを使う人がPostgreSQLを使うときに知っておくべきや概念の違いについて説明します。
MySQLのストレージエンジンはInnoDBに限定します。

# 目次
- 
- ログの出し方
- 実行計画の見方
- JOINのアルゴリズム
- インデックス
- パラレルクエリ

# ログの出し方
MySQLとPostgreSQLのスロークエリをログとして出す方法と統計情報について説明します。

## MySQLのログの出力
todo:あとでやる

## PostgreSQLのログの出力
tood:あとでやる

## MySQLのevents_statements_summary_by_digest

MySQLには`events_statements_summary_by_digest`というビューがあり、スロークエリの統計情報を確認できます。

https://blog.mirakui.com/entry/2023/11/27/152107

## PostgreSQLのpg_stat_statements
MySQLの`events_statements_summary_by_digest`に相当するものとして、PostgreSQLには`pg_stat_statements`という拡張機能があります。
`pg_stat_statements`は、実行されたSQLクエリの統計情報を収集し、クエリのパフォーマンス分析に役立ちます。

# 実行計画の見方
MySQLとPostgreSQLの実行計画の見方にはいくつかの違いがあります。

## MySQLの実行計画
- [公式ドキュメント：EXPLAIN ステートメント](https://dev.mysql.com/doc/refman/8.0/ja/explain.html)

## PostgreSQLの実行計画
『EXPLAINを使ったPostgreSQLのクエリ最適化の基本と実践』を読みましょう。
この資料が今日現在(2025/09/16 時点)で最も詳しく、かつ最適な資料です。

- [EXPLAINを使ったPostgreSQLのクエリ最適化の基本と実践](https://speakerdeck.com/keiko713/explain-explain)
- [PGCon 2014 Tokyo【D3】PostgreSQL SQL チューニング入門 入門編（下雅意 美紀）](https://www.youtube.com/watch?v=gxsBi-6ub3k)
- [PGCon 2014 Tokyo【D4】PostgreSQL SQL チューニング入門 実践編（山田 聡）](https://www.youtube.com/watch?v=ptUd33kZ3-o)
- [パフォーマンスチューニング9つの技 ～「探し」について～](https://www.fujitsu.com/jp/products/software/resources/feature-stories/postgres/article-index/tuningrule9-search/)

# JOINのアルゴリズム
MySQLにはNested Loop JoinとMySQL 8.0.18 以降でサポートされたHash Joinがあります。
PostgreSQLにはNested Loop Join、Hash Join、Sort Merge Joinがあります。

- https://x.com/ikkitang/status/1845808792937824644
- https://x.com/ikkitang/status/1845808921140986186
- https://x.com/ikkitang/status/1845809043413344632

　このJOINの違いは、LIMIT付きのORDER BYのパフォーマンスや、テーブルスキャンが発生するような集計クエリのパフォーマンスに大きな影響を与えます。
用途に合わせて適切なJOINのアルゴリズムが選ばれていることを確認しましょう。

# カバリングインデックス

MySQLとPostgreSQLのカバリングインデックスの違いについて説明します。

## MySQLのカバリングインデックス
MySQLでは、インデックスに含まれるすべての列がクエリで使用されている場合、テーブルへのアクセスを避けることができます。これにより、パフォーマンスが向上します。

- 例: `SELECT col1, col2 FROM table WHERE col1 = 'value';` で `col1` と `col2` がインデックスに含まれている場合、テーブルアクセスは不要です。
- 参考: [MySQLとインデックスと私](https://speakerdeck.com/yoku0825/mysqltoindetukusutosi)

MySQLのカバリングインデックスは、Disk I/Oの削減に非常に効果的で常用されるようなクエリのパフォーマンスを大幅に向上させます。

## PostgreSQLのカバリングインデックス
PostgreSQLでは、インデックスに含まれるすべての列がクエリで使用されている場合でも、テーブルへのアクセスが必要になります。これは、PostgreSQLがインデックスに含まれる列の値を直接返すことができないためです。

ただし、例外的に条件を満たせばテーブルアクセスを避けることができます。それがインデックスオンリースキャン(Index Only Scan)です。
インデックスオンリースキャンの条件はVACUUM 後に未更新のページに限られます。つまり、頻繁に更新されるテーブルではインデックスオンリースキャンは活用できません。

実際に更新がされないテーブルであれば、インデックスオンリースキャンが活用できる可能性がありますが、実務ではアプリケーション側でcacheを活用するケースが多くなるため、インデックスオンリースキャンを前提とした設計はあまり現実的ではありません。

# 全文検索

　全文検索は、テキストデータの中から特定のキーワードやフレーズを効率的に検索するための技術です。
MySQLとPostgreSQLの両方で全文検索をサポートしていますが、実装や機能にいくつかの違いがあります。

## MySQLの全文検索
MySQLにはB-treeインデックスと全文検索インデックス（フルテキストインデックス）があります。
InnoDBストレージエンジンでは、全文検索インデックスはMyISAMストレージエンジンでのみサポートされていましたが、MySQL 5.6以降ではInnoDBでもサポートされています。
ただし、InnoDBの全文検索インデックスはMyISAMに比べて機能が制限が多く、すべてのユースケースをカバーできるわけではありません。

実務では、可能であればMroongaやElasticSearchなどの外部の全文検索エンジンを利用することになるでしょう。

# PostgreSQLの全文検索

PostgreSQLの全文検索も、MySQL同様に様々な拡張があり、反面、標準ではサポートしていません。
マルチバイト文字の全文検索では今回は最も簡単に利用できる[pg_bigm](https://pgbigm.github.io/pg_bigm/index.html)が標準的に利用されます。

pg_bigmの特徴は、既存の `LIKE %{文字列}%` による部分一致検索のためのインデックスを作成して高速化することです。
そのため、MySQLとは異なり、全文検索インデックスを作成したあとにSQLそのものを変更する必要がありません。

Cloudサービスのマネージドサービスを利用している場合は、拡張のインストールはマネージドサービスのドキュメントを参考にしてください。
Amazon RDSやGCPのCloud SQLでは、最初からpg_bigmがインストールされているので、そのまま利用できます。

Mroongaと同様にPGroongaもあります。
pg_bigmと細かい違いはありますが、実務上で選択基準になる差異は検索の特性とインデックスの作成とサイズです。

検索特性の違いとして検索対象の文字列が長くなればなるほど、PGroongaにパフォーマンスの優位性が出てきます。
またhit数が多い場合もPGroongaの方が有利であり、pg_bigmは2文字以上のhit数が多い場合にパフォーマンスが低下します。
それに対し、PGroongaはhit数が多くてもパフォーマンスが安定しており、データ量が増えてhit数が多くなるようなケースの場合もPGroongaが有利です。

それに対し、pg_bigmはhit数が少なく、短い文字列の部分一致検索に強く、地名や建物名、タイトルなどの検索に向いています。
例えばウィキペディアのタイトルを検索するならpg_bigm、ウィキペディアの本文を検索するならPGroongaが向いていると言えるでしょう。

インデックスについてはPGroongaはインデックスのサイズが大きくなる傾向があります。
インデックスの作成自体はPGroongaの方が2倍程度に早いのですが、インデックスのサイズは概ね5倍程度のサイズになります。


# その他のINDEXの違い

PostgreSQLはこれ以外にもHashインデックス、GiSTインデックス、GINインデックス、BRINインデックスなど多様なインデックスをサポートしています。

実務では、MySQLと同様にB-treeインデックスを選ぶことが多いでしょう。
しかしJSONB型や配列型に対して、GINインデックスを利用することでパフォーマンスを大幅に向上できるケースがありますし、 `created_at` のような時系列データのように連続した値に対してはBRINインデックスを活用することでインデックスサイズを大幅に削減できます。

　またMySQL 8.0.13から導入された関数ベースインデックスもPostgreSQLではサポートされています。
関数ベースインデックスは、列の値に基づいて計算された値に対してインデックスを作成することができます。
例えば、文字列の大文字・小文字を区別しない検索や、`YYYY-mm-dd` のような日付に対して年のYYYYで検索したい、など文字の一部に基づく検索を高速化させることができます。

```sql
-- 名前を小文字に変換してインデックスを作成
CREATE INDEX idx_lower_username ON users (LOWER(username));

-- PostgreSQLの日付の一部を抽出してインデックスを作成
CREATE INDEX idx_year_created_at ON orders (EXTRACT(YEAR FROM created_at));
```

- 参考: [PostgreSQLのインデックスを使い倒す](https://www.postgresql.jp/sites/default/files/2020-11/20201113_index_talk.pdf)

# パラレルクエリ

MySQLとPostgreSQLの大きな違いの中にパラレルクエリのサポートがあります。

- [パラレルクエリ](https://www.postgresql.jp/document/17/html/parallel-query.html)

```sql
EXPLAIN SELECT * FROM pgbench_accounts WHERE filler LIKE '%x%';
                                     QUERY PLAN
-------------------------------------------------------------------​------------------
 Gather  (cost=1000.00..217018.43 rows=1 width=97)
   Workers Planned: 2
   ->  Parallel Seq Scan on pgbench_accounts  (cost=0.00..216018.33 rows=1 width=97)
         Filter: (filler ~~ '%x%'::text)
(4 rows)
```

> クエリがデータを書き込むか、データベースの行をロックする場合。 クエリがデータ更新操作をトップレベルあるいはCTE内で含むと、そのクエリに対するパラレルプランは生成されません。 例外として、新しいテーブルを作成したりデータを追加したりする次のコマンドでは、そのクエリのSELECT部分に対してパラレルプランが使用できます。

引用元: https://www.postgresql.jp/document/17/html/when-can-parallel-query-be-used.html

かならずしもパラレルクエリを使ってくれるわけではなく、また使っているバージョンによっても対象が異なるため、利用しているPostgreSQLのバージョンのドキュメントを確認してください。
例えば、NLJで結合している場合、JOINの片方が大きなテーブルであればパラレルクエリを使ってくれますが、両方とも小さなテーブルであればパラレルクエリを使ってくれないケースが多く、Hash Joinであれば両方とも大きなテーブルであってもパラレルクエリを使って改善するケースがあります。

# パーテーション
パーテーションはMySQLに対しPostgreSQLは後発ですが、昨今では強力な機能を多数備えています。

[パーティショニングの概要](https://www.fujitsu.com/jp/products/software/resources/feature-stories/postgres/article-index/partitioning-overview/)

[パーティショニングにおける性能向上のしくみ](https://www.fujitsu.com/jp/products/software/resources/feature-stories/postgres/article-index/partitioning-performanceup/)

PostgreSQLとMySQLのパーテーションで大きな違いの一つに外部キー制約があります。
MySQLではパーテーションをまたいだ外部キー制約をサポートしていませんが、PostgreSQLではパーテーションをまたいだ外部キー制約をサポートしています。

パーテーションは外部キー制約の子にも親にもなることができますが、子になる場合は外部キー制約だけではインデックスを作成しないため、パフォーマンスに注意が必要です。
パーテーションはレコードが増える前提で設計するため、外部キー制約の子に設定する場合は、外部キー制約の対象の列に対してインデックスを作成することを忘れないようにしましょう。
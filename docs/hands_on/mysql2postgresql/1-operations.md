# MySQLを使う人がPostgreSQLを使うときに知っておくべきこと
このドキュメントでは、MySQLを使う人がPostgreSQLを使うときに知っておくべき基本的な操作や概念の違いについて説明します。

# 目次
1. インストール
1. DDL
1. インデックス
1. JSON型
1. ユーザと権限
1. バックアップとリストア

# インストール
MySQLとPostgreSQLのインストール方法は異なります。
以下にPostgreSQLの基本的なインストール手順を示します。

## コマンドによるインストール

パッケージ管理システムを使用してPostgreSQLをインストールします。

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install postgresql postgresql-contrib
```

データベースを作成します。

```bash
sudo -i -u postgres
createuser -P dbuser
# --no-locale と locakle=Cは同義
-- オプションを指定しない場合はOSのエンコード、ロケールが使われる
createdb -E UTF8 --locale=C --template=template0 mydb
psql mydb

mydb=# SELECT name, setting, context FROM pg_settings WHERE name LIKE 'lc%';
name | setting | context
-------------+---------+-----------
lc_collate | C | internal
lc_ctype | C | internal
lc_messages | C | superuser
lc_monetary | C | user
lc_numeric | C | user
lc_time | C | user

mydb=# SHOW clie    nt_encoding;
```

大きな注意点としてエンコードとロケールは必ず設定するようにしましょう。
ここは後から変更できません。つまり、実務上問題がでた場合、データベースを再作成し、データを移行する必要があります。
当然、データが大きくなり、ダウンタイムが許されない場合は難易度の高い作業になります。

## PostgreSQLのTemplate
PostgreSQLではデータベースを作成する際に、templateという仕組みを使います。
template0はPostgreSQLがインストールされた直後の状態を保持しているテンプレートです。
template1はtemplate0を元に、ユーザが作成したオブジェクトを含むテンプレートです。
Templateを指定されない場合、通常はtemplate1を使いますが、エンコードやロケールを変更したい場合はtemplate0を指定して、データベースを作成する必要があります。
そのためtemplate0を使うために、`--template=template0` を指定します。

実務の例では、RDSのPostgreSQLを使う場合に、RDSのPostgreSQLはtemplate1を変更できないため、template0を指定してデータベースを作成する必要があります。

## 文字コードとロケールの設定
PostgreSQLはデータベースの際にロケールを指定しない場合、OS側に設定されているロケールを使用します。日本語の環境ならja_JP.UTF-8が選ばれます。
しかし、RDSの場合は `en_US.UTF-8` が選ばれます。これに伴いDBが壊れることはありませんし、エラーなどもありません。ただし、文字コードに関する細かいソートやチェックなど文字関連に影響し、OSに依存してしまうことから、意図しない挙動をすることがあります。
特に開発環境において、OSのロケールが異なる場合、同じクエリであっても異なる結果になることがありますので統一するようにしましょう。

それを防ぐためにPostgreSQLでは一般的に、エンコードとロケールとして明示的指定します。
一般的にはロケールにはCを指定します。これにより、OSに依存することなく、バイナリ値を基準にした一定のソートが行われ、ORDER BYの性能も向上します。

ロケールにCを指定するには、前述の手順のとおり--no-localeを指定するか、--locale=Cを指定します。--no-localeと--locale=Cは同義ですのでどちらでもかまいません。

エンコードは多くの環境ではデフォルトでUTF8が指定されますが、念のため-E UTF8を指定することをお勧めします。
古い環境などの場合には、デフォルトがSQL_ASCIIになっている場合があります。
SQL_ASCIIの場合はマルチバイト文字が文字化けすることになり、実務では運用できないため、必ずUTF8を指定するようにしましょう。

再三の注意ですが、もし指定し忘れた場合、基本的にはDBを作りなおすことになるため、無停止では変更できないと思ってください。運用が走り出すと変更がしにくい箇所ですので、最初の構築が重要です

## 注意点
PostgreSQLに限らず、MySQLでも同様ですが、データベースを作成時は必ずTimeZoneを確認しましょう。
こちらもデフォルトではOSのタイムゾーンが使われます。
しかしRDSのデフォルトはUTCになっているため、容易に開発環境と本番環境でタイムゾーンが異なることになり、意図しない挙動をすることがあります。
特にtimestamp with timezone型を使う場合に意図しない時間が保存されることで、時間がずれることになります。

ただし、PostgreSQLでもtimezoneはあとから `set timezone 'Asia/Tokyo';` のように変更できますが、データのズレは修正が必要になるため、やはり最初に確認することが重要です。

## アクセス制限
PostgreSQLのアクセス制限はpg_hba.confというファイルとpostgresql.confというファイルで設定します。
pg_hba.confはホストベースのアクセス制御を行うファイルで、接続元IPアドレス、データベース名、ユーザ名、認証方法などを設定します。
postgresql.confはPostgreSQLの全般的な設定を行うファイルで、リスニングアドレス、ポート番号、ログ設定などを設定します。

これらのファイルはPostgreSQLのデータディレクトリにあります。
通常、デフォルトではlocalhostからの接続のみ許可されています。
外部からの接続を許可する場合は、pg_hba.confに適切な設定を追加し、postgresql.confでlisten_addressesを設定する必要があります。
設定を変更した後は、PostgreSQLを再起動する必要があります。
RDSｎ場合は、自然と設定されているので、特に意識する必要はありませんが、ローカルの開発環境等でPostgreSQLを使う場合は注意してください。

# DDL
MySQLとPostgreSQLのDDLにはいくつかの違いがあります。以下に主要な違いを示します。

todo: 文字列型の大文字小文字の違い
todo: バイナリの違い
todo: 日付時刻の違い
todo: JSONの違い
## 型の違い
| 概念/用途 | PostgreSQL                                                                                        | MySQL                                                                         | 違い・注意点                                                                                                                     |                                                                        |
| ----- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 整数    | `SMALLINT` (2B)<br>`INTEGER`/`INT` (4B)<br>`BIGINT` (8B)                                          | `SMALLINT` (2B)<br>`INT`/`INTEGER` (4B)<br>`BIGINT` (8B)                      | サイズと範囲はほぼ同じ。MySQL の `UNSIGNED` は PostgreSQL には無い。代替は `CHECK (col >= 0)` 制約。                                                |                                                                        |
| 自動採番  | \`GENERATED {BY DEFAULT                                                                           | ALWAYS} AS IDENTITY`（推奨）<br>`SERIAL`/`BIGSERIAL\`（古い書き方）                      | `AUTO_INCREMENT`                                                                                                           | PostgreSQL は **独立シーケンス**で管理し標準SQL準拠。MySQL はテーブルごとのカウンタ。Postgres の方が柔軟。 |
| 小数    | `NUMERIC(p,s)` / `DECIMAL(p,s)`（任意精度）<br>`REAL` (4B, IEEE) <br>`DOUBLE PRECISION` (8B, IEEE)      | `DECIMAL(p,s)`（任意精度）<br>`FLOAT(p)` (近似, 4/8B)<br>`DOUBLE` / `REAL` (8B, IEEE) | PostgreSQL の `NUMERIC` は厳密精度、`REAL/DOUBLE` はIEEE。MySQL の `FLOAT(M,D)` は古い表記で廃止推奨。                                          |                                                                        |
| 文字列   | `CHAR(n)`<br>`VARCHAR(n)`<br>`TEXT`                                                               | `CHAR(n)`<br>`VARCHAR(n)`<br>`TEXT`                                           | PostgreSQL は `TEXT` に長さ制限なし（実用上 `VARCHAR` と差なし）。MySQL は `TEXT` にサイズ区分（TINYTEXT/ TEXT/ MEDIUMTEXT/ LONGTEXT）。               |                                                                        |
| バイナリ  | `BYTEA`                                                                                           | `BLOB`（TINY/MEDIUM/LONG 区分あり）                                                 | PostgreSQL は1種類で管理。MySQL は用途ごとにサイズ別。                                                                                       |                                                                        |
| 日付/時刻 | `DATE`<br>`TIME [WITHOUT/ WITH TIME ZONE]`<br>`TIMESTAMP [WITHOUT/ WITH TIME ZONE]`<br>`INTERVAL` | `DATE`<br>`TIME`<br>`DATETIME`<br>`TIMESTAMP`                                 | PostgreSQL の `TIMESTAMP WITH TIME ZONE` は実際には **UTC変換＋TZ情報保持**。MySQL の `TIMESTAMP` は常に UTC に変換して保存。`INTERVAL` は MySQL 非対応。 |                                                                        |
| 論理値   | `BOOLEAN`（実体は `true/false`）                                                                       | `BOOLEAN`（実体は `TINYINT(1)`）                                                   | PostgreSQL は真の論理型。MySQL は整数で代替。                                                                                            |                                                                        |
| JSON  | `JSON` / `JSONB`                                                                                  | `JSON`                                                                        | PostgreSQL の `JSONB` は**バイナリ格納＋索引最適化可能**。MySQL の `JSON` は文字列格納＋関数群。Postgres の方が検索演算子や索引が豊富。                                |                                                                        |
| UUID  | `UUID`                                                                                            | `CHAR(36)` などで代替（MySQL 8.0.19 以降 `UUID()` 関数あり）                               | PostgreSQL は専用型を持ち、格納効率・演算子あり。MySQL は文字列やバイナリで実装。                                                                          |                                                                        |
| 配列    | `integer[]` など **配列型**あり                                                                          | 非対応                                                                           | PostgreSQL 独自の強力機能。MySQL は正規化か JSON で代替。                                                                                   |                                                                        |
| 列挙    | `ENUM`（型定義）                                                                                       | `ENUM`（列ごとに定義）                                                                | PostgreSQL の `ENUM` は型オブジェクトとして再利用可能。MySQL は列ごとに閉じた定義。                                                                     |                                                                        |
| 範囲    | `int4range`, `tsrange`, `tstzrange`, `daterange` など                                               | 非対応                                                                           | PostgreSQL 独自。予約や期間検索に有用。MySQL は BETWEEN などで代替。                                                                            |                                                                        |

## idの指定
MySQLのAUTO_INCREMENTに相当するものとして、PostgreSQLではSERIAL型やIDENTITY型があります。
どちらもMySQLと同様にintの範囲で自動的に連番を生成しますが、SERIAL型はPostgreSQLのバージョン10以降では非推奨となり、IDENTITY型の使用が推奨されています。

```sql
-- 基本形：アプリがIDを明示しない想定（多くのケース）
CREATE TABLE users (
  id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  name text NOT NULL
);

-- どうしてもアプリからIDを入れさせたくない場合
CREATE TABLE strict_users (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL
);

-- ALWAYS では手動INSERTはエラー。入れるなら:
-- INSERT ... OVERRIDING SYSTEM VALUE ...
-- BY DEFAULT … 値を指定したら“その値”を採用。未指定なら自動採番。
-- ALWAYS … 原則、常に自動採番。手動値は不可（ただし OVERRIDING SYSTEM VALUE を明示した場合のみ受け入れ）
```

IDENTITY型については、日本語では識別列と翻訳されており、公式ドキュメントでは識別列になっています。
MySQLとは違う大きな特徴の一つなのでドキュメントをチェックしておきましょう。
[PostgreSQL 識別列](https://www.postgresql.jp/docs/17/ddl-identity-columns.html)

## ALTERの違い

`ALTER` 構文に関してもMySQLとPostgreSQLではいくつかの違いがあります。

多少の構文の違いはありますが、基本的な操作は同様で、カラムの追加、削除、変更や、テーブルの名前変更などが可能です。

まず、MySQLではカラム単位で文字コードを指定できますが、PostgreSQLではデータベース単位できまり、あとから変更できません。

またロック範囲が大きく違い、MySQLのオンラインDDLのような書き込み可能なDDLはPostgreSQLにはなく、手順の工夫などで最小化することはできますが、最終的なロックは避けられません。
ロックの流動を最小化する手順の例については他社の事例をご覧ください。

- [令和最新版: PostgreSQLの安全なSET NOT NULL](https://www.wantedly.com/companies/wantedly/post_articles/433252)
- [PostgreSQLで安全にテーブル定義を変更する](https://techblog.lclco.com/entry/2018/01/24/070000)
- [ALTER TABLEの各コマンドのロックレベル](https://masahikosawada.github.io/2023/05/08/Lock-Levels-Of-ALTER-TABLE/)
  - このブログはPostgreSQL 15までの情報ですが、PostgreSQL17まででも大きな変更はありません。

# インデックス
MySQLとPostgreSQLのインデックスにはいくつかの違いがあります

## CREATE INDEX CONCURRENTLY
PostgreSQLでは、インデックスを作成する際に`CONCURRENTLY`オプションを使用することで、テーブルのロックを最小限に抑えながらインデックスを作成できます。これにより、インデックス作成中もテーブルへの読み書きが可能です。

```sql
-- 書き込みを止めずに作る（失敗してもテーブルはそのまま）
CREATE INDEX CONCURRENTLY idx_orders_created_at
  ON orders (created_at);

-- 併走DDLの可視化（作成中の未VALIDなindex監視）
SELECT schemaname, tablename, indexname, indisvalid
FROM pg_indexes AS i
JOIN pg_class   AS c   ON c.relname = i.indexname
JOIN pg_index   AS idx ON idx.indexrelid = c.oid
WHERE NOT idx.indisvalid;
```

CREATE INDEX CONCURRENTLYはロックをとらないというメリットの反面、テーブルスキャンを2回行うため、通常のCREATE INDEXよりも時間がかかります。インデックス作成時に追加されたデータを後から反映させるために、2回目のスキャンが必要になるためです。
またインデックス作成中にDDLが走ると失敗することがありますし、データの更新量が多いと作成が追い付かず、失敗することがあります。
そのため、インデックス作成中に大量の更新が発生することが予想される場合は、メンテナンスウィンドウを設けて、ロックを取った通常のCREATE INDEXを使用するか、新たなテーブルやカラムを追加して、インデックスを作成し、データを移行する方法を検討してください。

## インデックスの種類
PostgreSQLでは、B-treeインデックスの他に、Hashインデックス、GINインデックス、GiSTインデックス、BRINインデックスなど、さまざまな種類のインデックスが利用できます。これにより、特定のクエリパターンに最適化されたインデックスを作成できます。

## インデックスのメンテナンス
PostgreSQLでは、追記型の特性上、MySQLよりも断片化が起こりやすいという課題があります。
テーブルの更新が頻繁に行われる場合、インデックスの断片化が発生し、パフォーマンスが低下することがあります。
その際には`REINDEX`コマンドを使用してインデックスを再構築することで改善します。
類似の例で

## インデックスの確認
PostgreSQLでは、`pg_indexes`ビューを使用して、データベース内のインデックスを確認できます。  

# JSON型
MySQLのJSON型とPostgreSQLのJSON型にはいくつかの違いがあります。
## JSON型とJSONB型
- todo : あとで書く
## JSON関数と演算子
- todo : あとで書く

# ユーザと権限
MySQLとPostgreSQLのユーザ管理と権限付与にはいくつかの違いがあります。

## ユーザの作成

- [PostgreSQLの権限管理 ～ アカウントの操作とRow Level Securityの活用 ～ / pgcon2022-tutorial](https://speakerdeck.com/soudai/pgcon2022-tutorial)
- [PostgreSQLのロール管理とその注意点（Open Source Conference 2022 Online/Osaka 発表資料）](https://www.slideshare.net/nttdata-tech/postgresql-roles-osc2022-online-osaka-nttdata)
- [PostgreSQLのロール](https://qiita.com/nuko_yokohama/items/085b75ee4c0938936ab9)
- [公式ドキュメント:PostgreSQLの権限管理](https://www.postgresql.jp/document/current/html/user-manag.html)
- [事前定義ロール（旧：デフォルトロール）](https://www.postgresql.jp/docs/17/predefined-roles.html)

# バックアップとリストア

- [PostgreSQLバックアップ基礎講座](https://www.sraoss.co.jp/wp-content/uploads/files/event_seminar/material/2024/OSC_SRAOSS_Backup_20240301_v2.pdf)
- [技術を知る：PostgreSQLのバックアップとリカバリー ～大量データの高速バックアップ～｜PostgreSQLインサイド](https://www.fujitsu.com/jp/products/software/resources/feature-stories/postgres/highspeed-backup/)
- [【Part1】PostgreSQLバックアップ基礎講座 ～ PostgreSQLのバックアップ手法 ～](https://www.youtube.com/watch?v=u_ky6US7FXo)
- [【Part2】PostgreSQLバックアップ基礎講座 ～ 論理バックアップ・物理バックアップ ～](https://www.youtube.com/watch?v=dFRnmZezJz8)
- [【T1】PostgreSQLバックアップ実践とバックアップ管理ツールの紹介](https://www.youtube.com/watch?v=aQo0IFjiTuM)

## PTIR
- [PostgreSQLの周辺ツール ～ pg_rmanでバックアップ・リカバリーを管理する ～](https://www.fujitsu.com/jp/products/software/resources/feature-stories/postgres/pgrman/)
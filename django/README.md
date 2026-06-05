# Django PostgreSQL Sample Tutorial

このディレクトリには、公開記事「[Djangoで便利なPostgreSQLの活用方法](https://soudai.hatenablog.com/entry/2026/06/05/153530)」で紹介している Django + PostgreSQL のサンプルを Docker 上で動かすための最小プロジェクトを置いています。

README は起動手順と確認ポイントの入口です。現在の Docker 環境で取得したコマンド実行結果は [tutorial.md](tutorial.md) にまとめています。

確認できる内容は以下です。

- `JSONField` / `jsonb` の絞り込み、ネスト値検索、包含検索、キー存在検索
- `ArrayField` の `contains` / `overlap`
- `DateTimeRangeField` と範囲型演算子
- `pgvector` による RAG チャンクのベクトル類似検索
- `ExclusionConstraint` による重複予約の防止
- `UniqueConstraint(condition=...)`、`CheckConstraint`、`UNIQUE NULLS NOT DISTINCT`
- 部分インデックス、関数インデックス、カバリングインデックス
- 全文検索、`pg_trgm` による Trigram 類似検索、部分一致検索
- `SELECT ... FOR UPDATE SKIP LOCKED`
- パーティショニング
- `MERGE`
- GIN / GiST / HNSW index の定義確認
- `EXPLAIN` / `EXPLAIN ANALYZE` による実行計画確認

この Docker サンプルでは標準の PostgreSQL + pgvector イメージで検証できる内容を扱います。PostGIS、`pg_bigm`、`CREATE INDEX CONCURRENTLY` の本番運用例は記事本文の説明対象ですが、このサンプルの実行ログには含めていません。

## 前提

Docker Compose が使える環境を前提にしています。

最初に Docker Compose が使えることを確認します。

```bash
docker compose version
```

ここで `docker: command not found` や `Cannot connect to the Docker daemon` が出る場合は、Django の問題ではなく Docker 環境の問題です。Docker Desktop や Docker Engine を起動してから、もう一度実行してください。

このサンプルでは以下のコンテナを起動します。

- `db`: PostgreSQL 18 + pgvector
- `web`: Django 5.2.15

利用するポートは以下です。

- Django: `localhost:8000`
- PostgreSQL: `localhost:5433`

## 1. サンプルを起動する

リポジトリルートから `django/` に移動して、コンテナを起動します。

```bash
cd django
docker compose up --build -d
```

起動時に `web` コンテナでは以下が順番に実行されます。

```bash
python manage.py migrate
python manage.py load_sample_data
python manage.py runserver 0.0.0.0:8000
```

ログを確認します。

```bash
docker compose logs web
```

初回起動で正常にマイグレーションが完了していれば、ログには以下のような内容が出ます。

```text
Applying sampleapp.0001_initial... OK
Applying sampleapp.0002_memo_samples... OK
Sample data loaded
Starting development server at http://0.0.0.0:8000/
```

すでに DB ボリュームがある場合は、マイグレーション部分が `No migrations to apply.` になることがあります。

## 2. ヘルスチェックを確認する

```bash
curl http://localhost:8000/
```

実行結果:

```json
{"status": "ok"}
```

## 3. 記事サンプルの結果を確認する

```bash
curl http://localhost:8000/sample/
```

実行結果:

```json
{
  "jsonfield": {
    "paid_events_count": 1,
    "customer_events_count": 1,
    "livemode_events_count": 1,
    "events_with_customer_count": 2
  },
  "arrayfield": {
    "contains_postgresql": [
      "PostgreSQL and Django"
    ],
    "overlap_django_or_postgresql": [
      "PostgreSQL and Django",
      "Only Django",
      "Django full text search"
    ]
  },
  "rangefield": {
    "active_campaigns": [
      "Now Active Campaign"
    ]
  },
  "pgvector": {
    "query_embedding": [
      0.9,
      0.1,
      0.2
    ],
    "nearest_chunks": [
      {
        "title": "JSONField and jsonb",
        "distance": 0.0
      },
      {
        "title": "pgvector for RAG",
        "distance": 0.004004
      }
    ]
  },
  "constraints": {
    "reservation_overlap_blocked": true,
    "duplicate_draft_blocked": true
  }
}
```

それぞれの結果は以下を表します。

- `paid_events_count`: `provider` と `event_type` で `WebhookEvent` を絞り込めている
- `customer_events_count`: `payload__customer__id` で JSON 内のネストした値を検索できている
- `livemode_events_count`: `payload__contains` で JSON 包含検索ができている
- `events_with_customer_count`: `payload__has_key="customer"` で JSON キーの存在を検索できている
- `contains_postgresql`: `tags__contains=["postgresql"]` で配列検索ができている
- `overlap_django_or_postgresql`: `tags__overlap=["django", "postgresql"]` で配列の重なりを検索できている
- `active_campaigns`: `active_period__contains=timezone.now()` で現在有効な範囲型を検索できている
- `nearest_chunks`: `CosineDistance("embedding", query_embedding)` で近い RAG チャンク順に検索できている
- `reservation_overlap_blocked`: `ExclusionConstraint` により、同じ部屋の重複予約が DB で拒否されている
- `duplicate_draft_blocked`: `UniqueConstraint(condition=...)` により、同じユーザーの下書き重複が DB で拒否されている

## 4. 詳細な実行ログを確認する

[tutorial.md](tutorial.md) には、この README のサンプルを現在の Docker 環境で実行したコマンドと実行結果を掲載しています。

主に以下を確認できます。

- Docker Compose の起動、コンテナ状態、起動ログ
- `/` と `/sample/` のレスポンス
- `btree_gist`、`pg_trgm`、`vector` 拡張の有効化
- Django モデルから作られた DB 定義
- JSON / Array / Range / pgvector の `EXPLAIN`
- `memo.md` と記事本文で紹介している SQL サンプルの実行結果

README では代表的なコマンドだけを載せています。実際の出力まで追う場合は [tutorial.md](tutorial.md) を参照してください。

## 5. モデル定義と DB 定義を確認する

Django 側のモデルは [src/sampleapp/models.py](src/sampleapp/models.py) にあります。

DB 側のテーブル、インデックス、制約は `psql` で確認できます。

```bash
docker compose exec db psql -U django_user -d django_sample
```

`psql` に入ったら、まず拡張を確認します。

```sql
SELECT extname
FROM pg_extension
WHERE extname IN ('btree_gist', 'pg_trgm', 'vector')
ORDER BY extname;
```

主要な DB 定義は以下で確認できます。

```sql
\d sampleapp_webhookevent
\d sampleapp_productattribute
\d sampleapp_article
\d sampleapp_campaign
\d sampleapp_ragchunk
\d sampleapp_reservation
\d sampleapp_draftarticle
\d sampleapp_externalaccount
\d sampleapp_customer
\d sampleapp_importjob
\d event_log
\d event_log_2026_06
\d sampleapp_stock
```

確認するポイント:

- `sampleapp_webhookevent` に `webhook_payload_path_gin` がある
- `sampleapp_productattribute` に `product_attrs_gin` がある
- `sampleapp_article` に `article_tags_gin` がある
- `sampleapp_campaign` に `campaign_active_period_gist` がある
- `sampleapp_ragchunk` に `rag_chunk_embedding_hnsw` があり、`embedding vector(3)` になっている
- `sampleapp_reservation` に `exclude_overlapping_reservations` がある
- `sampleapp_draftarticle` に `unique_draft_article_per_user` と `draft_article_valid_status` がある
- `sampleapp_externalaccount` に `NULLS NOT DISTINCT` のユニーク制約がある
- `sampleapp_customer` に部分インデックス、関数インデックス、カバリングインデックスがある
- `event_log` がパーティション親テーブルとして作られ、`event_log_2026_06` が子テーブルとして作られている

## 6. 実行計画を確認する

`psql` で以下を実行します。

```sql
EXPLAIN
SELECT id
FROM sampleapp_webhookevent
WHERE payload @> '{"livemode": true}'::jsonb;
```

JSON 包含検索の実行計画を確認できます。

```sql
EXPLAIN
SELECT id
FROM sampleapp_article
WHERE tags @> ARRAY['postgresql']::varchar(50)[];
```

配列の `contains` 検索の実行計画を確認できます。

```sql
EXPLAIN
SELECT id
FROM sampleapp_campaign
WHERE active_period @> now();
```

範囲型の `contains` 検索の実行計画を確認できます。

```sql
EXPLAIN
SELECT id, title
FROM sampleapp_ragchunk
ORDER BY embedding <=> '[0.9,0.1,0.2]'::vector
LIMIT 2;
```

pgvector の cosine 距離による近傍検索の実行計画を確認できます。`<=>` は cosine 距離の演算子です。

このサンプルはデータ件数が少ないため、実行計画が `Seq Scan` になることがあります。これはインデックス定義が間違っているという意味ではありません。PostgreSQL は小さいテーブルでは、インデックスを読むよりテーブルを直接読む方が安いと判断することがあります。

実データに近い条件で確認する場合は、十分な件数を投入したうえで以下のように確認します。

```sql
ANALYZE;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id
FROM sampleapp_webhookevent
WHERE payload @> '{"livemode": true}'::jsonb;
```

## 7. memo.md の SQL サンプルを実行する

[tutorial.md](tutorial.md) の「memo.md のサンプルを SQL で実行する」では、記事本文の SQL を `psql` から実行できる形で整理しています。

代表的には以下のような SQL を確認できます。

```sql
SELECT sku, attrs
FROM sampleapp_productattribute
WHERE attrs @> '{"color": "red"}'::jsonb;
```

```sql
SELECT id, title, embedding <=> '[0.9,0.1,0.2]'::vector AS distance
FROM sampleapp_ragchunk
ORDER BY embedding <=> '[0.9,0.1,0.2]'::vector
LIMIT 2;
```

```sql
BEGIN;

SELECT id, payload
FROM sampleapp_importjob
WHERE status = 'queued'
ORDER BY id
FOR UPDATE SKIP LOCKED
LIMIT 1;

ROLLBACK;
```

```sql
MERGE INTO sampleapp_stock AS target
USING (
  VALUES
    ('A-001', 12, '2026-06-05 16:00:00+09'::timestamptz),
    ('C-003', 5, '2026-06-05 16:00:00+09'::timestamptz)
) AS source(sku, quantity, seen_at)
ON target.sku = source.sku
WHEN MATCHED THEN
  UPDATE SET quantity = source.quantity, seen_at = source.seen_at
WHEN NOT MATCHED THEN
  INSERT (sku, quantity, seen_at)
  VALUES (source.sku, source.quantity, source.seen_at);
```

全文検索、Trigram 類似検索、部分一致検索、パーティショニング、`UNIQUE NULLS NOT DISTINCT`、各種インデックスの実行結果も [tutorial.md](tutorial.md) に掲載しています。

## 8. 制約が効いていることを直接確認する

`/sample/` は内部で重複予約と重複下書きを作ろうとします。どちらも DB 制約で拒否されるため、結果は `true` になります。

```json
{
  "constraints": {
    "reservation_overlap_blocked": true,
    "duplicate_draft_blocked": true
  }
}
```

ここで重要なのは、アプリケーション側の事前チェックではなく、最後は DB 制約が整合性を守っていることです。

## 9. 停止する

```bash
docker compose down
```

DB ボリュームも削除して最初からやり直す場合:

```bash
docker compose down -v
```

## トラブルシュート

### `localhost:8000` が使われている

`docker-compose.yml` の `web.ports` を変更します。

```yaml
ports:
  - "8001:8000"
```

変更後は以下で起動し直します。

```bash
docker compose up --build -d
```

### `localhost:5433` が使われている

`docker-compose.yml` の `db.ports` を変更します。

```yaml
ports:
  - "5434:5432"
```

### サンプルデータを初期化したい

DB ボリュームを削除して起動し直します。

```bash
docker compose down -v
docker compose up --build -d
```

DB を消さずにサンプルデータだけ入れ直したい場合は、以下を実行します。

```bash
docker compose exec web python manage.py load_sample_data
```

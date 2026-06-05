# Django PostgreSQL Sample Tutorial

このディレクトリには、`memo.md` の記事で紹介している Django + PostgreSQL のサンプルを Docker 上で動かすための最小プロジェクトを置いています。

確認できる内容は以下です。

- `JSONField` の絞り込み
- `ArrayField` の `contains` / `overlap`
- `DateTimeRangeField` の `contains`
- `pgvector` によるベクトル類似検索
- `ExclusionConstraint` による重複予約の防止
- `UniqueConstraint(condition=...)` による下書き重複の防止
- GIN / GiST / HNSW index の定義確認
- `EXPLAIN` による実行計画確認

## 前提

Docker Compose が使える環境を前提にしています。

最初に Docker Compose が使えることを確認します。

```bash
docker compose version
```

ここで `docker: command not found` や `Cannot connect to the Docker daemon` が出る場合は、Djangoの問題ではなくDocker環境の問題です。
Docker DesktopやDocker Engineを起動してから、もう一度実行してください。

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

正常に起動していれば、ログには以下のような内容が出ます。

```text
Applying sampleapp.0001_initial... OK
Sample data loaded
Starting development server at http://0.0.0.0:8000/
```

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
- `customer_events_count`: `payload__customer__id` でJSON内のネストした値を検索できている
- `livemode_events_count`: `payload__contains` でJSON包含検索ができている
- `events_with_customer_count`: `payload__has_key="customer"` でJSONキーの存在を検索できている
- `contains_postgresql`: `tags__contains=["postgresql"]` で配列検索ができている
- `overlap_django_or_postgresql`: `tags__overlap=["django", "postgresql"]` で配列の重なりを検索できている
- `active_campaigns`: `active_period__contains=timezone.now()` で現在有効な範囲型を検索できている
- `nearest_chunks`: `CosineDistance("embedding", query_embedding)` で近いRAGチャンク順に検索できている
- `reservation_overlap_blocked`: `ExclusionConstraint` により、同じ部屋の重複予約がDBで拒否されている
- `duplicate_draft_blocked`: `UniqueConstraint(condition=...)` により、同じユーザーの下書き重複がDBで拒否されている

## 4. モデル定義とDB定義を確認する

Django側のモデルは [src/sampleapp/models.py](src/sampleapp/models.py) にあります。

DB側のテーブル、インデックス、制約は `psql` で確認できます。

```bash
docker compose exec db psql -U django_user -d django_sample
```

`psql` に入ったら、以下を実行します。

```sql
\d sampleapp_webhookevent
\d sampleapp_article
\d sampleapp_campaign
\d sampleapp_ragchunk
\d sampleapp_reservation
\d sampleapp_draftarticle
```

確認するポイント:

- `sampleapp_webhookevent` に `webhook_payload_path_gin` がある
- `sampleapp_article` に `article_tags_gin` がある
- `sampleapp_campaign` に `campaign_active_period_gist` がある
- `sampleapp_ragchunk` に `rag_chunk_embedding_hnsw` があり、`embedding vector(3)` になっている
- `sampleapp_reservation` に `exclude_overlapping_reservations` がある
- `sampleapp_draftarticle` に `unique_draft_article_per_user` と `draft_article_valid_status` がある

## 5. 実行計画を確認する

`psql` で以下を実行します。

```sql
EXPLAIN
SELECT id
FROM sampleapp_webhookevent
WHERE payload @> '{"livemode": true}'::jsonb;
```

JSON包含検索の実行計画を確認できます。

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

pgvector の cosine 距離による近傍検索の実行計画を確認できます。
`<=>` は cosine 距離の演算子です。

このサンプルはデータ件数が少ないため、実行計画が `Seq Scan` になることがあります。
これはインデックス定義が間違っているという意味ではありません。
PostgreSQLは小さいテーブルでは、インデックスを読むよりテーブルを直接読む方が安いと判断することがあります。

実データに近い条件で確認する場合は、十分な件数を投入したうえで以下のように確認します。

```sql
ANALYZE;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id
FROM sampleapp_webhookevent
WHERE payload @> '{"livemode": true}'::jsonb;
```

## 6. 制約が効いていることを直接確認する

`/sample/` は内部で重複予約と重複下書きを作ろうとします。
どちらもDB制約で拒否されるため、結果は `true` になります。

```json
{
  "constraints": {
    "reservation_overlap_blocked": true,
    "duplicate_draft_blocked": true
  }
}
```

ここで重要なのは、アプリケーション側の事前チェックではなく、最後はDB制約が整合性を守っていることです。

## 7. 停止する

```bash
docker compose down
```

DBボリュームも削除して最初からやり直す場合:

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

DBボリュームを削除して起動し直します。

```bash
docker compose down -v
docker compose up --build -d
```

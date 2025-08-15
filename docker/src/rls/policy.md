# Row Level Security policy (based on rls_key)

このドキュメントは、`demo` スキーマの `company` と `organization` に対して、`rls_key` を用いた Row Level Security (RLS) を有効化するためのポリシー SQL をまとめたものです。

- 前提スキーマ/テーブル: `docker/src/rls/ddl.sql` に準拠
- セッション変数: `demo.rls_key` に UUID を設定（`rls_key.key` 列の値）
- アクセス許可の単位: `rls_company_group`（`rls_key` と `company` の対応）
- `organization` は `organization_chart` を介して `company` に紐付けて判定

## セッション変数の扱い

- セッションごとに、アクセスを許可したい `rls_key.key` の UUID を `demo.rls_key` へ設定します。
- 未設定時は参照できる行がゼロになります（deny-by-default）。

例:

```sql
-- セッションローカルに RLS キーを設定（UUID は rls_key.key の値）
SELECT set_config('demo.rls_key', '00000000-0000-0000-0000-000000000000', true);

-- 解除（NULL/未設定相当に）
SELECT set_config('demo.rls_key', NULL, true);
```

## 事前推奨インデックス（任意）
`organization` 判定で `organization_chart` を参照するため、以下のインデックスがあると良いです（存在しなければ作成してください）。

```sql
CREATE INDEX IF NOT EXISTS organization_chart_organization_id_idx ON demo.organization_chart(organization_id);
CREATE INDEX IF NOT EXISTS rls_company_group_company_id_idx ON demo.rls_company_group(company_id);
CREATE INDEX IF NOT EXISTS rls_company_group_rls_key_id_idx ON demo.rls_company_group(rls_key_id);
```

## ポリシー定義 SQL（一括適用可）

```sql
SET search_path TO demo, public;

-- 1) company に対する RLS 有効化とポリシー
ALTER TABLE demo.company ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.company FORCE ROW LEVEL SECURITY;

-- 既存ポリシーがあれば除去
DROP POLICY IF EXISTS company_rls_by_key ON demo.company;

-- rls_key -> rls_company_group にマッチする company のみ可視化/変更可
CREATE POLICY company_rls_by_key ON demo.company
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
      WHERE rk.key = current_setting('demo.rls_key', true)::uuid
        AND cg.company_id = company.id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
      WHERE rk.key = current_setting('demo.rls_key', true)::uuid
        AND cg.company_id = company.id
    )
  );

-- 2) organization に対する RLS 有効化とポリシー
ALTER TABLE demo.organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.organization FORCE ROW LEVEL SECURITY;

-- 既存ポリシーがあれば除去
DROP POLICY IF EXISTS organization_rls_by_key ON demo.organization;

-- rls_key -> rls_company_group にマッチする company 配下の organization のみ可視化/変更可
CREATE POLICY organization_rls_by_key ON demo.organization
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
      JOIN demo.organization_chart oc ON oc.company_id = cg.company_id
      WHERE rk.key = current_setting('demo.rls_key', true)::uuid
        AND oc.organization_id = organization.id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
      JOIN demo.organization_chart oc ON oc.company_id = cg.company_id
      WHERE rk.key = current_setting('demo.rls_key', true)::uuid
        AND oc.organization_id = organization.id
    )
  );
```

### ポリシーの意味
- `company`: `demo.rls_key`（セッション変数、UUID）に対応する `rls_key` が `rls_company_group` に存在し、そこに紐づく `company_id` の行のみが可視・操作可能。
- `organization`: 上記に該当する `company` に属する `organization`（`organization_chart` の `company_id` と `organization_id` の組）だけが可視・操作可能。
- `FORCE ROW LEVEL SECURITY` により、テーブル所有者を含め全ロールに RLS を強制します。
- `current_setting('demo.rls_key', true)` は未設定時に NULL を返し、`rk.key = NULL` は不成立となるため deny-by-default になります。

## 動作確認の例

```sql
-- 例: 任意の rls_key を 1 つ取得し、その key をセッションに設定
WITH picked AS (
  SELECT rk.key
  FROM demo.rls_key rk
  ORDER BY rk.created_at DESC
  LIMIT 1
)
SELECT set_config('demo.rls_key', (SELECT key::text FROM picked), true);

-- セレクト: 許可された company のみ見える
SELECT * FROM demo.company ORDER BY name;

-- セレクト: 許可された company 配下の organization のみ見える
SELECT o.*
FROM demo.organization o
ORDER BY o.name;

-- 解除
SELECT set_config('demo.rls_key', NULL, true);
```

## 補足
- 書き込み（INSERT/UPDATE/DELETE）も `WITH CHECK` により同じ制約がかかります。
- より厳密な運用をする場合、RLS キーの設定を行えるロールや、実際に `SELECT/INSERT/UPDATE/DELETE` を行えるロールを GRANT で制御してください。

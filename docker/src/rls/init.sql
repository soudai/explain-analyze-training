-- demo スキーマ用 初期データ投入スクリプト（各テーブル 10 件以上、users は company ごとに 2〜5 人）
-- 条件
--  - TEMP テーブルを使わない
--  - 外部キーは INSERT ... SELECT で id を解決
--  - 冪等実行（重複挿入を避ける）

SET search_path TO demo, public;

-- 1) company を最低 12 件用意
WITH s AS (
  SELECT to_char(gs, 'FM00') AS n FROM generate_series(1, 12) gs
)
INSERT INTO company(name)
SELECT 'Company ' || n
FROM s
WHERE NOT EXISTS (
  SELECT 1 FROM company c WHERE c.name = 'Company ' || n
);

-- 2) organization（各 company に HQ / Sales / Tech）
WITH roles AS (
  SELECT unnest(ARRAY['HQ','Sales','Tech']) AS role
)
INSERT INTO organization(name)
SELECT c.name || ' ' || r.role
FROM (
  SELECT * FROM company WHERE name LIKE 'Company %' ORDER BY name LIMIT 12
) c
CROSS JOIN roles r
WHERE NOT EXISTS (
  SELECT 1 FROM organization o WHERE o.name = c.name || ' ' || r.role
);

-- 3) organization_chart（HQ 自己参照、Sales/Tech は HQ 配下）
-- HQ 自己参照
INSERT INTO organization_chart(company_id, parent_organization_id, organization_id)
SELECT c.id AS company_id, ohq.id AS parent_id, ohq.id AS org_id
FROM (
  SELECT * FROM company WHERE name LIKE 'Company %' ORDER BY name LIMIT 12
) c
JOIN organization ohq ON ohq.name = c.name || ' ' || 'HQ'
WHERE NOT EXISTS (
  SELECT 1 FROM organization_chart oc
  WHERE oc.company_id = c.id AND oc.parent_organization_id = ohq.id AND oc.organization_id = ohq.id
);

-- Sales/Tech -> HQ 配下
INSERT INTO organization_chart(company_id, parent_organization_id, organization_id)
SELECT c.id AS company_id, ohq.id AS parent_id, och.id AS org_id
FROM (
  SELECT * FROM company WHERE name LIKE 'Company %' ORDER BY name LIMIT 12
) c
JOIN organization ohq ON ohq.name = c.name || ' ' || 'HQ'
JOIN organization och ON och.name IN (c.name || ' ' || 'Sales', c.name || ' ' || 'Tech')
WHERE NOT EXISTS (
  SELECT 1 FROM organization_chart oc
  WHERE oc.company_id = c.id AND oc.parent_organization_id = ohq.id AND oc.organization_id = och.id
);

-- 4) users：company ごとに 2〜5 人（合計 10 人以上を満たす）
WITH ordered_company AS (
  SELECT id, name, ROW_NUMBER() OVER (ORDER BY name) AS rn
  FROM company WHERE name LIKE 'Company %' ORDER BY name LIMIT 12
), per_company AS (
  SELECT id, name, 2 + ((rn - 1) % 4) AS cnt  -- 2..5 を循環
  FROM ordered_company
), to_insert AS (
  SELECT p.name || ' User ' || to_char(gs, 'FM00') AS user_name
  FROM per_company p
  JOIN LATERAL generate_series(1, p.cnt) gs ON true
)
INSERT INTO users(name)
SELECT t.user_name
FROM to_insert t
WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.name = t.user_name
);

-- 5) staff：各ユーザーを自社の HQ / Sales / Tech に均等に割当
-- 会社はユーザー名に含まれる company 名から逆引き
WITH u AS (
  SELECT id AS user_id, name AS user_name,
         split_part(name, ' User ', 1) AS company_name,
         CAST(split_part(name, ' User ', 2) AS int) AS user_no
  FROM users
  WHERE name LIKE 'Company % User %'
), target_org AS (
  SELECT
    u.user_id,
    CASE ((u.user_no - 1) % 3)
      WHEN 0 THEN u.company_name || ' HQ'
      WHEN 1 THEN u.company_name || ' Sales'
      ELSE        u.company_name || ' Tech'
    END AS org_name
  FROM u
)
INSERT INTO staff(user_id, organization_id)
SELECT u.user_id, o.id AS organization_id
FROM target_org u
JOIN organization o ON o.name = u.org_name
WHERE NOT EXISTS (
  SELECT 1 FROM staff s WHERE s.user_id = u.user_id AND s.organization_id = o.id
)
ON CONFLICT DO NOTHING;

-- 6) admin を最低 10 件: 会社ユーザーから先頭 10 名
WITH candidates AS (
  SELECT id FROM users WHERE name LIKE 'Company % User %' ORDER BY name LIMIT 10
)
INSERT INTO admin(user_id)
SELECT id FROM candidates
WHERE NOT EXISTS (SELECT 1 FROM admin a WHERE a.user_id = candidates.id);

-- 7) rls_key を最低 10 件
WITH needed AS (
  SELECT GREATEST(0, 10 - COUNT(*)) AS n FROM rls_key
), gs AS (
  SELECT generate_series(1, (SELECT n FROM needed)) AS i
)
INSERT INTO rls_key(key)
SELECT gen_random_uuid() FROM gs
ON CONFLICT DO NOTHING;

-- 8) rls_company_group を最低 10 行: 直近キーに会社を循環割当
WITH rk AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY created_at DESC) AS rn
  FROM rls_key
  ORDER BY created_at DESC
  LIMIT 10
), comp AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY name) AS rn, COUNT(*) OVER () AS total
  FROM company WHERE name LIKE 'Company %' ORDER BY name LIMIT 12
)
INSERT INTO rls_company_group(rls_key_id, company_id)
SELECT rk.id, c.id
FROM rk
JOIN comp c ON c.rn = ((rk.rn - 1) % c.total) + 1
WHERE NOT EXISTS (
  SELECT 1 FROM rls_company_group g WHERE g.rls_key_id = rk.id AND g.company_id = c.id
)
ON CONFLICT DO NOTHING;


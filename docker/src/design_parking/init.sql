-- init.sql
-- 目的: PostgreSQL のデフォルトDB（例: pgdemo）に、
--   - schema "soudai" に soudai_ddl.sql
--   - schema "ai"     に ai_ddl.sql
--   - schema "ai2"    に ai2_ddl.sql
-- をそれぞれ取り込みます。
-- 注意: このスクリプトは psql から実行されることを想定し、\i で同ディレクトリのファイルを参照します。

-- 事前に共通拡張が無ければ作成（拡張はDBスコープ / 既定でpublicに配置）
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ===== soudai スキーマ =====
CREATE SCHEMA IF NOT EXISTS soudai;
SET search_path TO soudai, public;
\echo 'Importing into schema: soudai -> soudai_ddl.sql'
\i 'soudai_ddl.sql'
RESET search_path;

-- ===== ai スキーマ =====
CREATE SCHEMA IF NOT EXISTS ai;
SET search_path TO ai, public;
\echo 'Importing into schema: ai -> ai_ddl.sql'
\i 'ai_ddl.sql'
RESET search_path;

-- ===== ai2 スキーマ =====
CREATE SCHEMA IF NOT EXISTS ai2;
SET search_path TO ai2, public;
\echo 'Importing into schema: ai2 -> ai2_ddl.sql'
\i 'ai2_ddl.sql'
RESET search_path;

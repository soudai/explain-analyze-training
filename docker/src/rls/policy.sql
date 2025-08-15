-- demo schema RLS policies based on rls_key
-- Safe to run multiple times

BEGIN;
SET search_path TO demo, public;

-- Optional helpful indexes
CREATE INDEX IF NOT EXISTS organization_chart_organization_id_idx ON demo.organization_chart(organization_id);
CREATE INDEX IF NOT EXISTS rls_company_group_company_id_idx ON demo.rls_company_group(company_id);
CREATE INDEX IF NOT EXISTS rls_company_group_rls_key_id_idx ON demo.rls_company_group(rls_key_id);

-- company RLS
ALTER TABLE demo.company ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.company FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_rls_by_key ON demo.company;
CREATE POLICY company_rls_by_key ON demo.company
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
  WHERE rk.key = NULLIF(current_setting('demo.rls_key', true), '')::uuid
        AND cg.company_id = company.id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
  WHERE rk.key = NULLIF(current_setting('demo.rls_key', true), '')::uuid
        AND cg.company_id = company.id
    )
  );

-- organization RLS
ALTER TABLE demo.organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.organization FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS organization_rls_by_key ON demo.organization;
CREATE POLICY organization_rls_by_key ON demo.organization
  FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
      JOIN demo.organization_chart oc ON oc.company_id = cg.company_id
  WHERE rk.key = NULLIF(current_setting('demo.rls_key', true), '')::uuid
        AND oc.organization_id = organization.id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM demo.rls_key rk
      JOIN demo.rls_company_group cg ON cg.rls_key_id = rk.id
      JOIN demo.organization_chart oc ON oc.company_id = cg.company_id
  WHERE rk.key = NULLIF(current_setting('demo.rls_key', true), '')::uuid
        AND oc.organization_id = organization.id
    )
  );

COMMIT;

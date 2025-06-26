-- 0. 拡張・共通ドメイン -----------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- 任意。bigserial でも可

-- 1. 顧客 ----------------------------------------------------------------
CREATE TABLE customers (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name          TEXT        NOT NULL,
    phone_number  TEXT        NOT NULL,
    address       TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. 車両 ----------------------------------------------------------------
CREATE TABLE vehicles (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id   UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    plate_number  TEXT NOT NULL UNIQUE,        -- 「名古屋 300 あ 12-34」などを自由書式で
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. 駐車区画（6 台固定）-------------------------------------------------
CREATE TABLE parking_spaces (
    id            SMALLINT  PRIMARY KEY,       -- 1〜6
    space_no      SMALLINT  NOT NULL UNIQUE,   -- 表示用（=id と同一でも可）
    monthly_fee   NUMERIC(10,2) NOT NULL CHECK (monthly_fee > 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 初期データ（すべて同額 15,000 円の例）
INSERT INTO parking_spaces (id, space_no, monthly_fee)
VALUES (1,1,15000),(2,2,15000),(3,3,15000),
       (4,4,15000),(5,5,15000),(6,6,15000);

-- 4. 契約 ----------------------------------------------------------------
CREATE TABLE contracts (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_space_id SMALLINT  NOT NULL REFERENCES parking_spaces(id) ON DELETE RESTRICT,
    customer_id      UUID      NOT NULL REFERENCES customers(id)      ON DELETE RESTRICT,
    vehicle_id       UUID      NOT NULL REFERENCES vehicles(id)       ON DELETE RESTRICT,
    start_date       DATE      NOT NULL
        CHECK (date_trunc('month', start_date) = start_date),          -- 必ず月初
    end_date         DATE
        CHECK (end_date IS NULL OR end_date >= start_date),
    monthly_fee      NUMERIC(10,2) NOT NULL CHECK (monthly_fee > 0),   -- 契約締結時にコピー
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 「同じ区画に同時に 2 件の “契約中” を作れない」ことを保証
CREATE UNIQUE INDEX contracts_active_space_uidx
    ON contracts (parking_space_id)
  WHERE end_date IS NULL;

-- 同様に車両・顧客も 1 契約限定（仕様変更に応じて削除可）
CREATE UNIQUE INDEX contracts_active_vehicle_uidx
    ON contracts (vehicle_id)
  WHERE end_date IS NULL;

CREATE UNIQUE INDEX contracts_active_customer_uidx
    ON contracts (customer_id)
  WHERE end_date IS NULL;

-- 5. 請求（バッチで月次生成）-------------------------------------------
CREATE TABLE billings (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id    UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    billing_month  DATE NOT NULL
        CHECK (date_trunc('month', billing_month) = billing_month),
    amount         NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    issued_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX billings_contract_month_uidx
    ON billings (contract_id, billing_month);

-- 6. 入金実績 ------------------------------------------------------------
CREATE TABLE payments (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    billing_id    UUID        NOT NULL REFERENCES billings(id) ON DELETE CASCADE,
    paid_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_amount   NUMERIC(10,2) NOT NULL CHECK (paid_amount > 0)
);

CREATE UNIQUE INDEX payments_billing_uidx ON payments (billing_id);

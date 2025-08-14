-- 0. 拡張・共通ドメイン -----------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- 任意。bigserial でも可

-- 1. 顧客 ----------------------------------------------------------------
CREATE TABLE customers (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name          TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Customersの個人情報を保存するテーブル
CREATE TABLE customer_personal_info (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id   UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
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
    vehicle_type  TEXT NOT NULL CHECK (vehicle_type IN ('car', 'motorcycle')),  -- 車種（車・バイク）
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 空き地名
CREATE TABLE parking_lots (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name          TEXT NOT NULL UNIQUE,         -- 空き地の名前
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 空き地と駐車区画の紐付け
CREATE TABLE parking_lot_spaces (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_lot_id UUID NOT NULL REFERENCES parking_lots(id) ON DELETE CASCADE,
    parking_space_id SMALLINT NOT NULL REFERENCES parking_spaces(id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (parking_space_id)  -- 同じ空き地に同じ駐車区画を登録できない
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

-- 4. 契約（月極駐車場のみ） -----------------------------------------------
CREATE TABLE contracts (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_space_id SMALLINT  NOT NULL REFERENCES parking_spaces(id) ON DELETE RESTRICT,
    customer_id      UUID      NOT NULL REFERENCES customers(id)      ON DELETE RESTRICT,
    vehicle_id       UUID      NOT NULL REFERENCES vehicles(id)       ON DELETE RESTRICT,
    contract_type    TEXT      NOT NULL CHECK (contract_type = 'monthly'), -- 月極契約のみ
    begin_at         TIMESTAMPTZ      NOT NULL,
    end_at           TIMESTAMPTZ,     -- NULLなら継続中
    monthly_fee      NUMERIC(10,2) NOT NULL CHECK (monthly_fee > 0),   -- 契約締結時にコピー
    vehicle_count    SMALLINT NOT NULL DEFAULT 1 CHECK (vehicle_count > 0),  -- バイクの場合は最大3台
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- バイクは最大3台、車は1台の制約
    CONSTRAINT contract_vehicle_count_limit CHECK (
        (vehicle_count = 1) OR 
        (vehicle_count <= 3 AND EXISTS (
            SELECT 1 FROM vehicles v WHERE v.id = vehicle_id AND v.vehicle_type = 'motorcycle'
        ))
    )
);

-- 同一駐車スペースで有効な契約（end_at が NULL）は1つのみ
CREATE UNIQUE INDEX contracts_active_space_uidx
    ON contracts (parking_space_id)
  WHERE end_at IS NULL;

-- 同様に車両・顧客も 1 契約限定（仕様変更に応じて削除可） 
CREATE UNIQUE INDEX contracts_active_vehicle_uidx
    ON contracts (vehicle_id)
  WHERE end_at IS NULL;

CREATE UNIQUE INDEX contracts_active_customer_uidx
    ON contracts (customer_id)
  WHERE end_at IS NULL;

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
    paid_amount   NUMERIC(10,2) NOT NULL CHECK (paid_amount > 0),
    cancel_at     TIMESTAMPTZ  -- キャンセル時の日時（nullならキャンセルなし）
);

CREATE UNIQUE INDEX payments_billing_uidx ON payments (billing_id);

-- 7. 時間貸しパーキング利用記録 ------------------------------------------
CREATE TABLE hourly_parking_sessions (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_space_id SMALLINT NOT NULL REFERENCES parking_spaces(id) ON DELETE RESTRICT,
    vehicle_id       UUID NOT NULL REFERENCES vehicles(id) ON DELETE RESTRICT,
    customer_id      UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    entry_at         TIMESTAMPTZ NOT NULL,
    exit_at          TIMESTAMPTZ,
    vehicle_count    SMALLINT NOT NULL DEFAULT 1 CHECK (vehicle_count > 0),  -- バイクの場合は最大3台
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- バイクは最大3台、車は1台の制約
    CONSTRAINT vehicle_count_limit CHECK (
        (vehicle_count = 1) OR 
        (vehicle_count <= 3 AND EXISTS (
            SELECT 1 FROM vehicles v WHERE v.id = vehicle_id AND v.vehicle_type = 'motorcycle'
        ))
    )
);

-- 時間貸しパーキングの利用中セッション（exit_at が NULL のもの）に対する制約
-- 同一スペースで重複した利用を防ぐ
CREATE UNIQUE INDEX hourly_parking_active_space_uidx
    ON hourly_parking_sessions (parking_space_id)
  WHERE exit_at IS NULL;

-- 8. 時間貸し料金設定 ----------------------------------------------------
CREATE TABLE hourly_rates (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    time_period   TEXT NOT NULL CHECK (time_period IN ('day', 'night')),  -- day: 08:00-19:59, night: 20:00-07:59
    rate_per_10min NUMERIC(10,2) NOT NULL DEFAULT 100.00,  -- 10分あたりの料金
    max_daily_fee NUMERIC(10,2) NOT NULL,  -- 最大料金 (day: 5000, night: 2000)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 初期料金設定
INSERT INTO hourly_rates (time_period, rate_per_10min, max_daily_fee)
VALUES 
    ('day', 100.00, 5000.00),    -- 8:00-19:59
    ('night', 100.00, 2000.00);  -- 20:00-7:59

-- 9. 時間貸し請求 --------------------------------------------------------
CREATE TABLE hourly_billings (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id  UUID NOT NULL REFERENCES hourly_parking_sessions(id) ON DELETE CASCADE,
    amount      NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    billing_periods JSONB NOT NULL,  -- 料金計算の詳細（時間帯別の内訳）
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at     TIMESTAMPTZ,
    
    UNIQUE (session_id)
);

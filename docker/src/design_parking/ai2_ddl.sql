-- イミュータブルデータモデル駐車場管理システム - ステップ2対応
-- 設計原則: イベントソーシング、単一責任、履歴完全保持

-- 0. 拡張・共通ドメイン -----------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. 顧客関連イベント =============================================

-- 顧客登録イベント（イミュータブル）
CREATE TABLE customer_registered_events (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL,
    name        TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 顧客個人情報登録イベント  
CREATE TABLE customer_personal_info_registered_events (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id  UUID NOT NULL,
    phone_number TEXT NOT NULL,
    address      TEXT,
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 顧客個人情報変更イベント
CREATE TABLE customer_personal_info_updated_events (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id  UUID NOT NULL,
    phone_number TEXT,
    address      TEXT,
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 2. 車両関連イベント =============================================

-- 車両登録イベント
CREATE TABLE vehicle_registered_events (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id   UUID NOT NULL,
    customer_id  UUID NOT NULL,
    plate_number TEXT NOT NULL,
    vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('car', 'motorcycle')),
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 車両情報変更イベント
CREATE TABLE vehicle_updated_events (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id   UUID NOT NULL,
    plate_number TEXT,
    vehicle_type TEXT CHECK (vehicle_type IN ('car', 'motorcycle')),
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 3. 駐車場・区画関連イベント =====================================

-- 駐車場登録イベント
CREATE TABLE parking_lot_registered_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_lot_id  UUID NOT NULL,
    name            TEXT NOT NULL,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version   INTEGER NOT NULL DEFAULT 1
);

-- 駐車区画設定イベント
CREATE TABLE parking_space_configured_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_space_id SMALLINT NOT NULL,
    parking_lot_id  UUID NOT NULL,
    space_no        SMALLINT NOT NULL,
    monthly_fee     NUMERIC(10,2) NOT NULL CHECK (monthly_fee > 0),
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version   INTEGER NOT NULL DEFAULT 1
);

-- 駐車区画料金変更イベント
CREATE TABLE parking_space_fee_updated_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parking_space_id SMALLINT NOT NULL,
    old_monthly_fee NUMERIC(10,2) NOT NULL,
    new_monthly_fee NUMERIC(10,2) NOT NULL CHECK (new_monthly_fee > 0),
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version   INTEGER NOT NULL DEFAULT 1
);

-- 4. 月極契約関連イベント ========================================

-- 月極契約開始イベント
CREATE TABLE monthly_contract_started_events (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id      UUID NOT NULL,
    parking_space_id SMALLINT NOT NULL,
    customer_id      UUID NOT NULL,
    vehicle_id       UUID NOT NULL,
    vehicle_count    SMALLINT NOT NULL DEFAULT 1 CHECK (vehicle_count > 0),
    monthly_fee      NUMERIC(10,2) NOT NULL CHECK (monthly_fee > 0),
    begin_at         TIMESTAMPTZ NOT NULL,
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version    INTEGER NOT NULL DEFAULT 1
);

-- 月極契約終了イベント
CREATE TABLE monthly_contract_ended_events (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_id      UUID NOT NULL,
    end_at           TIMESTAMPTZ NOT NULL,
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version    INTEGER NOT NULL DEFAULT 1
);

-- 5. 時間貸し利用関連イベント ====================================

-- 時間貸し入庫イベント
CREATE TABLE hourly_parking_entry_events (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id       UUID NOT NULL,
    parking_space_id SMALLINT NOT NULL,
    vehicle_id       UUID NOT NULL,
    customer_id      UUID NOT NULL,
    vehicle_count    SMALLINT NOT NULL DEFAULT 1 CHECK (vehicle_count > 0),
    entry_at         TIMESTAMPTZ NOT NULL,
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version    INTEGER NOT NULL DEFAULT 1
);

-- 時間貸し出庫イベント
CREATE TABLE hourly_parking_exit_events (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id       UUID NOT NULL,
    exit_at          TIMESTAMPTZ NOT NULL,
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version    INTEGER NOT NULL DEFAULT 1
);

-- 6. 料金関連イベント ==========================================

-- 時間貸し料金設定イベント
CREATE TABLE hourly_rate_configured_events (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rate_id        UUID NOT NULL,
    time_period    TEXT NOT NULL CHECK (time_period IN ('day', 'night')),
    rate_per_10min NUMERIC(10,2) NOT NULL DEFAULT 100.00,
    max_daily_fee  NUMERIC(10,2) NOT NULL,
    occurred_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version  INTEGER NOT NULL DEFAULT 1
);

-- 初期料金設定
INSERT INTO hourly_rate_configured_events (rate_id, time_period, rate_per_10min, max_daily_fee)
VALUES 
    (uuid_generate_v4(), 'day', 100.00, 5000.00),
    (uuid_generate_v4(), 'night', 100.00, 2000.00);

-- 7. 請求関連イベント ==========================================

-- 月極請求発行イベント
CREATE TABLE monthly_billing_issued_events (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    billing_id     UUID NOT NULL,
    contract_id    UUID NOT NULL,
    billing_month  DATE NOT NULL CHECK (date_trunc('month', billing_month) = billing_month),
    amount         NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    occurred_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version  INTEGER NOT NULL DEFAULT 1
);

-- 時間貸し請求発行イベント
CREATE TABLE hourly_billing_issued_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    billing_id      UUID NOT NULL,
    session_id      UUID NOT NULL,
    amount          NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    billing_periods JSONB NOT NULL,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version   INTEGER NOT NULL DEFAULT 1
);

-- 8. 入金関連イベント ==========================================

-- 入金受領イベント
CREATE TABLE payment_received_events (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id    UUID NOT NULL,
    billing_id    UUID NOT NULL,
    billing_type  TEXT NOT NULL CHECK (billing_type IN ('monthly', 'hourly')),
    paid_amount   NUMERIC(10,2) NOT NULL CHECK (paid_amount > 0),
    paid_at       TIMESTAMPTZ NOT NULL,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 入金キャンセルイベント
CREATE TABLE payment_cancelled_events (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id    UUID NOT NULL,
    cancelled_at  TIMESTAMPTZ NOT NULL,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_version INTEGER NOT NULL DEFAULT 1
);

-- 9. 集約ビュー（現在状態の計算結果） ========================

-- 現在の顧客一覧（最新情報）
CREATE VIEW current_customers AS
SELECT DISTINCT
    cr.customer_id,
    cr.name,
    cp.phone_number,
    cp.address,
    cr.occurred_at as registered_at
FROM customer_registered_events cr
LEFT JOIN LATERAL (
    SELECT phone_number, address, occurred_at
    FROM customer_personal_info_registered_events cpir
    WHERE cpir.customer_id = cr.customer_id
    UNION ALL
    SELECT phone_number, address, occurred_at  
    FROM customer_personal_info_updated_events cpiu
    WHERE cpiu.customer_id = cr.customer_id
    ORDER BY occurred_at DESC
    LIMIT 1
) cp ON true;

-- 現在の車両一覧
CREATE VIEW current_vehicles AS
SELECT DISTINCT
    vr.vehicle_id,
    vr.customer_id,
    COALESCE(vu.plate_number, vr.plate_number) as plate_number,
    COALESCE(vu.vehicle_type, vr.vehicle_type) as vehicle_type,
    vr.occurred_at as registered_at
FROM vehicle_registered_events vr
LEFT JOIN LATERAL (
    SELECT plate_number, vehicle_type, occurred_at
    FROM vehicle_updated_events vu
    WHERE vu.vehicle_id = vr.vehicle_id
    ORDER BY occurred_at DESC
    LIMIT 1
) vu ON true;

-- 現在の駐車区画状況
CREATE VIEW current_parking_spaces AS
SELECT 
    ps.parking_space_id,
    ps.parking_lot_id,
    ps.space_no,
    COALESCE(pf.new_monthly_fee, ps.monthly_fee) as current_monthly_fee
FROM parking_space_configured_events ps
LEFT JOIN LATERAL (
    SELECT new_monthly_fee, occurred_at
    FROM parking_space_fee_updated_events pf
    WHERE pf.parking_space_id = ps.parking_space_id
    ORDER BY occurred_at DESC
    LIMIT 1
) pf ON true;

-- 現在の月極契約状況
CREATE VIEW current_monthly_contracts AS
SELECT 
    cs.contract_id,
    cs.parking_space_id,
    cs.customer_id,
    cs.vehicle_id,
    cs.vehicle_count,
    cs.monthly_fee,
    cs.begin_at,
    ce.end_at
FROM monthly_contract_started_events cs
LEFT JOIN monthly_contract_ended_events ce ON cs.contract_id = ce.contract_id
WHERE ce.contract_id IS NULL; -- 終了していない契約のみ

-- 現在の時間貸しセッション
CREATE VIEW current_hourly_sessions AS
SELECT 
    en.session_id,
    en.parking_space_id,
    en.vehicle_id,
    en.customer_id,
    en.vehicle_count,
    en.entry_at,
    ex.exit_at
FROM hourly_parking_entry_events en
LEFT JOIN hourly_parking_exit_events ex ON en.session_id = ex.session_id
WHERE ex.session_id IS NULL; -- 出庫していないセッションのみ

-- 初期データ投入（駐車区画設定）
INSERT INTO parking_lot_registered_events (parking_lot_id, name)
VALUES (uuid_generate_v4(), 'メイン駐車場');

INSERT INTO parking_space_configured_events (parking_space_id, parking_lot_id, space_no, monthly_fee)
SELECT 
    s.space_no,
    (SELECT parking_lot_id FROM parking_lot_registered_events LIMIT 1),
    s.space_no,
    15000.00
FROM generate_series(1, 6) AS s(space_no);
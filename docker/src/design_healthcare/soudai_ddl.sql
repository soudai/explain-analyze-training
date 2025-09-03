-- DDL for Healthcare App (weights + expert chat)
-- Design: UUID PKs, No RLS, only necessary timestamps, timezone-aware weights
-- Schema: soudai

CREATE SCHEMA IF NOT EXISTS soudai;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid()

-- Users (supertype)
CREATE TABLE IF NOT EXISTS soudai.users (
	user_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	display_name text NOT NULL,
	timezone     text NOT NULL DEFAULT 'UTC', -- IANA timezone, e.g., 'Asia/Tokyo'
	active       boolean NOT NULL DEFAULT true
);

-- Subtypes
CREATE TABLE IF NOT EXISTS soudai.end_users (
	user_id uuid PRIMARY KEY REFERENCES soudai.users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS soudai.experts (
	user_id   uuid PRIMARY KEY REFERENCES soudai.users(user_id) ON DELETE CASCADE,
	expertise text
);

-- Weight measurements (store all in UTC, no deletion)
CREATE TABLE IF NOT EXISTS soudai.weights (
	weight_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id     uuid NOT NULL REFERENCES soudai.users(user_id) ON DELETE CASCADE,
	measured_at timestamptz NOT NULL,
	weight_kg   numeric(6,2) NOT NULL CHECK (weight_kg > 0 AND weight_kg < 500),
	source      text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','device')),
	device_id   text,
	note        text
);
CREATE INDEX IF NOT EXISTS ix_weights_user_time ON soudai.weights(user_id, measured_at DESC);

-- Chat rooms
CREATE TABLE IF NOT EXISTS soudai.chat_rooms (
	room_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	created_by uuid NOT NULL REFERENCES soudai.users(user_id) ON DELETE RESTRICT,
	created_at timestamptz NOT NULL DEFAULT now()
);

-- Room participants (1 end_user + many experts)
CREATE TABLE IF NOT EXISTS soudai.chat_room_participants (
	participant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	room_id        uuid NOT NULL REFERENCES soudai.chat_rooms(room_id) ON DELETE CASCADE,
	user_id        uuid NOT NULL REFERENCES soudai.users(user_id) ON DELETE CASCADE,
	role           text NOT NULL CHECK (role IN ('end_user','expert')),
	joined_at      timestamptz NOT NULL DEFAULT now(),
	left_at        timestamptz
);
-- Avoid duplicate membership of same user in a room
CREATE UNIQUE INDEX IF NOT EXISTS ux_participants_room_user
	ON soudai.chat_room_participants(room_id, user_id);
-- Only one end_user per room
CREATE UNIQUE INDEX IF NOT EXISTS ux_participants_one_end_user_per_room
	ON soudai.chat_room_participants(room_id)
	WHERE role = 'end_user';

-- Messages parent (no sender column; sender is in subtype tables)
CREATE TABLE IF NOT EXISTS soudai.chat_messages (
	message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	room_id    uuid NOT NULL REFERENCES soudai.chat_rooms(room_id) ON DELETE CASCADE,
	content    text,
	image_url  text,
	sent_at    timestamptz NOT NULL DEFAULT now(),
	CHECK (content IS NOT NULL OR image_url IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ix_messages_room_time ON soudai.chat_messages(room_id, sent_at DESC);

-- Message subtypes
CREATE TABLE IF NOT EXISTS soudai.chat_messages_end_user (
	message_id         uuid PRIMARY KEY REFERENCES soudai.chat_messages(message_id) ON DELETE CASCADE,
	sender_end_user_id uuid NOT NULL REFERENCES soudai.end_users(user_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS soudai.chat_messages_expert (
	message_id        uuid PRIMARY KEY REFERENCES soudai.chat_messages(message_id) ON DELETE CASCADE,
	sender_expert_id  uuid NOT NULL REFERENCES soudai.experts(user_id) ON DELETE RESTRICT
);

-- Read receipts (audit)
CREATE TABLE IF NOT EXISTS soudai.chat_message_read_receipts (
	receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	message_id uuid NOT NULL REFERENCES soudai.chat_messages(message_id) ON DELETE CASCADE,
	user_id    uuid NOT NULL REFERENCES soudai.users(user_id) ON DELETE CASCADE,
	read_at    timestamptz NOT NULL DEFAULT now(),
	UNIQUE (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS ix_read_receipts_user_time ON soudai.chat_message_read_receipts(user_id, read_at DESC);

-- Deletions (audit)
CREATE TABLE IF NOT EXISTS soudai.chat_message_deletions (
	deletion_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	message_id  uuid NOT NULL REFERENCES soudai.chat_messages(message_id) ON DELETE CASCADE,
	deleted_by  uuid NOT NULL REFERENCES soudai.users(user_id) ON DELETE RESTRICT,
	deleted_at  timestamptz NOT NULL DEFAULT now(),
	reason      text
);
CREATE INDEX IF NOT EXISTS ix_message_deletions_msg ON soudai.chat_message_deletions(message_id);

-- View: union of messages
CREATE OR REPLACE VIEW soudai.v_chat_messages_union AS
SELECT
	m.message_id,
	m.room_id,
	m.sent_at,
	m.content,
	m.image_url,
	'end_user'::text AS sender_type,
	ceu.sender_end_user_id AS sender_id
FROM soudai.chat_messages m
JOIN soudai.chat_messages_end_user ceu ON ceu.message_id = m.message_id
UNION ALL
SELECT
	m.message_id,
	m.room_id,
	m.sent_at,
	m.content,
	m.image_url,
	'expert'::text AS sender_type,
	cex.sender_expert_id AS sender_id
FROM soudai.chat_messages m
JOIN soudai.chat_messages_expert cex ON cex.message_id = m.message_id;

-- View: daily latest weight per user in the user's local date
CREATE OR REPLACE VIEW soudai.v_weight_daily_latest AS
WITH enriched AS (
	SELECT
		w.user_id,
		w.measured_at,
		w.weight_kg,
		w.source,
		(w.measured_at AT TIME ZONE u.timezone)::date AS local_date
	FROM soudai.weights w
	JOIN soudai.users u ON u.user_id = w.user_id
)
SELECT DISTINCT ON (user_id, local_date)
	user_id,
	local_date,
	measured_at,
	weight_kg,
	source
FROM enriched
ORDER BY user_id, local_date, measured_at DESC;

-- View: 7-day trailing SMA over daily latest (exclude missing days)
CREATE OR REPLACE VIEW soudai.v_weight_daily_sma7 AS
SELECT
	d.user_id,
	d.local_date,
	d.weight_kg,
	(
		SELECT AVG(d2.weight_kg)
		FROM soudai.v_weight_daily_latest d2
		WHERE d2.user_id = d.user_id
		  AND d2.local_date BETWEEN d.local_date - 6 AND d.local_date
	) AS sma7_kg
FROM soudai.v_weight_daily_latest d;

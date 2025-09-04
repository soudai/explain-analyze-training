-- Healthcare app DDL (weights + expert chat)
-- PK: uuid, No RLS, date/time only where needed
-- Schema: demo3

CREATE SCHEMA IF NOT EXISTS demo3;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid()

-- Users (end users and experts)
CREATE TABLE IF NOT EXISTS demo3.users (
	user_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	display_name text NOT NULL,
	role         text NOT NULL CHECK (role IN ('end_user','expert')),
	timezone     text NOT NULL DEFAULT 'UTC',
	active       boolean NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS ix_users_role ON demo3.users(role);

-- Weight measurements (store all, in UTC)
CREATE TABLE IF NOT EXISTS demo3.weights (
	weight_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id     uuid NOT NULL REFERENCES demo3.users(user_id) ON DELETE CASCADE,
	measured_at timestamptz NOT NULL,
	weight_kg   numeric(6,2) NOT NULL CHECK (weight_kg > 0 AND weight_kg < 500),
	source      text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','device')),
	device_id   text,
	note        text
);
CREATE INDEX IF NOT EXISTS ix_weights_user_time ON demo3.weights(user_id, measured_at DESC);

-- Chat rooms
CREATE TABLE IF NOT EXISTS demo3.chat_rooms (
	room_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	created_by uuid NOT NULL REFERENCES demo3.users(user_id) ON DELETE RESTRICT,
	created_at timestamptz NOT NULL DEFAULT now()
);

-- Room participants (1 end_user + many experts)
CREATE TABLE IF NOT EXISTS demo3.chat_room_participants (
	participant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	room_id        uuid NOT NULL REFERENCES demo3.chat_rooms(room_id) ON DELETE CASCADE,
	user_id        uuid NOT NULL REFERENCES demo3.users(user_id) ON DELETE CASCADE,
	role           text NOT NULL CHECK (role IN ('end_user','expert')),
	joined_at      timestamptz NOT NULL DEFAULT now(),
	left_at        timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_participants_room_user
	ON demo3.chat_room_participants(room_id, user_id);
-- Only one end_user per room
CREATE UNIQUE INDEX IF NOT EXISTS ux_participants_one_end_user_per_room
	ON demo3.chat_room_participants(room_id)
	WHERE role = 'end_user';

-- Messages (text and/or image)
CREATE TABLE IF NOT EXISTS demo3.chat_messages (
	message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	room_id    uuid NOT NULL REFERENCES demo3.chat_rooms(room_id) ON DELETE CASCADE,
	sender_id  uuid NOT NULL REFERENCES demo3.users(user_id) ON DELETE RESTRICT,
	content    text,
	image_url  text,
	sent_at    timestamptz NOT NULL DEFAULT now(),
	CHECK (content IS NOT NULL OR image_url IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ix_messages_room_time ON demo3.chat_messages(room_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS ix_messages_sender_time ON demo3.chat_messages(sender_id, sent_at DESC);

-- Read receipts (audit)
CREATE TABLE IF NOT EXISTS demo3.chat_message_read_receipts (
	receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	message_id uuid NOT NULL REFERENCES demo3.chat_messages(message_id) ON DELETE CASCADE,
	user_id    uuid NOT NULL REFERENCES demo3.users(user_id) ON DELETE CASCADE,
	read_at    timestamptz NOT NULL DEFAULT now(),
	UNIQUE (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS ix_read_receipts_user_time ON demo3.chat_message_read_receipts(user_id, read_at DESC);

-- Deletions (audit)
CREATE TABLE IF NOT EXISTS demo3.chat_message_deletions (
	deletion_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	message_id  uuid NOT NULL REFERENCES demo3.chat_messages(message_id) ON DELETE CASCADE,
	deleted_by  uuid NOT NULL REFERENCES demo3.users(user_id) ON DELETE RESTRICT,
	deleted_at  timestamptz NOT NULL DEFAULT now(),
	reason      text
);
CREATE INDEX IF NOT EXISTS ix_message_deletions_msg ON demo3.chat_message_deletions(message_id);

-- View: daily latest weight per user in user's local date
CREATE OR REPLACE VIEW demo3.v_weight_daily_latest AS
WITH enriched AS (
	SELECT
		w.user_id,
		w.measured_at,
		w.weight_kg,
		w.source,
		(w.measured_at AT TIME ZONE u.timezone)::date AS local_date
	FROM demo3.weights w
	JOIN demo3.users u ON u.user_id = w.user_id
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
CREATE OR REPLACE VIEW demo3.v_weight_daily_sma7 AS
SELECT
	d.user_id,
	d.local_date,
	d.weight_kg,
	(
		SELECT AVG(d2.weight_kg)
		FROM demo3.v_weight_daily_latest d2
		WHERE d2.user_id = d.user_id
			AND d2.local_date BETWEEN d.local_date - 6 AND d.local_date
	) AS sma7_kg
FROM demo3.v_weight_daily_latest d;

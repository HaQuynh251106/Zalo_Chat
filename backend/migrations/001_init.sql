-- Zalo-clone initial schema
-- Run with: psql "$DATABASE_URL" -f migrations/001_init.sql

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========================================================
-- USERS & DEVICES
-- =========================================================
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           TEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    display_name    TEXT NOT NULL DEFAULT '',
    avatar_url      TEXT,
    bio             TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS devices (
    id              TEXT PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name     TEXT,
    platform        TEXT, -- ios|android|web|desktop
    push_token      TEXT,
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);

-- =========================================================
-- FRIENDSHIPS  (canonical pair: user_low < user_high)
-- =========================================================
CREATE TABLE IF NOT EXISTS friendships (
    user_low        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_high       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requested_by    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          TEXT NOT NULL CHECK (status IN ('pending','accepted','blocked')),
    accepted_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_low, user_high),
    CHECK (user_low <> user_high)
);
CREATE INDEX IF NOT EXISTS idx_friendships_high ON friendships(user_high);

-- =========================================================
-- CONVERSATIONS & MEMBERS
-- =========================================================
CREATE TABLE IF NOT EXISTS conversations (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type                  TEXT NOT NULL CHECK (type IN ('direct','group')),
    title                 TEXT,
    avatar_url            TEXT,
    created_by            UUID REFERENCES users(id) ON DELETE SET NULL,
    last_message_at       TIMESTAMPTZ,
    last_message_preview  TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_conversations_last ON conversations(last_message_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS conversation_members (
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role             TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner','admin','member')),
    joined_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_read_at     TIMESTAMPTZ,
    muted_until      TIMESTAMPTZ,
    PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_members_user ON conversation_members(user_id);

-- =========================================================
-- MESSAGES
-- =========================================================
CREATE TABLE IF NOT EXISTS messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type             TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text','image','audio','video','file','system')),
    body             TEXT,
    media_url        TEXT,
    reply_to_id      UUID REFERENCES messages(id) ON DELETE SET NULL,
    recalled         BOOLEAN NOT NULL DEFAULT FALSE,
    recalled_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_messages_conv_time ON messages(conversation_id, created_at DESC);

-- =========================================================
-- READ RECEIPTS (per-user, per-message)
-- =========================================================
CREATE TABLE IF NOT EXISTS message_reads (
    message_id  UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);

-- =========================================================
-- PERSONAL FEED (Zalo-style "Nhật ký")
-- =========================================================
CREATE TABLE IF NOT EXISTS feed_posts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body        TEXT,
    media       JSONB NOT NULL DEFAULT '[]'::jsonb,
    visibility  TEXT NOT NULL DEFAULT 'friends' CHECK (visibility IN ('public','friends','private')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_feed_user_time ON feed_posts(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS feed_reactions (
    post_id    UUID NOT NULL REFERENCES feed_posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction   TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS feed_comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID NOT NULL REFERENCES feed_posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_feed_comments_post ON feed_comments(post_id, created_at);

-- =========================================================
-- CALL HISTORY (voice / video) — placeholder for future VoIP service
-- =========================================================
CREATE TABLE IF NOT EXISTS calls (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    initiator_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind             TEXT NOT NULL CHECK (kind IN ('voice','video')),
    started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at         TIMESTAMPTZ,
    status           TEXT NOT NULL DEFAULT 'ringing'
                       CHECK (status IN ('ringing','accepted','rejected','missed','ended'))
);
CREATE INDEX IF NOT EXISTS idx_calls_conv ON calls(conversation_id, started_at DESC);

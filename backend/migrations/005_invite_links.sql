-- Sprint Group Admin: shareable invite links for groups.

CREATE TABLE IF NOT EXISTS invite_links (
    token            TEXT PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_by       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at       TIMESTAMPTZ,
    max_uses         INT,
    use_count        INT NOT NULL DEFAULT 0,
    revoked          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invite_links_conv
ON invite_links(conversation_id) WHERE revoked = FALSE;

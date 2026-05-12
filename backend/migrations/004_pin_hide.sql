-- Sprint A: pinned messages + per-user hide (delete-for-me)

-- Pin: one column on messages. NULL = not pinned. NOT NULL = pinned at that time.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_messages_conv_pinned
ON messages(conversation_id, pinned_at DESC) WHERE pinned_at IS NOT NULL;

-- Per-user message hide (delete-for-me): hides message from a single user
-- without affecting others. Different from `recalled` which is global.
CREATE TABLE IF NOT EXISTS message_hides (
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    hidden_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_message_hides_user ON message_hides(user_id);

-- Sprint Hide Conversation: per-user hide of conversations behind a PIN gate.

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_cm_hidden
  ON conversation_members(user_id) WHERE hidden_at IS NOT NULL;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS hide_pin_hash TEXT;

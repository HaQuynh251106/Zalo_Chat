-- Sprint Wallet: in-app VND wallet with top-up and p2p transfer.
-- Amounts are stored as BIGINT "cents" (= VND × 100).

CREATE TABLE IF NOT EXISTS wallets (
    user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    balance_cents  BIGINT NOT NULL DEFAULT 0 CHECK (balance_cents >= 0),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$ BEGIN
    CREATE TYPE wallet_txn_type AS ENUM ('topup','transfer_out','transfer_in');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    counterparty_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    type               wallet_txn_type NOT NULL,
    amount_cents       BIGINT NOT NULL CHECK (amount_cents > 0),
    balance_after      BIGINT NOT NULL,
    memo               TEXT,
    related_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS wallet_txn_user_created_idx
    ON wallet_transactions(user_id, created_at DESC);

-- Money-message metadata on messages. We also relax the CHECK constraint
-- on messages.type to include 'money'.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS money_amount_cents BIGINT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS money_txn_id UUID;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'messages_type_check'
    ) THEN
        ALTER TABLE messages DROP CONSTRAINT messages_type_check;
    END IF;
END $$;

ALTER TABLE messages
    ADD CONSTRAINT messages_type_check
    CHECK (type IN ('text','image','audio','video','file','system','money'));

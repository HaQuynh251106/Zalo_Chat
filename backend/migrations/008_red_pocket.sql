-- Sprint Red Pocket: receiver explicitly "opens" the money message to claim
-- the reveal animation. Money has already moved into the receiver's wallet
-- when transferred; opened_at only gates the celebratory UI.

ALTER TABLE wallet_transactions
    ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS wallet_txn_related_message_idx
    ON wallet_transactions(related_message_id);

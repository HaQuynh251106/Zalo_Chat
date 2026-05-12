// Package wallet implements an in-app VND wallet: top-up (mock), peer-to-peer
// transfer (transactional, friendship-gated, block-aware) and history.
//
// Amounts are stored as BIGINT "cents" where 1 cent = 1 VND × 0.01.
// In practice the smallest unit users transact in is 1.000 ₫ = 100_000 cents.
package wallet

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/a1234/zalo-clone/backend/internal/message"
)

// Limits expressed in cents (VND × 100).
const (
	MinTopupCents    int64 = 10_000 * 100     // 10.000 ₫
	MaxTopupCents    int64 = 50_000_000 * 100 // 50.000.000 ₫
	MinTransferCents int64 = 1_000 * 100      // 1.000 ₫
	MaxTransferCents int64 = 20_000_000 * 100 // 20.000.000 ₫
)

var (
	ErrInvalidAmount     = errors.New("invalid amount")
	ErrAmountTooSmall    = errors.New("amount below minimum")
	ErrAmountTooLarge    = errors.New("amount above maximum")
	ErrInsufficientFunds = errors.New("insufficient_funds")
	ErrSelfTransfer      = errors.New("cannot transfer to self")
	ErrNotFriends        = errors.New("not_friends")
	ErrBlocked           = errors.New("blocked")
)

type Wallet struct {
	UserID       uuid.UUID `json:"user_id"`
	BalanceCents int64     `json:"balance_cents"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type Counterparty struct {
	ID          uuid.UUID `json:"id"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
}

type Transaction struct {
	ID             uuid.UUID     `json:"id"`
	Type           string        `json:"type"` // topup | transfer_in | transfer_out
	AmountCents    int64         `json:"amount_cents"`
	BalanceAfter   int64         `json:"balance_after"`
	Memo           string        `json:"memo,omitempty"`
	Counterparty   *Counterparty `json:"counterparty,omitempty"`
	RelatedMessage *uuid.UUID    `json:"related_message_id,omitempty"`
	CreatedAt      time.Time     `json:"created_at"`
}

type TransferResult struct {
	TxnID           uuid.UUID       `json:"txn_id"`
	MessageID       uuid.UUID       `json:"message_id"`
	ConversationID  uuid.UUID       `json:"conversation_id"`
	NewBalanceCents int64           `json:"new_balance_cents"`
	ReceiverID      uuid.UUID       `json:"receiver_id"`
	ReceiverBalance int64           `json:"-"`
	Message         message.Message `json:"-"`
	Counterparty    Counterparty    `json:"-"`
	Sender          Counterparty    `json:"-"`
}

type Service struct {
	pool *pgxpool.Pool
	msgs *message.Service
}

func NewService(pool *pgxpool.Pool, msgs *message.Service) *Service {
	return &Service{pool: pool, msgs: msgs}
}

// Me returns (or lazily creates) the caller's wallet row.
func (s *Service) Me(ctx context.Context, userID uuid.UUID) (Wallet, error) {
	if _, err := s.pool.Exec(ctx, `
		INSERT INTO wallets (user_id) VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID); err != nil {
		return Wallet{}, err
	}
	var w Wallet
	err := s.pool.QueryRow(ctx, `
		SELECT user_id, balance_cents, updated_at FROM wallets WHERE user_id=$1
	`, userID).Scan(&w.UserID, &w.BalanceCents, &w.UpdatedAt)
	return w, err
}

// Topup adds the given amount to the caller's wallet using a mock source.
// Returns the updated wallet.
func (s *Service) Topup(ctx context.Context, userID uuid.UUID, amountCents int64) (Wallet, error) {
	if amountCents <= 0 {
		return Wallet{}, ErrInvalidAmount
	}
	if amountCents < MinTopupCents {
		return Wallet{}, ErrAmountTooSmall
	}
	if amountCents > MaxTopupCents {
		return Wallet{}, ErrAmountTooLarge
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Wallet{}, err
	}
	defer tx.Rollback(ctx)

	// Ensure wallet row exists & lock it.
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallets (user_id) VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID); err != nil {
		return Wallet{}, err
	}
	var w Wallet
	err = tx.QueryRow(ctx, `
		SELECT user_id, balance_cents, updated_at
		FROM wallets WHERE user_id=$1 FOR UPDATE
	`, userID).Scan(&w.UserID, &w.BalanceCents, &w.UpdatedAt)
	if err != nil {
		return Wallet{}, err
	}

	newBal := w.BalanceCents + amountCents
	if err := tx.QueryRow(ctx, `
		UPDATE wallets SET balance_cents=$2, updated_at=NOW()
		WHERE user_id=$1
		RETURNING balance_cents, updated_at
	`, userID, newBal).Scan(&w.BalanceCents, &w.UpdatedAt); err != nil {
		return Wallet{}, err
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO wallet_transactions
		    (user_id, type, amount_cents, balance_after, memo)
		VALUES ($1, 'topup', $2, $3, 'Nạp tiền (mock)')
	`, userID, amountCents, newBal); err != nil {
		return Wallet{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return Wallet{}, err
	}
	return w, nil
}

// Transfer moves money from -> to atomically. The flow:
//  1. validate amount & not self
//  2. require friendship status='accepted'
//  3. reject if either side has blocked the other
//  4. get-or-create direct conversation between the two users
//  5. lock both wallet rows in stable (sorted) order
//  6. check sender funds, debit sender, credit receiver
//  7. insert a money-message in the conversation
//  8. insert two wallet_transactions rows (transfer_out, transfer_in)
//     linking to the message
//  9. commit and return enough info for the handler to fan-out WS events
//
// Returns ErrSelfTransfer / ErrNotFriends / ErrBlocked / ErrInsufficientFunds
// / ErrAmount* on validation failure.
func (s *Service) Transfer(
	ctx context.Context,
	fromUser, toUser uuid.UUID,
	amountCents int64,
	memo string,
) (TransferResult, error) {
	if fromUser == toUser {
		return TransferResult{}, ErrSelfTransfer
	}
	if amountCents <= 0 {
		return TransferResult{}, ErrInvalidAmount
	}
	if amountCents < MinTransferCents {
		return TransferResult{}, ErrAmountTooSmall
	}
	if amountCents > MaxTransferCents {
		return TransferResult{}, ErrAmountTooLarge
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return TransferResult{}, err
	}
	defer tx.Rollback(ctx)

	// 2. Friendship check
	a, b := orderPair(fromUser, toUser)
	var friendCount int
	if err := tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM friendships
		WHERE user_low=$1 AND user_high=$2 AND status='accepted'
	`, a, b).Scan(&friendCount); err != nil {
		return TransferResult{}, err
	}
	if friendCount == 0 {
		return TransferResult{}, ErrNotFriends
	}

	// 3. Block check (both directions)
	var blocked int
	if err := tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM user_blocks
		WHERE (blocker_id=$1 AND blocked_id=$2)
		   OR (blocker_id=$2 AND blocked_id=$1)
	`, fromUser, toUser).Scan(&blocked); err != nil {
		return TransferResult{}, err
	}
	if blocked > 0 {
		return TransferResult{}, ErrBlocked
	}

	// 4. Get-or-create the direct conversation
	var convID uuid.UUID
	err = tx.QueryRow(ctx, `
		SELECT c.id
		FROM conversations c
		JOIN conversation_members m1 ON m1.conversation_id=c.id AND m1.user_id=$1
		JOIN conversation_members m2 ON m2.conversation_id=c.id AND m2.user_id=$2
		WHERE c.type='direct'
		LIMIT 1
	`, fromUser, toUser).Scan(&convID)
	if errors.Is(err, pgx.ErrNoRows) {
		if err := tx.QueryRow(ctx, `
			INSERT INTO conversations (type, created_by) VALUES ('direct', $1) RETURNING id
		`, fromUser).Scan(&convID); err != nil {
			return TransferResult{}, err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, role)
			VALUES ($1, $2, 'member'), ($1, $3, 'member')
		`, convID, fromUser, toUser); err != nil {
			return TransferResult{}, err
		}
	} else if err != nil {
		return TransferResult{}, err
	}

	// 5. Ensure both wallet rows exist, then lock them in stable order.
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallets (user_id) VALUES ($1), ($2)
		ON CONFLICT (user_id) DO NOTHING
	`, fromUser, toUser); err != nil {
		return TransferResult{}, err
	}

	lockOrder := []uuid.UUID{fromUser, toUser}
	if fromUser.String() > toUser.String() {
		lockOrder = []uuid.UUID{toUser, fromUser}
	}
	balances := map[uuid.UUID]int64{}
	for _, uid := range lockOrder {
		var bal int64
		if err := tx.QueryRow(ctx, `
			SELECT balance_cents FROM wallets WHERE user_id=$1 FOR UPDATE
		`, uid).Scan(&bal); err != nil {
			return TransferResult{}, err
		}
		balances[uid] = bal
	}

	// 6. Funds check & update balances
	if balances[fromUser] < amountCents {
		return TransferResult{}, ErrInsufficientFunds
	}
	newFromBal := balances[fromUser] - amountCents
	newToBal := balances[toUser] + amountCents

	if _, err := tx.Exec(ctx, `
		UPDATE wallets SET balance_cents=$2, updated_at=NOW() WHERE user_id=$1
	`, fromUser, newFromBal); err != nil {
		return TransferResult{}, err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE wallets SET balance_cents=$2, updated_at=NOW() WHERE user_id=$1
	`, toUser, newToBal); err != nil {
		return TransferResult{}, err
	}

	// We allocate the txn UUIDs in Go so we can stamp the message with them.
	outTxnID := uuid.New()
	inTxnID := uuid.New()

	// 7. Money message
	m, err := s.msgs.InsertMoneyMessageTx(ctx, tx, convID, fromUser, amountCents, outTxnID, memo)
	if err != nil {
		return TransferResult{}, err
	}

	// 8. Transactions
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallet_transactions
		    (id, user_id, counterparty_id, type, amount_cents, balance_after, memo, related_message_id)
		VALUES ($1, $2, $3, 'transfer_out', $4, $5, NULLIF($6,''), $7)
	`, outTxnID, fromUser, toUser, amountCents, newFromBal, memo, m.ID); err != nil {
		return TransferResult{}, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallet_transactions
		    (id, user_id, counterparty_id, type, amount_cents, balance_after, memo, related_message_id)
		VALUES ($1, $2, $3, 'transfer_in', $4, $5, NULLIF($6,''), $7)
	`, inTxnID, toUser, fromUser, amountCents, newToBal, memo, m.ID); err != nil {
		return TransferResult{}, err
	}

	// Load both display profiles for the WS payloads. We do this inside the
	// tx so the read is consistent even if a profile changes mid-flight.
	var sender, receiver Counterparty
	sender.ID = fromUser
	receiver.ID = toUser
	if err := tx.QueryRow(ctx, `
		SELECT display_name, COALESCE(avatar_url,'') FROM users WHERE id=$1
	`, fromUser).Scan(&sender.DisplayName, &sender.AvatarURL); err != nil {
		return TransferResult{}, err
	}
	if err := tx.QueryRow(ctx, `
		SELECT display_name, COALESCE(avatar_url,'') FROM users WHERE id=$1
	`, toUser).Scan(&receiver.DisplayName, &receiver.AvatarURL); err != nil {
		return TransferResult{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return TransferResult{}, err
	}

	return TransferResult{
		TxnID:           outTxnID,
		MessageID:       m.ID,
		ConversationID:  convID,
		NewBalanceCents: newFromBal,
		ReceiverID:      toUser,
		ReceiverBalance: newToBal,
		Message:         m,
		Counterparty:    receiver,
		Sender:          sender,
	}, nil
}

// History returns the caller's transactions newest-first (capped at 50),
// joined to the counterparty profile when present.
func (s *Service) History(ctx context.Context, userID uuid.UUID) ([]Transaction, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT t.id, t.type, t.amount_cents, t.balance_after,
		       COALESCE(t.memo,''),
		       t.counterparty_id, u.display_name, COALESCE(u.avatar_url,''),
		       t.related_message_id, t.created_at
		FROM wallet_transactions t
		LEFT JOIN users u ON u.id = t.counterparty_id
		WHERE t.user_id = $1
		ORDER BY t.created_at DESC
		LIMIT 50
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Transaction, 0)
	for rows.Next() {
		var (
			t        Transaction
			cpID     *uuid.UUID
			cpName   *string
			cpAvatar *string
		)
		if err := rows.Scan(&t.ID, &t.Type, &t.AmountCents, &t.BalanceAfter,
			&t.Memo, &cpID, &cpName, &cpAvatar, &t.RelatedMessage, &t.CreatedAt); err != nil {
			return nil, err
		}
		if cpID != nil {
			t.Counterparty = &Counterparty{
				ID:          *cpID,
				DisplayName: derefStr(cpName),
				AvatarURL:   derefStr(cpAvatar),
			}
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func derefStr(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// orderPair returns the two UUIDs sorted ascending by string form. This
// matches the convention in friendships.user_low / user_high.
func orderPair(a, b uuid.UUID) (uuid.UUID, uuid.UUID) {
	if a.String() < b.String() {
		return a, b
	}
	return b, a
}

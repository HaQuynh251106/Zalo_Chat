package contact

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Friendship struct {
	UserID      uuid.UUID `json:"user_id"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
	Status      string    `json:"status"`    // pending | accepted | blocked
	Direction   string    `json:"direction"` // incoming | outgoing | "" (for accepted)
	CreatedAt   time.Time `json:"created_at"`
}

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

func (s *Service) SendRequest(ctx context.Context, fromUser, toUser uuid.UUID) error {
	if fromUser == toUser {
		return errors.New("cannot friend self")
	}
	a, b := orderPair(fromUser, toUser)
	_, err := s.pool.Exec(ctx, `
		INSERT INTO friendships (user_low, user_high, requested_by, status)
		VALUES ($1, $2, $3, 'pending')
		ON CONFLICT (user_low, user_high) DO NOTHING
	`, a, b, fromUser)
	return err
}

func (s *Service) Accept(ctx context.Context, me, peer uuid.UUID) error {
	a, b := orderPair(me, peer)
	tag, err := s.pool.Exec(ctx, `
		UPDATE friendships
		SET status='accepted', accepted_at = NOW()
		WHERE user_low=$1 AND user_high=$2 AND status='pending' AND requested_by <> $3
	`, a, b, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("no pending request to accept")
	}
	return nil
}

// RemovePending deletes a pending friendship between me and peer.
// Used for both "Cancel outgoing" (I sent it) and "Reject incoming" (they sent it).
func (s *Service) RemovePending(ctx context.Context, me, peer uuid.UUID) error {
	a, b := orderPair(me, peer)
	tag, err := s.pool.Exec(ctx, `
		DELETE FROM friendships
		WHERE user_low=$1 AND user_high=$2 AND status='pending'
	`, a, b)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("no pending request between you and this user")
	}
	return nil
}

func (s *Service) List(ctx context.Context, me uuid.UUID) ([]Friendship, error) {
	// Exclude friends whose direct conversation with me has been hidden.
	// "Ẩn hoàn toàn" — the peer must disappear from the contacts list too,
	// only re-appearing inside the PIN-gated hidden chats screen.
	rows, err := s.pool.Query(ctx, `
		SELECT
			CASE WHEN f.user_low = $1 THEN f.user_high ELSE f.user_low END AS peer_id,
			u.display_name, COALESCE(u.avatar_url,''),
			f.status,
			CASE
			    WHEN f.status <> 'pending' THEN ''
			    WHEN f.requested_by = $1 THEN 'outgoing'
			    ELSE 'incoming'
			END AS direction,
			f.created_at
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.user_low = $1 THEN f.user_high ELSE f.user_low END
		WHERE (f.user_low = $1 OR f.user_high = $1)
		  AND NOT EXISTS (
		      SELECT 1
		      FROM conversations c
		      JOIN conversation_members me_cm
		           ON me_cm.conversation_id = c.id AND me_cm.user_id = $1
		      JOIN conversation_members peer_cm
		           ON peer_cm.conversation_id = c.id
		          AND peer_cm.user_id = CASE WHEN f.user_low = $1
		                                     THEN f.user_high
		                                     ELSE f.user_low END
		      WHERE c.type = 'direct'
		        AND me_cm.hidden_at IS NOT NULL
		  )
		ORDER BY f.created_at DESC
	`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Friendship, 0)
	for rows.Next() {
		var f Friendship
		if err := rows.Scan(&f.UserID, &f.DisplayName, &f.AvatarURL,
			&f.Status, &f.Direction, &f.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

func orderPair(a, b uuid.UUID) (uuid.UUID, uuid.UUID) {
	if a.String() < b.String() {
		return a, b
	}
	return b, a
}

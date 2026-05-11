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
	Status      string    `json:"status"` // pending, accepted, blocked
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

func (s *Service) List(ctx context.Context, me uuid.UUID) ([]Friendship, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT
			CASE WHEN f.user_low = $1 THEN f.user_high ELSE f.user_low END AS peer_id,
			u.display_name, COALESCE(u.avatar_url,''), f.status, f.created_at
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.user_low = $1 THEN f.user_high ELSE f.user_low END
		WHERE f.user_low = $1 OR f.user_high = $1
		ORDER BY f.created_at DESC
	`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Friendship, 0)
	for rows.Next() {
		var f Friendship
		if err := rows.Scan(&f.UserID, &f.DisplayName, &f.AvatarURL, &f.Status, &f.CreatedAt); err != nil {
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

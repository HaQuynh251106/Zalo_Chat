package user

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Profile struct {
	ID          uuid.UUID `json:"id"`
	Phone       string    `json:"phone"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
	Bio         string    `json:"bio"`
	CreatedAt   time.Time `json:"created_at"`
}

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

func (s *Service) Me(ctx context.Context, userID uuid.UUID) (Profile, error) {
	var p Profile
	err := s.pool.QueryRow(ctx, `
		SELECT id, phone, display_name, COALESCE(avatar_url,''), COALESCE(bio,''), created_at
		FROM users WHERE id=$1
	`, userID).Scan(&p.ID, &p.Phone, &p.DisplayName, &p.AvatarURL, &p.Bio, &p.CreatedAt)
	return p, err
}

func (s *Service) Update(ctx context.Context, userID uuid.UUID, displayName, avatarURL, bio string) (Profile, error) {
	_, err := s.pool.Exec(ctx, `
		UPDATE users
		SET display_name = COALESCE(NULLIF($2,''), display_name),
		    avatar_url   = COALESCE(NULLIF($3,''), avatar_url),
		    bio          = COALESCE(NULLIF($4,''), bio),
		    updated_at   = NOW()
		WHERE id = $1
	`, userID, displayName, avatarURL, bio)
	if err != nil {
		return Profile{}, err
	}
	return s.Me(ctx, userID)
}

func (s *Service) SearchByPhone(ctx context.Context, phone string) (Profile, error) {
	var p Profile
	err := s.pool.QueryRow(ctx, `
		SELECT id, phone, display_name, COALESCE(avatar_url,''), COALESCE(bio,''), created_at
		FROM users WHERE phone=$1
	`, phone).Scan(&p.ID, &p.Phone, &p.DisplayName, &p.AvatarURL, &p.Bio, &p.CreatedAt)
	return p, err
}

func (s *Service) UpdatePushToken(ctx context.Context, userID uuid.UUID, deviceID, pushToken, platform string) error {
	if deviceID == "" {
		return errors.New("missing device id")
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO devices (id, user_id, push_token, platform, last_seen_at)
		VALUES ($1, $2, NULLIF($3,''), $4, NOW())
		ON CONFLICT (id) DO UPDATE
		SET user_id      = EXCLUDED.user_id,
		    push_token   = EXCLUDED.push_token,
		    platform     = COALESCE(NULLIF(EXCLUDED.platform,''), devices.platform),
		    last_seen_at = NOW()
	`, deviceID, userID, pushToken, platform)
	return err
}

func (s *Service) Block(ctx context.Context, blocker, blocked uuid.UUID) error {
	if blocker == blocked {
		return errors.New("cannot block yourself")
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, blocker, blocked)
	return err
}

func (s *Service) Unblock(ctx context.Context, blocker, blocked uuid.UUID) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id=$2`, blocker, blocked)
	return err
}

func (s *Service) ListBlocked(ctx context.Context, blocker uuid.UUID) ([]Profile, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT u.id, u.phone, u.display_name, COALESCE(u.avatar_url,''), COALESCE(u.bio,''), u.created_at
		FROM user_blocks b
		JOIN users u ON u.id = b.blocked_id
		WHERE b.blocker_id = $1
		ORDER BY b.created_at DESC
	`, blocker)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Profile, 0)
	for rows.Next() {
		var p Profile
		if err := rows.Scan(&p.ID, &p.Phone, &p.DisplayName, &p.AvatarURL, &p.Bio, &p.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

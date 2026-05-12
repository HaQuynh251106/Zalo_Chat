package user

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrPinNotSet   = errors.New("hide pin not set")
	ErrWrongPin    = errors.New("wrong pin")
	ErrInvalidPin  = errors.New("pin must be 4-12 digits")
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

// SearchByPhone returns a profile by exact phone match, but treats the user
// as "not found" if the caller has hidden their direct conversation with them.
// This is part of the "ẩn hoàn toàn" privacy guarantee.
func (s *Service) SearchByPhone(ctx context.Context, requester uuid.UUID, phone string) (Profile, error) {
	var p Profile
	err := s.pool.QueryRow(ctx, `
		SELECT u.id, u.phone, u.display_name, COALESCE(u.avatar_url,''),
		       COALESCE(u.bio,''), u.created_at
		FROM users u
		WHERE u.phone = $1
		  AND u.id <> $2
		  AND NOT EXISTS (
		      SELECT 1
		      FROM conversations c
		      JOIN conversation_members me_cm
		           ON me_cm.conversation_id = c.id AND me_cm.user_id = $2
		      JOIN conversation_members peer_cm
		           ON peer_cm.conversation_id = c.id AND peer_cm.user_id = u.id
		      WHERE c.type = 'direct'
		        AND me_cm.hidden_at IS NOT NULL
		  )
	`, phone, requester).Scan(&p.ID, &p.Phone, &p.DisplayName, &p.AvatarURL, &p.Bio, &p.CreatedAt)
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

// HasHidePin returns whether the user has set their PIN for hidden conversations.
func (s *Service) HasHidePin(ctx context.Context, userID uuid.UUID) (bool, error) {
	var h sql.NullString
	err := s.pool.QueryRow(ctx,
		`SELECT hide_pin_hash FROM users WHERE id=$1`, userID).Scan(&h)
	if err != nil {
		return false, err
	}
	return h.Valid && h.String != "", nil
}

// SetHidePin sets or changes the hide PIN. If a PIN already exists,
// oldPin must match.
func (s *Service) SetHidePin(ctx context.Context, userID uuid.UUID, oldPin, newPin string) error {
	if !validPin(newPin) {
		return ErrInvalidPin
	}
	var existing sql.NullString
	if err := s.pool.QueryRow(ctx,
		`SELECT hide_pin_hash FROM users WHERE id=$1`, userID).Scan(&existing); err != nil {
		return err
	}
	if existing.Valid && existing.String != "" {
		if err := bcrypt.CompareHashAndPassword(
			[]byte(existing.String), []byte(oldPin)); err != nil {
			return ErrWrongPin
		}
	}
	newHash, err := bcrypt.GenerateFromPassword([]byte(newPin), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx,
		`UPDATE users SET hide_pin_hash=$2 WHERE id=$1`, userID, string(newHash))
	return err
}

// VerifyHidePin returns nil if the PIN matches.
// Returns ErrPinNotSet when the user has no PIN yet, or ErrWrongPin otherwise.
func (s *Service) VerifyHidePin(ctx context.Context, userID uuid.UUID, pin string) error {
	var h sql.NullString
	if err := s.pool.QueryRow(ctx,
		`SELECT hide_pin_hash FROM users WHERE id=$1`, userID).Scan(&h); err != nil {
		return err
	}
	if !h.Valid || h.String == "" {
		return ErrPinNotSet
	}
	if err := bcrypt.CompareHashAndPassword([]byte(h.String), []byte(pin)); err != nil {
		return ErrWrongPin
	}
	return nil
}

func validPin(p string) bool {
	if len(p) < 4 || len(p) > 12 {
		return false
	}
	for _, r := range p {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
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

package auth

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrPhoneTaken         = errors.New("phone already registered")
	ErrInvalidCredentials = errors.New("invalid credentials")
)

type UserRow struct {
	ID          uuid.UUID `json:"id"`
	Phone       string    `json:"phone"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
	CreatedAt   time.Time `json:"created_at"`
}

type RequestInfo struct {
	IP        string
	UserAgent string
}

type DeviceSession struct {
	ID               string     `json:"id"`
	DeviceName       string     `json:"device_name"`
	Platform         string     `json:"platform"`
	PushTokenPresent bool       `json:"push_token_present"`
	LastSeenAt       time.Time  `json:"last_seen_at"`
	CreatedAt        time.Time  `json:"created_at"`
	Current          bool       `json:"current"`
	RefreshExpiresAt *time.Time `json:"refresh_expires_at,omitempty"`
}

type Service struct {
	pool   *pgxpool.Pool
	issuer *TokenIssuer
}

func NewService(pool *pgxpool.Pool, issuer *TokenIssuer) *Service {
	return &Service{pool: pool, issuer: issuer}
}

func (s *Service) Register(ctx context.Context, phone, password, displayName string, info RequestInfo) (UserRow, error) {
	phone = strings.TrimSpace(phone)
	if phone == "" || len(password) < 6 {
		s.logEvent(ctx, nil, "", "register", false, info, map[string]any{"phone": phone, "reason": "invalid_input"})
		return UserRow{}, errors.New("phone or password invalid")
	}
	hash, err := hashPassword(password)
	if err != nil {
		return UserRow{}, err
	}

	var u UserRow
	err = s.pool.QueryRow(ctx, `
		INSERT INTO users (phone, password_hash, display_name)
		VALUES ($1, $2, $3)
		RETURNING id, phone, display_name, COALESCE(avatar_url,''), created_at
	`, phone, string(hash), displayName).Scan(&u.ID, &u.Phone, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "users_phone_key") {
			s.logEvent(ctx, nil, "", "register", false, info, map[string]any{"phone": phone, "reason": "phone_taken"})
			return UserRow{}, ErrPhoneTaken
		}
		s.logEvent(ctx, nil, "", "register", false, info, map[string]any{"phone": phone, "reason": "db_error"})
		return UserRow{}, err
	}
	s.logEvent(ctx, &u.ID, "", "register", true, info, map[string]any{"phone": phone})
	return u, nil
}

func (s *Service) Login(ctx context.Context, phone, password, deviceID, deviceName, platform string, info RequestInfo) (UserRow, string, string, string, error) {
	var (
		u    UserRow
		hash string
	)
	err := s.pool.QueryRow(ctx, `
		SELECT id, phone, display_name, COALESCE(avatar_url,''), created_at, password_hash
		FROM users WHERE phone=$1
	`, phone).Scan(&u.ID, &u.Phone, &u.DisplayName, &u.AvatarURL, &u.CreatedAt, &hash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			s.logEvent(ctx, nil, deviceID, "login", false, info, map[string]any{"phone": phone, "reason": "not_found"})
			return UserRow{}, "", "", "", ErrInvalidCredentials
		}
		return UserRow{}, "", "", "", err
	}
	ok, needsUpgrade := verifyPassword(hash, password)
	if !ok {
		s.logEvent(ctx, &u.ID, deviceID, "login", false, info, map[string]any{"phone": phone, "reason": "bad_password"})
		return UserRow{}, "", "", "", ErrInvalidCredentials
	}

	if deviceID == "" {
		deviceID = uuid.NewString()
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO devices (id, user_id, device_name, platform, last_seen_at)
		VALUES ($1, $2, $3, $4, NOW())
			ON CONFLICT (id) DO UPDATE
			SET user_id     = EXCLUDED.user_id,
			    device_name = EXCLUDED.device_name,
			    platform    = EXCLUDED.platform,
			    last_seen_at = NOW()
	`, deviceID, u.ID, deviceName, platform)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	if needsUpgrade {
		if upgraded, err := hashPassword(password); err == nil {
			_, _ = s.pool.Exec(ctx, `UPDATE users SET password_hash=$2, updated_at=NOW() WHERE id=$1`, u.ID, upgraded)
		}
	}

	access, refresh, err := s.issueSession(ctx, u.ID, deviceID, info)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	s.logEvent(ctx, &u.ID, deviceID, "login", true, info, map[string]any{"platform": platform})
	return u, access, refresh, deviceID, nil
}

func (s *Service) RefreshSession(ctx context.Context, refreshToken string, info RequestInfo) (UserRow, string, string, string, error) {
	claims, err := s.issuer.VerifyRefresh(refreshToken)
	if err != nil {
		s.logEvent(ctx, nil, "", "refresh", false, info, map[string]any{"reason": "invalid_signature"})
		return UserRow{}, "", "", "", ErrInvalidCredentials
	}
	oldID, err := uuid.Parse(claims.ID)
	if err != nil {
		s.logEvent(ctx, &claims.UserID, claims.DeviceID, "refresh", false, info, map[string]any{"reason": "invalid_jti"})
		return UserRow{}, "", "", "", ErrInvalidCredentials
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	defer tx.Rollback(ctx)

	var oldExpires time.Time
	err = tx.QueryRow(ctx, `
		SELECT expires_at
		FROM refresh_tokens
		WHERE id=$1 AND user_id=$2 AND device_id=$3 AND revoked_at IS NULL AND expires_at > NOW()
		FOR UPDATE
	`, oldID, claims.UserID, claims.DeviceID).Scan(&oldExpires)
	if err != nil {
		s.logEvent(ctx, &claims.UserID, claims.DeviceID, "refresh", false, info, map[string]any{"reason": "revoked_or_expired"})
		if errors.Is(err, pgx.ErrNoRows) {
			return UserRow{}, "", "", "", ErrInvalidCredentials
		}
		return UserRow{}, "", "", "", err
	}

	var u UserRow
	err = tx.QueryRow(ctx, `
			SELECT u.id, u.phone, u.display_name, COALESCE(u.avatar_url,''), u.created_at
			FROM users u
			JOIN devices d ON d.user_id = u.id AND d.id = $2
			WHERE u.id = $1
	`, claims.UserID, claims.DeviceID).Scan(&u.ID, &u.Phone, &u.DisplayName, &u.AvatarURL, &u.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return UserRow{}, "", "", "", ErrInvalidCredentials
		}
		return UserRow{}, "", "", "", err
	}

	_, err = tx.Exec(ctx, `UPDATE devices SET last_seen_at = NOW() WHERE id = $1 AND user_id = $2`, claims.DeviceID, claims.UserID)
	if err != nil {
		return UserRow{}, "", "", "", err
	}

	access, err := s.issuer.Access(u.ID, claims.DeviceID)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	refresh, err := s.issuer.Refresh(u.ID, claims.DeviceID)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	newClaims, err := s.issuer.VerifyRefresh(refresh)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	expiresAt := newClaims.ExpiresAt.Time
	newID, err := uuid.Parse(newClaims.ID)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO refresh_tokens (id, user_id, device_id, expires_at, created_ip, user_agent)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, newID, u.ID, claims.DeviceID, expiresAt, info.IP, info.UserAgent)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	_, err = tx.Exec(ctx, `UPDATE refresh_tokens SET revoked_at=NOW(), replaced_by=$2 WHERE id=$1`, oldID, newID)
	if err != nil {
		return UserRow{}, "", "", "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return UserRow{}, "", "", "", err
	}
	s.logEvent(ctx, &u.ID, claims.DeviceID, "refresh", true, info, nil)
	return u, access, refresh, claims.DeviceID, nil
}

func (s *Service) ListDevices(ctx context.Context, userID uuid.UUID, currentDeviceID string) ([]DeviceSession, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT d.id, COALESCE(d.device_name,''), COALESCE(d.platform,''), d.push_token IS NOT NULL,
		       d.last_seen_at, d.created_at, MAX(rt.expires_at) FILTER (WHERE rt.revoked_at IS NULL)
		FROM devices d
		LEFT JOIN refresh_tokens rt ON rt.device_id=d.id AND rt.user_id=d.user_id
		WHERE d.user_id=$1
		GROUP BY d.id, d.device_name, d.platform, d.push_token, d.last_seen_at, d.created_at
		ORDER BY d.last_seen_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]DeviceSession, 0)
	for rows.Next() {
		var d DeviceSession
		if err := rows.Scan(&d.ID, &d.DeviceName, &d.Platform, &d.PushTokenPresent, &d.LastSeenAt, &d.CreatedAt, &d.RefreshExpiresAt); err != nil {
			return nil, err
		}
		d.Current = d.ID == currentDeviceID
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Service) LogoutDevice(ctx context.Context, userID uuid.UUID, deviceID string, info RequestInfo) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE refresh_tokens SET revoked_at=NOW()
		WHERE user_id=$1 AND device_id=$2 AND revoked_at IS NULL
	`, userID, deviceID)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM devices WHERE user_id=$1 AND id=$2`, userID, deviceID)
	if err != nil {
		return err
	}
	s.logEvent(ctx, &userID, deviceID, "logout_device", true, info, map[string]any{"revoked_tokens": tag.RowsAffected()})
	return nil
}

func (s *Service) LogoutAllDevices(ctx context.Context, userID uuid.UUID, info RequestInfo) error {
	tag, err := s.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL`, userID)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM devices WHERE user_id=$1`, userID)
	if err != nil {
		return err
	}
	s.logEvent(ctx, &userID, "", "logout_all_devices", true, info, map[string]any{"revoked_tokens": tag.RowsAffected()})
	return nil
}

func (s *Service) issueSession(ctx context.Context, userID uuid.UUID, deviceID string, info RequestInfo) (string, string, error) {
	access, err := s.issuer.Access(userID, deviceID)
	if err != nil {
		return "", "", err
	}
	refresh, err := s.issuer.Refresh(userID, deviceID)
	if err != nil {
		return "", "", err
	}
	claims, err := s.issuer.VerifyRefresh(refresh)
	if err != nil {
		return "", "", err
	}
	id, err := uuid.Parse(claims.ID)
	if err != nil {
		return "", "", err
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO refresh_tokens (id, user_id, device_id, expires_at, created_ip, user_agent)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, id, userID, deviceID, claims.ExpiresAt.Time, info.IP, info.UserAgent)
	if err != nil {
		return "", "", err
	}
	return access, refresh, nil
}

func (s *Service) logEvent(ctx context.Context, userID *uuid.UUID, deviceID, eventType string, success bool, info RequestInfo, metadata map[string]any) {
	meta := []byte(`{}`)
	if metadata != nil {
		if b, err := json.Marshal(metadata); err == nil {
			meta = b
		}
	}
	_, _ = s.pool.Exec(ctx, `
		INSERT INTO auth_events (user_id, device_id, event_type, success, ip, user_agent, metadata)
		VALUES ($1, NULLIF($2,''), $3, $4, NULLIF($5,''), NULLIF($6,''), $7)
	`, userID, deviceID, eventType, success, info.IP, info.UserAgent, meta)
}

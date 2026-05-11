package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type Claims struct {
	UserID    uuid.UUID `json:"uid"`
	DeviceID  string    `json:"did,omitempty"`
	TokenType string    `json:"typ"`
	jwt.RegisteredClaims
}

type TokenIssuer struct {
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewIssuer(secret string, accessTTL, refreshTTL time.Duration) *TokenIssuer {
	return &TokenIssuer{
		secret:     []byte(secret),
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
	}
}

func (i *TokenIssuer) Access(userID uuid.UUID, deviceID string) (string, error) {
	return i.sign(userID, deviceID, "access", i.accessTTL)
}

func (i *TokenIssuer) Refresh(userID uuid.UUID, deviceID string) (string, error) {
	return i.sign(userID, deviceID, "refresh", i.refreshTTL)
}

func (i *TokenIssuer) sign(userID uuid.UUID, deviceID, tokenType string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID:    userID,
		DeviceID:  deviceID,
		TokenType: tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        uuid.NewString(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			NotBefore: jwt.NewNumericDate(now),
			Subject:   userID.String(),
			Issuer:    "zalo-clone",
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return t.SignedString(i.secret)
}

func (i *TokenIssuer) Verify(token string) (*Claims, error) {
	parsed, err := jwt.ParseWithClaims(token, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return i.secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

func (i *TokenIssuer) VerifyAccess(token string) (*Claims, error) {
	claims, err := i.Verify(token)
	if err != nil {
		return nil, err
	}
	if claims.TokenType != "access" {
		return nil, errors.New("not an access token")
	}
	return claims, nil
}

func (i *TokenIssuer) VerifyRefresh(token string) (*Claims, error) {
	claims, err := i.Verify(token)
	if err != nil {
		return nil, err
	}
	if claims.TokenType != "refresh" {
		return nil, errors.New("not a refresh token")
	}
	return claims, nil
}

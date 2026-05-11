package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/a1234/zalo-clone/backend/internal/auth"
	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/google/uuid"
)

type ctxKey string

const (
	ctxUserID   ctxKey = "uid"
	ctxDeviceID ctxKey = "did"
)

func RequireAuth(issuer *auth.TokenIssuer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token := bearer(r)
			if token == "" {
				token = r.URL.Query().Get("token")
			}
			if token == "" {
				httpx.Error(w, http.StatusUnauthorized, "missing token")
				return
			}
			claims, err := issuer.VerifyAccess(token)
			if err != nil {
				httpx.Error(w, http.StatusUnauthorized, "invalid token")
				return
			}
			ctx := context.WithValue(r.Context(), ctxUserID, claims.UserID)
			ctx = context.WithValue(ctx, ctxDeviceID, claims.DeviceID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func UserIDFrom(ctx context.Context) (uuid.UUID, bool) {
	v, ok := ctx.Value(ctxUserID).(uuid.UUID)
	return v, ok
}

func DeviceIDFrom(ctx context.Context) string {
	v, _ := ctx.Value(ctxDeviceID).(string)
	return v
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	return ""
}

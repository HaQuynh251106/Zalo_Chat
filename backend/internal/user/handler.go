package user

import (
	"errors"
	"net/http"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	p, err := h.svc.Me(r.Context(), uid)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

type updateReq struct {
	DisplayName string `json:"display_name"`
	AvatarURL   string `json:"avatar_url"`
	Bio         string `json:"bio"`
}

func (h *Handler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	var req updateReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	p, err := h.svc.Update(r.Context(), uid, req.DisplayName, req.AvatarURL, req.Bio)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

func (h *Handler) SearchByPhone(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	if phone == "" {
		httpx.Error(w, http.StatusBadRequest, "missing phone")
		return
	}
	p, err := h.svc.SearchByPhone(r.Context(), phone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, http.StatusNotFound, "user not found")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

type pushTokenReq struct {
	PushToken string `json:"push_token"`
	Platform  string `json:"platform"`
}

type blockReq struct {
	UserID uuid.UUID `json:"user_id"`
}

func (h *Handler) Block(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req blockReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.Block(r.Context(), me, req.UserID); err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "blocked"})
}

func (h *Handler) Unblock(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req blockReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.Unblock(r.Context(), me, req.UserID); err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "unblocked"})
}

func (h *Handler) ListBlocked(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	list, err := h.svc.ListBlocked(r.Context(), me)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func (h *Handler) UpdatePushToken(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	deviceID := middleware.DeviceIDFrom(r.Context())
	var req pushTokenReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.UpdatePushToken(r.Context(), uid, deviceID, req.PushToken, req.Platform); err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

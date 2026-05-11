package conversation

import (
	"errors"
	"net/http"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/a1234/zalo-clone/backend/internal/ws"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type Handler struct {
	svc *Service
	hub *ws.Hub
}

func NewHandler(svc *Service, hub *ws.Hub) *Handler { return &Handler{svc: svc, hub: hub} }

type openDirectReq struct {
	PeerID uuid.UUID `json:"peer_id"`
}

type createGroupReq struct {
	Title     string      `json:"title"`
	MemberIDs []uuid.UUID `json:"member_ids"`
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	list, err := h.svc.ListForUser(r.Context(), me)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func (h *Handler) OpenDirect(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req openDirectReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	c, err := h.svc.OpenDirect(r.Context(), me, req.PeerID)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, c)
}

func (h *Handler) CreateGroup(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req createGroupReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	c, err := h.svc.CreateGroup(r.Context(), me, req.Title, req.MemberIDs)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusCreated, c)
}

type muteReq struct {
	Until *time.Time `json:"until"` // nil to unmute; far-future to mute "forever"
}

func (h *Handler) SetMute(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req muteReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.SetMute(r.Context(), conv, me, req.Until); err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, "not a member")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"muted_until": req.Until})
}

func (h *Handler) MarkRead(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	readAt, err := h.svc.MarkRead(r.Context(), conv, me)
	if err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, err.Error())
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "read.receipt",
		Payload: map[string]any{
			"conversation_id": conv,
			"user_id":         me,
			"read_at":         readAt,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

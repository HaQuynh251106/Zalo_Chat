package reaction

import (
	"errors"
	"net/http"

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

type setReq struct {
	Emoji string `json:"emoji"` // "" to clear
}

func (h *Handler) Set(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	msgID, err := uuid.Parse(chi.URLParam(r, "msgID"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req setReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	conv, err := h.svc.Set(r.Context(), msgID, me, req.Emoji)
	if err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, "not a member")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "message.reaction",
		Payload: map[string]any{
			"message_id":      msgID,
			"conversation_id": conv,
			"user_id":         me,
			"emoji":           req.Emoji,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

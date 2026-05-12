package contact

import (
	"net/http"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/a1234/zalo-clone/backend/internal/ws"
	"github.com/google/uuid"
)

type Handler struct {
	svc *Service
	hub *ws.Hub
}

func NewHandler(svc *Service, hub *ws.Hub) *Handler {
	return &Handler{svc: svc, hub: hub}
}

type peerReq struct {
	UserID uuid.UUID `json:"user_id"`
}

func (h *Handler) Request(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req peerReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.SendRequest(r.Context(), me, req.UserID); err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	// Push to BOTH so each side refreshes their contacts list.
	h.hub.BroadcastToUsers([]uuid.UUID{req.UserID, me}, ws.Event{
		Type: "contact.changed",
		Payload: map[string]any{
			"action":       "requested",
			"from_user_id": me,
			"to_user_id":   req.UserID,
		},
	})
	httpx.JSON(w, http.StatusCreated, map[string]string{"status": "pending"})
}

func (h *Handler) Accept(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req peerReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.Accept(r.Context(), me, req.UserID); err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	h.hub.BroadcastToUsers([]uuid.UUID{req.UserID, me}, ws.Event{
		Type: "contact.changed",
		Payload: map[string]any{
			"action":   "accepted",
			"user_a":   me,
			"user_b":   req.UserID,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "accepted"})
}

// Cancel handles both "I cancel my own outgoing request" AND
// "I reject an incoming request" — same DB operation: delete the
// pending row between us.
func (h *Handler) Cancel(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req peerReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.RemovePending(r.Context(), me, req.UserID); err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	h.hub.BroadcastToUsers([]uuid.UUID{req.UserID, me}, ws.Event{
		Type: "contact.changed",
		Payload: map[string]any{
			"action":  "removed",
			"user_a":  me,
			"user_b":  req.UserID,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	list, err := h.svc.List(r.Context(), me)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

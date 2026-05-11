package message

import (
	"errors"
	"net/http"
	"strconv"
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

func NewHandler(svc *Service, hub *ws.Hub) *Handler {
	return &Handler{svc: svc, hub: hub}
}

type sendReq struct {
	Type      string     `json:"type"`
	Body      string     `json:"body"`
	MediaURL  string     `json:"media_url"`
	ReplyToID *uuid.UUID `json:"reply_to_id"`
}

func (h *Handler) Send(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid conversation id")
		return
	}
	var req sendReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	m, err := h.svc.Send(r.Context(), conv, me, req.Type, req.Body, req.MediaURL, req.ReplyToID)
	if err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, err.Error())
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{Type: "message.new", Payload: m})
	httpx.JSON(w, http.StatusCreated, m)
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid conversation id")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	var before *time.Time
	if b := r.URL.Query().Get("before"); b != "" {
		if t, err := time.Parse(time.RFC3339Nano, b); err == nil {
			before = &t
		}
	}
	list, err := h.svc.List(r.Context(), conv, me, limit, before)
	if err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, err.Error())
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func (h *Handler) Recall(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	id, err := uuid.Parse(chi.URLParam(r, "msgID"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	convID, err := h.svc.Recall(r.Context(), id, me)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	h.hub.BroadcastToConversation(r.Context(), convID, ws.Event{
		Type: "message.recalled",
		Payload: map[string]any{
			"id":              id,
			"conversation_id": convID,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "recalled"})
}

package call

import (
	"errors"
	"net/http"
	"strconv"

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

type initiateReq struct {
	ConversationID uuid.UUID `json:"conversation_id"`
	Kind           string    `json:"kind"`
}

func (h *Handler) Initiate(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req initiateReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	c, err := h.svc.Initiate(r.Context(), req.ConversationID, me, req.Kind)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidKind):
			httpx.Error(w, http.StatusBadRequest, "kind must be voice|video")
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		default:
			httpx.Error(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	h.hub.BroadcastToConversation(r.Context(), c.ConversationID, ws.Event{
		Type:    "call.incoming",
		Payload: c,
	})
	httpx.JSON(w, http.StatusCreated, c)
}

func (h *Handler) Accept(w http.ResponseWriter, r *http.Request) {
	h.runTransition(w, r, "call.answered", func(callID, actor uuid.UUID) (Call, error) {
		return h.svc.Accept(r.Context(), callID, actor)
	})
}

func (h *Handler) Reject(w http.ResponseWriter, r *http.Request) {
	h.runTransition(w, r, "call.rejected", func(callID, actor uuid.UUID) (Call, error) {
		return h.svc.Reject(r.Context(), callID, actor)
	})
}

func (h *Handler) End(w http.ResponseWriter, r *http.Request) {
	h.runTransition(w, r, "call.ended", func(callID, actor uuid.UUID) (Call, error) {
		return h.svc.End(r.Context(), callID, actor)
	})
}

func (h *Handler) runTransition(
	w http.ResponseWriter, r *http.Request, evType string,
	fn func(callID, actor uuid.UUID) (Call, error),
) {
	me, _ := middleware.UserIDFrom(r.Context())
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	c, err := fn(id, me)
	if err != nil {
		switch {
		case errors.Is(err, ErrCallNotFound):
			httpx.Error(w, http.StatusNotFound, "call not found")
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		case errors.Is(err, ErrInvalidStatus):
			httpx.Error(w, http.StatusConflict, "invalid call state")
		default:
			httpx.Error(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	h.hub.BroadcastToConversation(r.Context(), c.ConversationID, ws.Event{
		Type:    evType,
		Payload: c,
	})
	httpx.JSON(w, http.StatusOK, c)
}

type signalReq struct {
	Kind    string         `json:"kind"`    // offer | answer | ice
	Payload map[string]any `json:"payload"` // SDP body or ICE candidate
}

func (h *Handler) Signal(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req signalReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	conv, err := h.svc.ConversationOf(r.Context(), id)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "call not found")
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "call.signal",
		Payload: map[string]any{
			"call_id": id,
			"from":    me,
			"kind":    req.Kind,
			"payload": req.Payload,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) Recent(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	list, err := h.svc.Recent(r.Context(), me, limit)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

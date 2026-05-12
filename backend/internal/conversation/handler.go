package conversation

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/a1234/zalo-clone/backend/internal/ws"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

// PinVerifier verifies a user's "hide" PIN. Returns nil on success.
type PinVerifier func(ctx context.Context, userID uuid.UUID, pin string) error

type Handler struct {
	svc         *Service
	hub         *ws.Hub
	verifyPin   PinVerifier
}

func NewHandler(svc *Service, hub *ws.Hub, verifyPin PinVerifier) *Handler {
	return &Handler{svc: svc, hub: hub, verifyPin: verifyPin}
}

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

func (h *Handler) Members(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	list, err := h.svc.Members(r.Context(), conv, me)
	if err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, "not a member")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func (h *Handler) Leave(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	if err := h.svc.Leave(r.Context(), conv, me); err != nil {
		switch {
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		case errors.Is(err, ErrLastMemberOfDirect):
			httpx.Error(w, http.StatusBadRequest, "cannot leave direct chat")
		default:
			httpx.Error(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	// Optional WS broadcast to other members.
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "conversation.member_left",
		Payload: map[string]any{
			"conversation_id": conv,
			"user_id":         me,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "left"})
}

type hideReq struct {
	Pin string `json:"pin"`
}

// Hide marks the conversation as hidden for the caller. Requires PIN.
func (h *Handler) Hide(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req hideReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.verifyPin(r.Context(), me, req.Pin); err != nil {
		// Generic 401 mapping; user/Service errors are exposed via verifyPin.
		httpx.Error(w, http.StatusUnauthorized, err.Error())
		return
	}
	if err := h.svc.SetHidden(r.Context(), conv, me, true); err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, "not a member")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"hidden": true})
}

// Unhide reveals a hidden conversation. Caller is assumed to have already
// passed PIN verification to access the hidden list in the first place.
func (h *Handler) Unhide(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	if err := h.svc.SetHidden(r.Context(), conv, me, false); err != nil {
		if errors.Is(err, ErrNotMember) {
			httpx.Error(w, http.StatusForbidden, "not a member")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"hidden": false})
}

type listHiddenReq struct {
	Pin string `json:"pin"`
}

// ListHidden returns the user's hidden conversations after verifying PIN.
func (h *Handler) ListHidden(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req listHiddenReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.verifyPin(r.Context(), me, req.Pin); err != nil {
		httpx.Error(w, http.StatusUnauthorized, err.Error())
		return
	}
	list, err := h.svc.ListHiddenForUser(r.Context(), me)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

type addMembersReq struct {
	UserIDs []uuid.UUID `json:"user_ids"`
}

func (h *Handler) AddMembers(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req addMembersReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	added, err := h.svc.AddMembers(r.Context(), conv, me, req.UserIDs)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		case errors.Is(err, ErrNotGroup):
			httpx.Error(w, http.StatusBadRequest, "not a group")
		case errors.Is(err, ErrForbidden):
			httpx.Error(w, http.StatusForbidden, "no permission")
		default:
			httpx.Error(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "conversation.members_added",
		Payload: map[string]any{
			"conversation_id": conv,
			"user_ids":        added,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]any{"added": added})
}

func (h *Handler) KickMember(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	target, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid user id")
		return
	}
	if err := h.svc.KickMember(r.Context(), conv, me, target); err != nil {
		switch {
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		case errors.Is(err, ErrNotGroup):
			httpx.Error(w, http.StatusBadRequest, "not a group")
		case errors.Is(err, ErrForbidden):
			httpx.Error(w, http.StatusForbidden, "no permission")
		case errors.Is(err, ErrCannotKickOwner):
			httpx.Error(w, http.StatusConflict, "cannot kick owner")
		default:
			httpx.Error(w, http.StatusBadRequest, err.Error())
		}
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "conversation.member_kicked",
		Payload: map[string]any{
			"conversation_id": conv,
			"user_id":         target,
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

type updateInfoReq struct {
	Title     string `json:"title"`
	AvatarURL string `json:"avatar_url"`
}

func (h *Handler) UpdateInfo(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req updateInfoReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.UpdateInfo(r.Context(), conv, me, req.Title, req.AvatarURL); err != nil {
		switch {
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		case errors.Is(err, ErrNotGroup):
			httpx.Error(w, http.StatusBadRequest, "not a group")
		case errors.Is(err, ErrForbidden):
			httpx.Error(w, http.StatusForbidden, "no permission")
		default:
			httpx.Error(w, http.StatusBadRequest, err.Error())
		}
		return
	}
	payload := map[string]any{"conversation_id": conv}
	if req.Title != "" {
		payload["title"] = req.Title
	}
	if req.AvatarURL != "" {
		payload["avatar_url"] = req.AvatarURL
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type:    "conversation.updated",
		Payload: payload,
	})
	httpx.JSON(w, http.StatusOK, payload)
}

func (h *Handler) CreateInvite(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	conv, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	token, err := h.svc.CreateInvite(r.Context(), conv, me)
	if err != nil {
		switch {
		case errors.Is(err, ErrNotMember):
			httpx.Error(w, http.StatusForbidden, "not a member")
		case errors.Is(err, ErrNotGroup):
			httpx.Error(w, http.StatusBadRequest, "not a group")
		case errors.Is(err, ErrForbidden):
			httpx.Error(w, http.StatusForbidden, "no permission")
		default:
			httpx.Error(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	httpx.JSON(w, http.StatusCreated, map[string]string{"token": token})
}

type joinReq struct {
	Token string `json:"token"`
}

func (h *Handler) JoinViaInvite(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req joinReq
	if err := httpx.Decode(r, &req); err != nil || req.Token == "" {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	conv, err := h.svc.JoinViaInvite(r.Context(), me, req.Token)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	h.hub.BroadcastToConversation(r.Context(), conv, ws.Event{
		Type: "conversation.members_added",
		Payload: map[string]any{
			"conversation_id": conv,
			"user_ids":        []uuid.UUID{me},
		},
	})
	httpx.JSON(w, http.StatusOK, map[string]any{"conversation_id": conv})
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

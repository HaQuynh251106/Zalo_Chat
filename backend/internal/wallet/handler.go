package wallet

import (
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/a1234/zalo-clone/backend/internal/ws"
)

type Handler struct {
	svc *Service
	hub *ws.Hub
}

func NewHandler(svc *Service, hub *ws.Hub) *Handler {
	return &Handler{svc: svc, hub: hub}
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	wal, err := h.svc.Me(r.Context(), uid)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, wal)
}

func (h *Handler) History(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	list, err := h.svc.History(r.Context(), uid)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

type topupReq struct {
	AmountCents int64  `json:"amount_cents"`
	Source      string `json:"source"`
}

func (h *Handler) Topup(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	var req topupReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Source != "" && strings.ToLower(req.Source) != "mock" {
		httpx.Error(w, http.StatusBadRequest, "unsupported topup source")
		return
	}
	wal, err := h.svc.Topup(r.Context(), uid, req.AmountCents)
	if err != nil {
		writeWalletErr(w, err)
		return
	}
	// Fan-out wallet.updated to caller's own sockets (web + mobile).
	if h.hub != nil {
		h.hub.BroadcastToUser(uid, ws.Event{
			Type: "wallet.updated",
			Payload: map[string]any{
				"balance_cents": wal.BalanceCents,
			},
		})
	}
	httpx.JSON(w, http.StatusOK, wal)
}

type transferReq struct {
	ToUserID    uuid.UUID `json:"to_user_id"`
	AmountCents int64     `json:"amount_cents"`
	Memo        string    `json:"memo"`
}

type transferResp struct {
	TxnID           uuid.UUID `json:"txn_id"`
	MessageID       uuid.UUID `json:"message_id"`
	ConversationID  uuid.UUID `json:"conversation_id"`
	NewBalanceCents int64     `json:"new_balance_cents"`
}

func (h *Handler) Transfer(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	var req transferReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	res, err := h.svc.Transfer(r.Context(), uid, req.ToUserID, req.AmountCents, req.Memo)
	if err != nil {
		writeWalletErr(w, err)
		return
	}

	// Fan-out WS events. The chat UI also needs message.created so the
	// money bubble appears in real time on both sides.
	if h.hub != nil {
		// Wallet balance updates for both sides.
		h.hub.BroadcastToUser(uid, ws.Event{
			Type:    "wallet.updated",
			Payload: map[string]any{"balance_cents": res.NewBalanceCents},
		})
		h.hub.BroadcastToUser(res.ReceiverID, ws.Event{
			Type:    "wallet.updated",
			Payload: map[string]any{"balance_cents": res.ReceiverBalance},
		})

		// In-chat money bubble for both members. Existing clients consume
		// message.new; newer wallet surfaces can also listen for message.created.
		h.hub.BroadcastToConversation(r.Context(), res.ConversationID, ws.Event{
			Type:    "message.created",
			Payload: res.Message,
		})
		h.hub.BroadcastToConversation(r.Context(), res.ConversationID, ws.Event{
			Type:    "message.new",
			Payload: res.Message,
		})

		// Toast for the receiver only.
		h.hub.BroadcastToUser(res.ReceiverID, ws.Event{
			Type: "money.received",
			Payload: map[string]any{
				"from": map[string]any{
					"id":     res.Sender.ID,
					"name":   res.Sender.DisplayName,
					"avatar": res.Sender.AvatarURL,
				},
				"amount_cents":    req.AmountCents,
				"txn_id":          res.TxnID,
				"message_id":      res.MessageID,
				"conversation_id": res.ConversationID,
				"memo":            req.Memo,
			},
		})
	}

	httpx.JSON(w, http.StatusOK, transferResp{
		TxnID:           res.TxnID,
		MessageID:       res.MessageID,
		ConversationID:  res.ConversationID,
		NewBalanceCents: res.NewBalanceCents,
	})
}

// OpenRedPocket: receiver claims the visual reveal for a money message they
// received. Idempotent. On first open, broadcasts money.opened to both sides
// so the sender's chat UI can update from "Đã gửi" to "Đã được mở".
func (h *Handler) OpenRedPocket(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	raw := chi.URLParam(r, "msgID")
	msgID, err := uuid.Parse(raw)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid message id")
		return
	}
	res, err := h.svc.OpenRedPocket(r.Context(), uid, msgID)
	if err != nil {
		if errors.Is(err, ErrPocketNotFound) {
			httpx.Error(w, http.StatusNotFound, "red pocket not found")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}

	if h.hub != nil && !res.AlreadyOpened {
		// Tell the whole conversation (both sides) that the pocket is open;
		// chat UIs can flip the closed envelope to the opened state without
		// a full reload.
		h.hub.BroadcastToConversation(r.Context(), res.ConversationID, ws.Event{
			Type: "money.opened",
			Payload: map[string]any{
				"message_id":      res.MessageID,
				"conversation_id": res.ConversationID,
				"opened_at":       res.OpenedAt,
				"by_user_id":      uid,
			},
		})
	}

	httpx.JSON(w, http.StatusOK, res)
}

func writeWalletErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrSelfTransfer):
		httpx.Error(w, http.StatusBadRequest, "cannot transfer to yourself")
	case errors.Is(err, ErrInvalidAmount):
		httpx.Error(w, http.StatusBadRequest, "invalid amount")
	case errors.Is(err, ErrAmountTooSmall):
		httpx.Error(w, http.StatusBadRequest, "amount below minimum")
	case errors.Is(err, ErrAmountTooLarge):
		httpx.Error(w, http.StatusBadRequest, "amount above maximum")
	case errors.Is(err, ErrInsufficientFunds):
		httpx.Error(w, http.StatusBadRequest, "insufficient_funds")
	case errors.Is(err, ErrNotFriends):
		httpx.Error(w, http.StatusForbidden, "not_friends")
	case errors.Is(err, ErrBlocked):
		httpx.Error(w, http.StatusForbidden, "blocked")
	default:
		httpx.Error(w, http.StatusInternalServerError, err.Error())
	}
}

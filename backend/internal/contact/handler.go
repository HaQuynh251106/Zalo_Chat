package contact

import (
	"net/http"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/google/uuid"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

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
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "accepted"})
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

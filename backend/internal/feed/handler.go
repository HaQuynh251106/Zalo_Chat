package feed

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

type createReq struct {
	Body       string   `json:"body"`
	Media      []string `json:"media"`
	Visibility string   `json:"visibility"`
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	var req createReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Body == "" && len(req.Media) == 0 {
		httpx.Error(w, http.StatusBadRequest, "post empty")
		return
	}
	p, err := h.svc.Create(r.Context(), me, req.Body, req.Media, req.Visibility)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusCreated, p)
}

func (h *Handler) Timeline(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	var before *time.Time
	if b := r.URL.Query().Get("before"); b != "" {
		if t, err := time.Parse(time.RFC3339Nano, b); err == nil {
			before = &t
		}
	}
	list, err := h.svc.Timeline(r.Context(), me, limit, before)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	p, err := h.svc.Get(r.Context(), id, me)
	if err != nil {
		switch {
		case errors.Is(err, ErrPostNotFound):
			httpx.Error(w, http.StatusNotFound, "not found")
		case errors.Is(err, ErrForbidden):
			httpx.Error(w, http.StatusForbidden, "forbidden")
		default:
			httpx.Error(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

type reactReq struct {
	Reaction string `json:"reaction"`
}

func (h *Handler) React(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req reactReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if err := h.svc.React(r.Context(), id, me, req.Reaction); err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type commentReq struct {
	Body string `json:"body"`
}

func (h *Handler) AddComment(w http.ResponseWriter, r *http.Request) {
	me, _ := middleware.UserIDFrom(r.Context())
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req commentReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	c, err := h.svc.AddComment(r.Context(), id, me, req.Body)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusCreated, c)
}

func (h *Handler) ListComments(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	list, err := h.svc.ListComments(r.Context(), id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

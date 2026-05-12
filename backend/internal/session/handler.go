package session

import (
	"net/http"
	"strings"

	"github.com/a1234/zalo-clone/backend/internal/auth"
	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/go-chi/chi/v5"
)

type Handler struct {
	authSvc *auth.Service
}

func NewHandler(authSvc *auth.Service) *Handler {
	return &Handler{authSvc: authSvc}
}

func (h *Handler) ListDevices(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	devices, err := h.authSvc.ListDevices(r.Context(), uid, middleware.DeviceIDFrom(r.Context()))
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, devices)
}

func (h *Handler) LogoutCurrent(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	deviceID := middleware.DeviceIDFrom(r.Context())
	if deviceID == "" {
		httpx.Error(w, http.StatusBadRequest, "missing device id")
		return
	}
	if err := h.authSvc.LogoutDevice(r.Context(), uid, deviceID, requestInfo(r)); err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (h *Handler) LogoutDevice(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	deviceID := chi.URLParam(r, "deviceID")
	if deviceID == "" {
		httpx.Error(w, http.StatusBadRequest, "missing device id")
		return
	}
	if err := h.authSvc.LogoutDevice(r.Context(), uid, deviceID, requestInfo(r)); err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (h *Handler) LogoutAllDevices(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "no user")
		return
	}
	if err := h.authSvc.LogoutAllDevices(r.Context(), uid, requestInfo(r)); err != nil {
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func requestInfo(r *http.Request) auth.RequestInfo {
	return auth.RequestInfo{IP: clientIP(r), UserAgent: r.UserAgent()}
}

func clientIP(r *http.Request) string {
	if h := r.Header.Get("X-Forwarded-For"); h != "" {
		return strings.TrimSpace(strings.Split(h, ",")[0])
	}
	if h := r.Header.Get("X-Real-IP"); h != "" {
		return strings.TrimSpace(h)
	}
	return r.RemoteAddr
}

package auth

import (
	"errors"
	"net/http"
	"strings"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

type registerReq struct {
	Phone       string `json:"phone"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
}

type loginReq struct {
	Phone      string `json:"phone"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
	Platform   string `json:"platform"`
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

type authResp struct {
	User         any    `json:"user"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	DeviceID     string `json:"device_id,omitempty"`
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	u, err := h.svc.Register(r.Context(), req.Phone, req.Password, req.DisplayName, requestInfo(r))
	if err != nil {
		if errors.Is(err, ErrPhoneTaken) {
			httpx.Error(w, http.StatusConflict, err.Error())
			return
		}
		httpx.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	httpx.JSON(w, http.StatusCreated, u)
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	u, access, refresh, deviceID, err := h.svc.Login(r.Context(), req.Phone, req.Password, req.DeviceID, req.DeviceName, req.Platform, requestInfo(r))
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			httpx.Error(w, http.StatusUnauthorized, "invalid phone or password")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, authResp{
		User:         u,
		AccessToken:  access,
		RefreshToken: refresh,
		DeviceID:     deviceID,
	})
}

func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.Decode(r, &req); err != nil || req.RefreshToken == "" {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	u, access, refresh, deviceID, err := h.svc.RefreshSession(r.Context(), req.RefreshToken, requestInfo(r))
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			httpx.Error(w, http.StatusUnauthorized, "invalid refresh token")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, err.Error())
		return
	}
	httpx.JSON(w, http.StatusOK, authResp{
		User:         u,
		AccessToken:  access,
		RefreshToken: refresh,
		DeviceID:     deviceID,
	})
}

func requestInfo(r *http.Request) RequestInfo {
	return RequestInfo{IP: clientIP(r), UserAgent: r.UserAgent()}
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

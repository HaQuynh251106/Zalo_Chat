package media

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
)

const (
	maxUploadBytes = 20 << 20 // 20 MiB
)

var allowedExt = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
	".mp4": true, ".mov": true, ".webm": true,
	".m4a": true, ".aac": true, ".mp3": true, ".ogg": true,
	".pdf": true, ".txt": true,
}

type Handler struct {
	uploadDir     string
	publicBaseURL string
}

func NewHandler(uploadDir, publicBaseURL string) (*Handler, error) {
	if err := os.MkdirAll(uploadDir, 0o755); err != nil {
		return nil, fmt.Errorf("create upload dir: %w", err)
	}
	return &Handler{uploadDir: uploadDir, publicBaseURL: strings.TrimRight(publicBaseURL, "/")}, nil
}

// Upload accepts multipart/form-data with field "file".
func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes)
	if err := r.ParseMultipartForm(maxUploadBytes); err != nil {
		httpx.Error(w, http.StatusRequestEntityTooLarge, "file too large or invalid form")
		return
	}
	file, hdr, err := r.FormFile("file")
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "missing file field")
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(hdr.Filename))
	if !allowedExt[ext] {
		httpx.Error(w, http.StatusUnsupportedMediaType, "extension not allowed")
		return
	}

	// random filename: <user_id_short>-<ts>-<rand>.<ext>
	nameBytes := make([]byte, 8)
	if _, err := rand.Read(nameBytes); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "rand")
		return
	}
	stem := fmt.Sprintf("%s-%d-%s", shortID(userID.String()), time.Now().UnixNano(), hex.EncodeToString(nameBytes))
	day := time.Now().UTC().Format("2006/01/02")
	dir := filepath.Join(h.uploadDir, day)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "mkdir")
		return
	}
	finalName := stem + ext
	target := filepath.Join(dir, finalName)
	out, err := os.Create(target)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "create file")
		return
	}
	defer out.Close()
	if _, err := io.Copy(out, file); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "save file")
		_ = os.Remove(target)
		return
	}

	urlPath := "/static/" + day + "/" + finalName
	full := urlPath
	if h.publicBaseURL != "" {
		full = h.publicBaseURL + urlPath
	}
	httpx.JSON(w, http.StatusCreated, map[string]any{
		"url":       full,
		"path":      urlPath,
		"size":      hdr.Size,
		"mime_type": hdr.Header.Get("Content-Type"),
	})
}

// Static serves files from uploadDir under /static/.
func (h *Handler) Static() http.Handler {
	fs := http.FileServer(http.Dir(h.uploadDir))
	return http.StripPrefix("/static/", safeFileServer(fs))
}

func safeFileServer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Guard against path traversal — clean and ensure no leading slash escape.
		clean := filepath.Clean(r.URL.Path)
		if strings.Contains(clean, "..") {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func shortID(id string) string {
	if len(id) >= 8 {
		return id[:8]
	}
	return id
}


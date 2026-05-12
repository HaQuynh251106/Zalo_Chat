package httpx

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestJSONWritesDataEnvelope(t *testing.T) {
	rec := httptest.NewRecorder()

	JSON(rec, http.StatusCreated, map[string]string{"id": "123"})

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
		t.Fatalf("unexpected content type %q", got)
	}

	var body Envelope
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode response body: %v", err)
	}

	data, ok := body.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected data map, got %T", body.Data)
	}
	if data["id"] != "123" {
		t.Fatalf("expected id 123, got %v", data["id"])
	}
	if body.Error != "" {
		t.Fatalf("expected empty error, got %q", body.Error)
	}
}

func TestErrorWritesErrorEnvelope(t *testing.T) {
	rec := httptest.NewRecorder()

	Error(rec, http.StatusBadRequest, "invalid request")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, rec.Code)
	}

	var body Envelope
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode response body: %v", err)
	}
	if body.Error != "invalid request" {
		t.Fatalf("expected error message, got %q", body.Error)
	}
	if body.Data != nil {
		t.Fatalf("expected nil data, got %v", body.Data)
	}
}

func TestDecodeRejectsUnknownFields(t *testing.T) {
	var dst struct {
		Name string `json:"name"`
	}
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewBufferString(`{"name":"Lumo","extra":true}`))

	if err := Decode(req, &dst); err == nil {
		t.Fatal("expected unknown field error")
	}
}

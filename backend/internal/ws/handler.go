package ws

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

type Handler struct {
	hub      *Hub
	upgrader websocket.Upgrader
	writeTO  time.Duration
	pongWait time.Duration
}

func NewHandler(hub *Hub, writeTimeout, pongWait time.Duration) *Handler {
	return &Handler{
		hub:      hub,
		writeTO:  writeTimeout,
		pongWait: pongWait,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin:     func(r *http.Request) bool { return true },
		},
	}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFrom(r.Context())
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[ws] upgrade: %v", err)
		return
	}
	c := &Client{
		userID:   uid,
		deviceID: middleware.DeviceIDFrom(r.Context()),
		send:     make(chan []byte, 64),
	}
	h.hub.register(r.Context(), c)

	go h.writePump(conn, c)
	h.readPump(conn, c)
}

func (h *Handler) readPump(conn *websocket.Conn, c *Client) {
	defer func() {
		h.hub.unregister(context.Background(), c)
		_ = conn.Close()
	}()
	conn.SetReadLimit(1 << 20)
	_ = conn.SetReadDeadline(time.Now().Add(h.pongWait))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(h.pongWait))
		return nil
	})

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			return
		}
		var ev Event
		if err := json.Unmarshal(msg, &ev); err != nil {
			continue
		}
		// Client-originated events are validated server-side before fan-out.
		switch ev.Type {
		case "typing":
			convID, ok := conversationIDFromPayload(ev.Payload)
			if !ok || !h.hub.IsConversationMember(context.Background(), convID, c.userID) {
				continue
			}
			h.hub.BroadcastToConversation(context.Background(), convID, Event{
				Type: "typing",
				Payload: map[string]any{
					"conversation_id": convID,
					"user_id":         c.userID,
					"device_id":       c.deviceID,
					"is_typing":       typingStateFromPayload(ev.Payload),
				},
			})
		case "ping":
			h.hub.BroadcastToUsers([]uuid.UUID{c.userID}, Event{Type: "pong"})
		}
	}
}

func (h *Handler) writePump(conn *websocket.Conn, c *Client) {
	ticker := time.NewTicker((h.pongWait * 9) / 10)
	defer func() {
		ticker.Stop()
		_ = conn.Close()
	}()
	for {
		select {
		case msg, ok := <-c.send:
			_ = conn.SetWriteDeadline(time.Now().Add(h.writeTO))
			if !ok {
				_ = conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = conn.SetWriteDeadline(time.Now().Add(h.writeTO))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func conversationIDFromPayload(payload any) (uuid.UUID, bool) {
	m, ok := payload.(map[string]any)
	if !ok {
		return uuid.Nil, false
	}
	raw, ok := m["conversation_id"].(string)
	if !ok || raw == "" {
		return uuid.Nil, false
	}
	id, err := uuid.Parse(raw)
	return id, err == nil
}

func typingStateFromPayload(payload any) bool {
	m, ok := payload.(map[string]any)
	if !ok {
		return true
	}
	v, ok := m["is_typing"].(bool)
	if !ok {
		return true
	}
	return v
}

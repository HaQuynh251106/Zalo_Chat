package ws

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type Event struct {
	Type    string `json:"type"`
	Payload any    `json:"payload,omitempty"`
}

type Client struct {
	userID   uuid.UUID
	deviceID string
	send     chan []byte
}

type Hub struct {
	mu     sync.RWMutex
	byUser map[uuid.UUID]map[*Client]struct{}
	pool   *pgxpool.Pool
	rdb    *redis.Client
}

func NewHub(pool *pgxpool.Pool, rdb *redis.Client) *Hub {
	return &Hub{
		byUser: make(map[uuid.UUID]map[*Client]struct{}),
		pool:   pool,
		rdb:    rdb,
	}
}

func (h *Hub) register(ctx context.Context, c *Client) {
	h.mu.Lock()
	set, ok := h.byUser[c.userID]
	if !ok {
		set = make(map[*Client]struct{})
		h.byUser[c.userID] = set
	}
	wasOffline := len(set) == 0
	set[c] = struct{}{}
	total := len(set)
	h.mu.Unlock()

	h.touchDevice(ctx, c)
	if wasOffline {
		h.setPresence(ctx, c.userID, true)
		h.BroadcastPresence(ctx, c.userID, true)
	}
	log.Printf("[ws] connected user=%s device=%s total=%d", c.userID, c.deviceID, total)
}

func (h *Hub) unregister(ctx context.Context, c *Client) {
	h.mu.Lock()
	nowOffline := false
	if set, ok := h.byUser[c.userID]; ok {
		delete(set, c)
		if len(set) == 0 {
			delete(h.byUser, c.userID)
			nowOffline = true
		}
	}
	close(c.send)
	h.mu.Unlock()

	h.touchDevice(ctx, c)
	if nowOffline {
		h.setPresence(ctx, c.userID, false)
		h.BroadcastPresence(ctx, c.userID, false)
	}
	log.Printf("[ws] disconnected user=%s device=%s", c.userID, c.deviceID)
}

func (h *Hub) Online(userID uuid.UUID) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.byUser[userID]
	return ok
}

func (h *Hub) sendToUser(userID uuid.UUID, raw []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.byUser[userID] {
		select {
		case c.send <- raw:
		default:
			// drop on backpressure
		}
	}
}

func (h *Hub) BroadcastToUsers(userIDs []uuid.UUID, ev Event) {
	raw, err := json.Marshal(ev)
	if err != nil {
		log.Printf("[ws] marshal: %v", err)
		return
	}
	for _, u := range userIDs {
		h.sendToUser(u, raw)
	}
}

func (h *Hub) BroadcastToConversation(ctx context.Context, conv uuid.UUID, ev Event) {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	rows, err := h.pool.Query(ctx, `SELECT user_id FROM conversation_members WHERE conversation_id=$1`, conv)
	if err != nil {
		log.Printf("[ws] member lookup: %v", err)
		return
	}
	defer rows.Close()

	ids := make([]uuid.UUID, 0)
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			continue
		}
		ids = append(ids, id)
	}
	h.BroadcastToUsers(ids, ev)
}

func (h *Hub) BroadcastPresence(ctx context.Context, userID uuid.UUID, online bool) {
	ids, err := h.usersSharingConversations(ctx, userID)
	if err != nil {
		log.Printf("[ws] presence subscribers: %v", err)
		return
	}
	h.BroadcastToUsers(ids, Event{
		Type: "presence.update",
		Payload: map[string]any{
			"user_id": userID,
			"online":  online,
		},
	})
}

func (h *Hub) IsConversationMember(ctx context.Context, conv, user uuid.UUID) bool {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	var ok int
	err := h.pool.QueryRow(ctx, `SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, conv, user).Scan(&ok)
	return err == nil
}

func (h *Hub) usersSharingConversations(ctx context.Context, userID uuid.UUID) ([]uuid.UUID, error) {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	rows, err := h.pool.Query(ctx, `
		SELECT DISTINCT cm2.user_id
		FROM conversation_members cm
		JOIN conversation_members cm2 ON cm2.conversation_id = cm.conversation_id
		WHERE cm.user_id = $1 AND cm2.user_id <> $1
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	ids := make([]uuid.UUID, 0)
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (h *Hub) touchDevice(ctx context.Context, c *Client) {
	if c.deviceID == "" {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	_, err := h.pool.Exec(ctx, `UPDATE devices SET last_seen_at = NOW() WHERE id=$1 AND user_id=$2`, c.deviceID, c.userID)
	if err != nil {
		log.Printf("[ws] touch device: %v", err)
	}
}

func (h *Hub) setPresence(ctx context.Context, userID uuid.UUID, online bool) {
	if h.rdb == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	key := "presence:user:" + userID.String()
	var err error
	if online {
		err = h.rdb.Set(ctx, key, "online", 2*time.Minute).Err()
	} else {
		err = h.rdb.Del(ctx, key).Err()
	}
	if err != nil {
		log.Printf("[ws] redis presence: %v", err)
	}
}

func (h *Hub) BroadcastAll(ev Event) {
	raw, err := json.Marshal(ev)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, set := range h.byUser {
		for c := range set {
			select {
			case c.send <- raw:
			default:
			}
		}
	}
}

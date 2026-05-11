package message

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Message struct {
	ID             uuid.UUID  `json:"id"`
	ConversationID uuid.UUID  `json:"conversation_id"`
	SenderID       uuid.UUID  `json:"sender_id"`
	Type           string     `json:"type"` // text|image|audio|video|file|system
	Body           string     `json:"body"`
	MediaURL       string     `json:"media_url,omitempty"`
	ReplyToID      *uuid.UUID `json:"reply_to_id,omitempty"`
	ReplyToSnippet string     `json:"reply_to_snippet,omitempty"`
	ReplyToSender  *uuid.UUID `json:"reply_to_sender,omitempty"`
	Recalled       bool       `json:"recalled"`
	CreatedAt      time.Time  `json:"created_at"`
	Reactions      []Reaction `json:"reactions,omitempty"`
}

type Reaction struct {
	UserID uuid.UUID `json:"user_id"`
	Emoji  string    `json:"emoji"`
}

var ErrNotMember = errors.New("not a member of conversation")

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

var ErrBlocked = errors.New("recipient blocked you")

func (s *Service) Send(ctx context.Context, conv, sender uuid.UUID, msgType, body, mediaURL string, replyTo *uuid.UUID) (Message, error) {
	if msgType == "" {
		msgType = "text"
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Message{}, err
	}
	defer tx.Rollback(ctx)

	var member int
	err = tx.QueryRow(ctx, `SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, conv, sender).Scan(&member)
	if errors.Is(err, pgx.ErrNoRows) {
		return Message{}, ErrNotMember
	}
	if err != nil {
		return Message{}, err
	}

	// Block check (for 1-1 direct only): if the other member has blocked sender, refuse.
	var blocked int
	err = tx.QueryRow(ctx, `
		SELECT 1
		FROM conversations c
		JOIN conversation_members other ON other.conversation_id = c.id AND other.user_id <> $2
		JOIN user_blocks b ON b.blocker_id = other.user_id AND b.blocked_id = $2
		WHERE c.id = $1 AND c.type = 'direct'
		LIMIT 1
	`, conv, sender).Scan(&blocked)
	if err == nil {
		return Message{}, ErrBlocked
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Message{}, err
	}

	var m Message
	err = tx.QueryRow(ctx, `
		WITH inserted AS (
		    INSERT INTO messages (conversation_id, sender_id, type, body, media_url, reply_to_id)
		    VALUES ($1,$2,$3,$4,NULLIF($5,''),$6)
		    RETURNING id, conversation_id, sender_id, type, body, media_url, reply_to_id, recalled, created_at
		)
		SELECT i.id, i.conversation_id, i.sender_id, i.type, i.body, COALESCE(i.media_url,''),
		       i.reply_to_id, i.recalled, i.created_at,
		       COALESCE(
		           CASE WHEN rep.recalled THEN '[đã thu hồi]'
		                WHEN rep.type = 'text' THEN LEFT(rep.body, 80)
		                ELSE '['||rep.type||']' END, '') AS reply_snippet,
		       rep.sender_id AS reply_sender
		FROM inserted i
		LEFT JOIN messages rep ON rep.id = i.reply_to_id
	`, conv, sender, msgType, body, mediaURL, replyTo).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &m.Body, &m.MediaURL, &m.ReplyToID,
		&m.Recalled, &m.CreatedAt, &m.ReplyToSnippet, &m.ReplyToSender,
	)
	if err != nil {
		return Message{}, err
	}
	preview := body
	if msgType != "text" {
		preview = "[" + msgType + "]"
	}
	if _, err = tx.Exec(ctx, `
		UPDATE conversations
		SET last_message_at = $2, last_message_preview = $3
		WHERE id = $1
	`, conv, m.CreatedAt, preview); err != nil {
		return Message{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Message{}, err
	}
	return m, nil
}

// List returns messages in a conversation, newest first, paginated by before-cursor.
func (s *Service) List(ctx context.Context, conv, requester uuid.UUID, limit int, before *time.Time) ([]Message, error) {
	var ok int
	err := s.pool.QueryRow(ctx, `SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, conv, requester).Scan(&ok)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotMember
	}
	if err != nil {
		return nil, err
	}

	if limit <= 0 || limit > 100 {
		limit = 30
	}
	args := []any{conv, limit}
	q := `
		SELECT m.id, m.conversation_id, m.sender_id, m.type,
		       CASE WHEN m.recalled THEN '' ELSE m.body END,
		       COALESCE(m.media_url,''), m.reply_to_id, m.recalled, m.created_at,
		       COALESCE(
		           CASE WHEN rep.recalled THEN '[đã thu hồi]'
		                WHEN rep.type = 'text' THEN LEFT(rep.body, 80)
		                ELSE '['||rep.type||']' END, '') AS reply_snippet,
		       rep.sender_id AS reply_sender
		FROM messages m
		LEFT JOIN messages rep ON rep.id = m.reply_to_id
		WHERE m.conversation_id = $1
	`
	if before != nil {
		q += " AND m.created_at < $3"
		args = append(args, *before)
	}
	q += " ORDER BY m.created_at DESC LIMIT $2"

	rows, err := s.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	msgs := make([]Message, 0, limit)
	ids := make([]uuid.UUID, 0, limit)
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &m.Body, &m.MediaURL,
			&m.ReplyToID, &m.Recalled, &m.CreatedAt, &m.ReplyToSnippet, &m.ReplyToSender); err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
		ids = append(ids, m.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// hydrate reactions
	if len(ids) > 0 {
		rrs, err := s.pool.Query(ctx, `
			SELECT message_id, user_id, emoji FROM message_reactions WHERE message_id = ANY($1)
		`, ids)
		if err != nil {
			return nil, err
		}
		defer rrs.Close()
		byID := make(map[uuid.UUID]int, len(msgs))
		for i, m := range msgs {
			byID[m.ID] = i
		}
		for rrs.Next() {
			var mid uuid.UUID
			var r Reaction
			if err := rrs.Scan(&mid, &r.UserID, &r.Emoji); err != nil {
				return nil, err
			}
			if idx, ok := byID[mid]; ok {
				msgs[idx].Reactions = append(msgs[idx].Reactions, r)
			}
		}
	}
	return msgs, nil
}

// Recall marks a message as recalled (only by sender, within 24h).
func (s *Service) Recall(ctx context.Context, msgID, requester uuid.UUID) (uuid.UUID, error) {
	var convID uuid.UUID
	var createdAt time.Time
	err := s.pool.QueryRow(ctx, `
		UPDATE messages
		SET recalled = TRUE, recalled_at = NOW()
		WHERE id = $1 AND sender_id = $2 AND created_at > NOW() - INTERVAL '24 hours'
		RETURNING conversation_id, created_at
	`, msgID, requester).Scan(&convID, &createdAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return uuid.Nil, errors.New("cannot recall this message")
		}
		return uuid.Nil, err
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE conversations
		SET last_message_preview = 'Tin nhắn đã được thu hồi'
		WHERE id = $1 AND last_message_at = $2
	`, convID, createdAt)
	if err != nil {
		return uuid.Nil, err
	}
	return convID, nil
}

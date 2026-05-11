package reaction

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Reaction struct {
	MessageID uuid.UUID `json:"message_id"`
	UserID    uuid.UUID `json:"user_id"`
	Emoji     string    `json:"emoji"`
	CreatedAt time.Time `json:"created_at"`
}

var ErrNotMember = errors.New("not a member of conversation")

type Service struct{ pool *pgxpool.Pool }

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

// Set upserts a reaction (emoji == "" => remove). Returns conv id for ws fan-out.
func (s *Service) Set(ctx context.Context, msgID, user uuid.UUID, emoji string) (uuid.UUID, error) {
	// 1. Verify user is in the conversation that this message belongs to.
	var conv uuid.UUID
	err := s.pool.QueryRow(ctx, `
		SELECT m.conversation_id
		FROM messages m
		JOIN conversation_members cm
		  ON cm.conversation_id = m.conversation_id AND cm.user_id = $2
		WHERE m.id = $1
	`, msgID, user).Scan(&conv)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return uuid.Nil, ErrNotMember
		}
		return uuid.Nil, err
	}
	if emoji == "" {
		_, err = s.pool.Exec(ctx, `DELETE FROM message_reactions WHERE message_id=$1 AND user_id=$2`, msgID, user)
		return conv, err
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO message_reactions (message_id, user_id, emoji)
		VALUES ($1, $2, $3)
		ON CONFLICT (message_id, user_id) DO UPDATE SET emoji = EXCLUDED.emoji, created_at = NOW()
	`, msgID, user, emoji)
	return conv, err
}

// ForMessages returns reactions grouped by message id (used for chat history hydration).
func (s *Service) ForMessages(ctx context.Context, msgIDs []uuid.UUID) (map[uuid.UUID][]Reaction, error) {
	out := make(map[uuid.UUID][]Reaction)
	if len(msgIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT message_id, user_id, emoji, created_at
		FROM message_reactions
		WHERE message_id = ANY($1)
	`, msgIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var r Reaction
		if err := rows.Scan(&r.MessageID, &r.UserID, &r.Emoji, &r.CreatedAt); err != nil {
			return nil, err
		}
		out[r.MessageID] = append(out[r.MessageID], r)
	}
	return out, rows.Err()
}

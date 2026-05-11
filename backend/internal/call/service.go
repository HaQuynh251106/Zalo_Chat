package call

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Call struct {
	ID             uuid.UUID  `json:"id"`
	ConversationID uuid.UUID  `json:"conversation_id"`
	InitiatorID    uuid.UUID  `json:"initiator_id"`
	InitiatorName  string     `json:"initiator_name"`
	InitiatorAvatr string     `json:"initiator_avatar"`
	Kind           string     `json:"kind"` // voice | video
	Status         string     `json:"status"`
	StartedAt      time.Time  `json:"started_at"`
	EndedAt        *time.Time `json:"ended_at,omitempty"`
}

var (
	ErrCallNotFound  = errors.New("call not found")
	ErrInvalidKind   = errors.New("invalid call kind")
	ErrNotMember     = errors.New("not a member of conversation")
	ErrInvalidStatus = errors.New("invalid call status transition")
)

type Service struct{ pool *pgxpool.Pool }

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

func (s *Service) Initiate(ctx context.Context, conv, initiator uuid.UUID, kind string) (Call, error) {
	if kind != "voice" && kind != "video" {
		return Call{}, ErrInvalidKind
	}
	// verify initiator is member
	var ok int
	err := s.pool.QueryRow(ctx, `SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, conv, initiator).Scan(&ok)
	if errors.Is(err, pgx.ErrNoRows) {
		return Call{}, ErrNotMember
	}
	if err != nil {
		return Call{}, err
	}
	var c Call
	err = s.pool.QueryRow(ctx, `
		INSERT INTO calls (conversation_id, initiator_id, kind, status)
		VALUES ($1, $2, $3, 'ringing')
		RETURNING id, conversation_id, initiator_id, kind, status, started_at
	`, conv, initiator, kind).Scan(&c.ID, &c.ConversationID, &c.InitiatorID, &c.Kind, &c.Status, &c.StartedAt)
	if err != nil {
		return Call{}, err
	}
	// hydrate initiator name
	_ = s.pool.QueryRow(ctx, `SELECT display_name, COALESCE(avatar_url,'') FROM users WHERE id=$1`, initiator).
		Scan(&c.InitiatorName, &c.InitiatorAvatr)
	return c, nil
}

func (s *Service) transition(ctx context.Context, callID, actor uuid.UUID, allowed []string, next string, setEnd bool) (Call, error) {
	// allowed: list of current statuses that may move to next.
	// For 'end', allowed includes initiator OR any member; for 'accept/reject' only non-initiator member.
	// We'll just enforce member-of-conversation here.
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Call{}, err
	}
	defer tx.Rollback(ctx)

	var (
		conv     uuid.UUID
		curStat  string
	)
	err = tx.QueryRow(ctx, `SELECT conversation_id, status FROM calls WHERE id=$1`, callID).Scan(&conv, &curStat)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Call{}, ErrCallNotFound
		}
		return Call{}, err
	}
	var member int
	if err := tx.QueryRow(ctx, `SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, conv, actor).Scan(&member); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Call{}, ErrNotMember
		}
		return Call{}, err
	}
	ok := false
	for _, a := range allowed {
		if a == curStat {
			ok = true
			break
		}
	}
	if !ok {
		return Call{}, ErrInvalidStatus
	}
	var c Call
	if setEnd {
		err = tx.QueryRow(ctx, `
			UPDATE calls SET status=$2, ended_at=NOW() WHERE id=$1
			RETURNING id, conversation_id, initiator_id, kind, status, started_at, ended_at
		`, callID, next).Scan(&c.ID, &c.ConversationID, &c.InitiatorID, &c.Kind, &c.Status, &c.StartedAt, &c.EndedAt)
	} else {
		err = tx.QueryRow(ctx, `
			UPDATE calls SET status=$2 WHERE id=$1
			RETURNING id, conversation_id, initiator_id, kind, status, started_at, ended_at
		`, callID, next).Scan(&c.ID, &c.ConversationID, &c.InitiatorID, &c.Kind, &c.Status, &c.StartedAt, &c.EndedAt)
	}
	if err != nil {
		return Call{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Call{}, err
	}
	_ = s.pool.QueryRow(ctx, `SELECT display_name, COALESCE(avatar_url,'') FROM users WHERE id=$1`, c.InitiatorID).
		Scan(&c.InitiatorName, &c.InitiatorAvatr)
	return c, nil
}

func (s *Service) Accept(ctx context.Context, callID, actor uuid.UUID) (Call, error) {
	return s.transition(ctx, callID, actor, []string{"ringing"}, "accepted", false)
}

func (s *Service) Reject(ctx context.Context, callID, actor uuid.UUID) (Call, error) {
	return s.transition(ctx, callID, actor, []string{"ringing"}, "rejected", true)
}

func (s *Service) End(ctx context.Context, callID, actor uuid.UUID) (Call, error) {
	return s.transition(ctx, callID, actor, []string{"ringing", "accepted"}, "ended", true)
}

// Recent lists last N calls in conversations the user is in.
func (s *Service) Recent(ctx context.Context, user uuid.UUID, limit int) ([]Call, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	rows, err := s.pool.Query(ctx, `
		SELECT c.id, c.conversation_id, c.initiator_id,
		       u.display_name, COALESCE(u.avatar_url,''),
		       c.kind, c.status, c.started_at, c.ended_at
		FROM calls c
		JOIN users u ON u.id = c.initiator_id
		JOIN conversation_members cm ON cm.conversation_id = c.conversation_id
		WHERE cm.user_id = $1
		ORDER BY c.started_at DESC
		LIMIT $2
	`, user, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Call, 0, limit)
	for rows.Next() {
		var c Call
		if err := rows.Scan(&c.ID, &c.ConversationID, &c.InitiatorID,
			&c.InitiatorName, &c.InitiatorAvatr,
			&c.Kind, &c.Status, &c.StartedAt, &c.EndedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ConversationOf returns the conversation_id for a given call (used by handler for ws fan-out).
func (s *Service) ConversationOf(ctx context.Context, callID uuid.UUID) (uuid.UUID, error) {
	var conv uuid.UUID
	err := s.pool.QueryRow(ctx, `SELECT conversation_id FROM calls WHERE id=$1`, callID).Scan(&conv)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrCallNotFound
	}
	return conv, err
}

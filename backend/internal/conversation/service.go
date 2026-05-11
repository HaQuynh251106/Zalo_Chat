package conversation

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Conversation struct {
	ID        uuid.UUID   `json:"id"`
	Type      string      `json:"type"` // direct | group
	Title     string      `json:"title"`
	AvatarURL string      `json:"avatar_url"`
	CreatedAt time.Time   `json:"created_at"`
	LastMsgAt *time.Time  `json:"last_message_at,omitempty"`
	LastMsg   string      `json:"last_message,omitempty"`
	UnreadCnt int         `json:"unread_count"`
	MemberIDs []uuid.UUID `json:"member_ids,omitempty"`
}

type Service struct {
	pool *pgxpool.Pool
}

var ErrNotMember = errors.New("not a member of conversation")

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

// OpenDirect: get-or-create a 1-1 conversation between me and peer.
func (s *Service) OpenDirect(ctx context.Context, me, peer uuid.UUID) (Conversation, error) {
	if me == peer {
		return Conversation{}, errors.New("cannot chat with self")
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Conversation{}, err
	}
	defer tx.Rollback(ctx)

	var convID uuid.UUID
	err = tx.QueryRow(ctx, `
		SELECT c.id
		FROM conversations c
		JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1
		JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2
		WHERE c.type='direct'
		LIMIT 1
	`, me, peer).Scan(&convID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return Conversation{}, err
	}

	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `
			INSERT INTO conversations (type, created_by) VALUES ('direct', $1) RETURNING id
		`, me).Scan(&convID)
		if err != nil {
			return Conversation{}, err
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, role)
			VALUES ($1,$2,'member'),($1,$3,'member')
		`, convID, me, peer)
		if err != nil {
			return Conversation{}, err
		}
		// Auto-establish friendship (Telegram-style: chatting = contact).
		// canonical: user_low < user_high
		a, b := me, peer
		if a.String() > b.String() {
			a, b = b, a
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO friendships (user_low, user_high, requested_by, status, accepted_at)
			VALUES ($1, $2, $3, 'accepted', NOW())
			ON CONFLICT (user_low, user_high) DO UPDATE
			SET status = 'accepted', accepted_at = COALESCE(friendships.accepted_at, NOW())
		`, a, b, me); err != nil {
			return Conversation{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return Conversation{}, err
	}
	return s.getByID(ctx, me, convID)
}

func (s *Service) CreateGroup(ctx context.Context, creator uuid.UUID, title string, memberIDs []uuid.UUID) (Conversation, error) {
	if title == "" {
		return Conversation{}, errors.New("title required")
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Conversation{}, err
	}
	defer tx.Rollback(ctx)

	var convID uuid.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, title, created_by) VALUES ('group',$1,$2) RETURNING id
	`, title, creator).Scan(&convID)
	if err != nil {
		return Conversation{}, err
	}
	if _, err = tx.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1,$2,'owner')
	`, convID, creator); err != nil {
		return Conversation{}, err
	}
	for _, m := range memberIDs {
		if m == creator {
			continue
		}
		if _, err = tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, role)
			VALUES ($1,$2,'member') ON CONFLICT DO NOTHING
		`, convID, m); err != nil {
			return Conversation{}, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return Conversation{}, err
	}
	return s.getByID(ctx, creator, convID)
}

func (s *Service) ListForUser(ctx context.Context, me uuid.UUID) ([]Conversation, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id, c.type,
		       COALESCE(c.title,
		         (SELECT u.display_name FROM conversation_members cm
		            JOIN users u ON u.id = cm.user_id
		           WHERE cm.conversation_id = c.id AND cm.user_id <> $1 LIMIT 1)
		       ) AS title,
		       COALESCE(c.avatar_url,'') AS avatar_url,
		       c.created_at,
		       c.last_message_at,
		       COALESCE(c.last_message_preview,'') AS last_msg,
		       (SELECT COUNT(*) FROM messages mm
		         WHERE mm.conversation_id = c.id
		           AND mm.created_at > COALESCE(m.last_read_at, 'epoch'::timestamptz)
		           AND mm.sender_id <> $1
		       ) AS unread
		FROM conversations c
		JOIN conversation_members m ON m.conversation_id = c.id
		WHERE m.user_id = $1
		ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
	`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Conversation, 0)
	for rows.Next() {
		var c Conversation
		if err := rows.Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedAt, &c.LastMsgAt, &c.LastMsg, &c.UnreadCnt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Service) getByID(ctx context.Context, me, convID uuid.UUID) (Conversation, error) {
	var c Conversation
	err := s.pool.QueryRow(ctx, `
		SELECT id, type,
		       COALESCE(title,'') AS title,
		       COALESCE(avatar_url,'') AS avatar_url,
		       created_at, last_message_at, COALESCE(last_message_preview,'')
		FROM conversations WHERE id = $1
	`, convID).Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedAt, &c.LastMsgAt, &c.LastMsg)
	if err != nil {
		return Conversation{}, err
	}

	rows, err := s.pool.Query(ctx, `SELECT user_id FROM conversation_members WHERE conversation_id=$1`, convID)
	if err != nil {
		return Conversation{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return Conversation{}, err
		}
		c.MemberIDs = append(c.MemberIDs, id)
	}
	return c, nil
}

func (s *Service) IsMember(ctx context.Context, conv, user uuid.UUID) (bool, error) {
	var x int
	err := s.pool.QueryRow(ctx, `SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, conv, user).Scan(&x)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

func (s *Service) MemberIDs(ctx context.Context, conv uuid.UUID) ([]uuid.UUID, error) {
	rows, err := s.pool.Query(ctx, `SELECT user_id FROM conversation_members WHERE conversation_id=$1`, conv)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]uuid.UUID, 0)
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func (s *Service) MarkRead(ctx context.Context, conv, user uuid.UUID) (time.Time, error) {
	readAt := time.Now().UTC()
	tag, err := s.pool.Exec(ctx, `
		UPDATE conversation_members SET last_read_at = $3
		WHERE conversation_id = $1 AND user_id = $2
	`, conv, user, readAt)
	if err != nil {
		return time.Time{}, err
	}
	if tag.RowsAffected() == 0 {
		return time.Time{}, ErrNotMember
	}
	return readAt, nil
}

// SetMute pauses notifications for this conversation. `until == nil` => unmute.
// `until` in the far future == "mute forever" (UX shortcut).
func (s *Service) SetMute(ctx context.Context, conv, user uuid.UUID, until *time.Time) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE conversation_members SET muted_until = $3
		WHERE conversation_id = $1 AND user_id = $2
	`, conv, user, until)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotMember
	}
	return nil
}

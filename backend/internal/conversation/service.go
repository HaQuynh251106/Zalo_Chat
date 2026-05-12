package conversation

import (
	"context"
	cryptorand "crypto/rand"
	"errors"
	"strings"
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
	IsHidden  bool        `json:"is_hidden"`
	MemberIDs []uuid.UUID `json:"member_ids,omitempty"`
}

type Member struct {
	UserID      uuid.UUID `json:"user_id"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url"`
	Role        string    `json:"role"` // owner | admin | member
	JoinedAt    time.Time `json:"joined_at"`
}

var (
	ErrLastMemberOfDirect = errors.New("cannot leave a direct conversation; delete it instead")
	ErrNotGroup           = errors.New("operation only valid for group conversations")
	ErrForbidden          = errors.New("you don't have permission for this action")
	ErrCannotKickOwner    = errors.New("cannot remove the group owner")
)

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
	return s.listFiltered(ctx, me, false)
}

// ListHiddenForUser returns only conversations the user has previously hidden.
// Caller is responsible for PIN-gating before invoking this.
func (s *Service) ListHiddenForUser(ctx context.Context, me uuid.UUID) ([]Conversation, error) {
	return s.listFiltered(ctx, me, true)
}

func (s *Service) listFiltered(
	ctx context.Context, me uuid.UUID, onlyHidden bool,
) ([]Conversation, error) {
	hideClause := "AND m.hidden_at IS NULL"
	if onlyHidden {
		hideClause = "AND m.hidden_at IS NOT NULL"
	}
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
		       ) AS unread,
		       (m.hidden_at IS NOT NULL) AS is_hidden,
		       COALESCE(
		         (SELECT ARRAY_AGG(cm2.user_id)
		            FROM conversation_members cm2
		           WHERE cm2.conversation_id = c.id),
		         ARRAY[]::uuid[]
		       ) AS member_ids
		FROM conversations c
		JOIN conversation_members m ON m.conversation_id = c.id
		WHERE m.user_id = $1
		  `+hideClause+`
		ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
	`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Conversation, 0)
	for rows.Next() {
		var c Conversation
		if err := rows.Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedAt, &c.LastMsgAt, &c.LastMsg, &c.UnreadCnt, &c.IsHidden, &c.MemberIDs); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Service) getByID(ctx context.Context, me, convID uuid.UUID) (Conversation, error) {
	var c Conversation
	err := s.pool.QueryRow(ctx, `
		SELECT c.id, c.type,
		       COALESCE(c.title,'') AS title,
		       COALESCE(c.avatar_url,'') AS avatar_url,
		       c.created_at, c.last_message_at, COALESCE(c.last_message_preview,''),
		       COALESCE(cm.hidden_at IS NOT NULL, FALSE) AS is_hidden
		FROM conversations c
		LEFT JOIN conversation_members cm
		  ON cm.conversation_id = c.id AND cm.user_id = $2
		WHERE c.id = $1
	`, convID, me).Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedAt, &c.LastMsgAt, &c.LastMsg, &c.IsHidden)
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

// Members returns full member info (joined with users) of a conversation.
// Caller must be a member.
func (s *Service) Members(ctx context.Context, conv, requester uuid.UUID) ([]Member, error) {
	var ok int
	err := s.pool.QueryRow(ctx,
		`SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,
		conv, requester).Scan(&ok)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotMember
	}
	if err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx, `
		SELECT cm.user_id, u.display_name, COALESCE(u.avatar_url,''),
		       cm.role, cm.joined_at
		FROM conversation_members cm
		JOIN users u ON u.id = cm.user_id
		WHERE cm.conversation_id = $1
		ORDER BY
		  CASE cm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
		  cm.joined_at ASC
	`, conv)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Member, 0)
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.UserID, &m.DisplayName, &m.AvatarURL,
			&m.Role, &m.JoinedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// Leave removes the user from a group conversation. Refuses for direct chats.
// If the leaving member is the owner and there are remaining members,
// ownership is transferred to the oldest joined member.
func (s *Service) Leave(ctx context.Context, conv, user uuid.UUID) error {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var ctype, role string
	err = tx.QueryRow(ctx, `
		SELECT c.type, cm.role
		FROM conversations c
		JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $2
		WHERE c.id = $1
	`, conv, user).Scan(&ctype, &role)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotMember
	}
	if err != nil {
		return err
	}
	if ctype == "direct" {
		return ErrLastMemberOfDirect
	}

	// If the leaver is the owner, transfer to oldest other member.
	if role == "owner" {
		var newOwner uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT user_id FROM conversation_members
			WHERE conversation_id=$1 AND user_id <> $2
			ORDER BY joined_at ASC LIMIT 1
		`, conv, user).Scan(&newOwner)
		if err == nil {
			if _, err := tx.Exec(ctx, `
				UPDATE conversation_members SET role='owner'
				WHERE conversation_id=$1 AND user_id=$2
			`, conv, newOwner); err != nil {
				return err
			}
		}
		// If no other member: deletion of conversation is left for a separate
		// cleanup task. We still proceed to remove this user.
	}

	if _, err := tx.Exec(ctx,
		`DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,
		conv, user); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// SetHidden marks a conversation as hidden (or visible) for a single user.
// PIN verification must be performed BEFORE calling this (in the handler).
func (s *Service) SetHidden(
	ctx context.Context, conv, user uuid.UUID, hidden bool,
) error {
	var sql string
	if hidden {
		sql = `UPDATE conversation_members SET hidden_at = NOW()
		       WHERE conversation_id = $1 AND user_id = $2`
	} else {
		sql = `UPDATE conversation_members SET hidden_at = NULL
		       WHERE conversation_id = $1 AND user_id = $2`
	}
	tag, err := s.pool.Exec(ctx, sql, conv, user)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotMember
	}
	return nil
}

// AddMembers adds users to a group. Caller must be owner or admin.
// Returns the list of user IDs actually inserted (skips already-members).
func (s *Service) AddMembers(
	ctx context.Context, conv, actor uuid.UUID, userIDs []uuid.UUID,
) ([]uuid.UUID, error) {
	role, ctype, err := s.roleAndType(ctx, conv, actor)
	if err != nil {
		return nil, err
	}
	if ctype != "group" {
		return nil, ErrNotGroup
	}
	if role != "owner" && role != "admin" {
		return nil, ErrForbidden
	}
	added := make([]uuid.UUID, 0, len(userIDs))
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	for _, uid := range userIDs {
		if uid == actor {
			continue
		}
		tag, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, role)
			VALUES ($1, $2, 'member')
			ON CONFLICT (conversation_id, user_id) DO NOTHING
		`, conv, uid)
		if err != nil {
			return nil, err
		}
		if tag.RowsAffected() > 0 {
			added = append(added, uid)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return added, nil
}

// KickMember removes a user from a group. Caller must be owner or admin.
// Owner cannot be kicked. Admins cannot kick other admins. Use Leave for self.
func (s *Service) KickMember(
	ctx context.Context, conv, actor, target uuid.UUID,
) error {
	if actor == target {
		return errors.New("use leave to remove yourself")
	}
	actorRole, ctype, err := s.roleAndType(ctx, conv, actor)
	if err != nil {
		return err
	}
	if ctype != "group" {
		return ErrNotGroup
	}
	if actorRole != "owner" && actorRole != "admin" {
		return ErrForbidden
	}
	targetRole, _, err := s.roleAndType(ctx, conv, target)
	if err != nil {
		return err
	}
	if targetRole == "owner" {
		return ErrCannotKickOwner
	}
	if actorRole == "admin" && targetRole == "admin" {
		return ErrForbidden
	}
	_, err = s.pool.Exec(ctx,
		`DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,
		conv, target)
	return err
}

// UpdateInfo updates group title and/or avatar. At least one must be provided.
// Caller must be owner or admin.
func (s *Service) UpdateInfo(
	ctx context.Context, conv, actor uuid.UUID, title, avatarURL string,
) error {
	title = strings.TrimSpace(title)
	avatarURL = strings.TrimSpace(avatarURL)
	if title == "" && avatarURL == "" {
		return errors.New("no fields to update")
	}
	if len(title) > 80 {
		return errors.New("title too long")
	}
	role, ctype, err := s.roleAndType(ctx, conv, actor)
	if err != nil {
		return err
	}
	if ctype != "group" {
		return ErrNotGroup
	}
	if role != "owner" && role != "admin" {
		return ErrForbidden
	}
	// COALESCE-style update: nil out empty strings; keep existing values otherwise.
	_, err = s.pool.Exec(ctx, `
		UPDATE conversations
		SET title = COALESCE(NULLIF($2,''), title),
		    avatar_url = COALESCE(NULLIF($3,''), avatar_url)
		WHERE id = $1
	`, conv, title, avatarURL)
	return err
}

// CreateInvite mints a fresh invite token for a group. Caller must be owner/admin.
// Token is a 12-char base32 string, never expires by default.
func (s *Service) CreateInvite(
	ctx context.Context, conv, actor uuid.UUID,
) (token string, err error) {
	role, ctype, err := s.roleAndType(ctx, conv, actor)
	if err != nil {
		return "", err
	}
	if ctype != "group" {
		return "", ErrNotGroup
	}
	if role != "owner" && role != "admin" {
		return "", ErrForbidden
	}
	token = randomToken(12)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO invite_links (token, conversation_id, created_by)
		VALUES ($1, $2, $3)
	`, token, conv, actor)
	return token, err
}

// JoinViaInvite consumes an invite token and adds the caller as a member.
// Returns the conversation id on success.
func (s *Service) JoinViaInvite(
	ctx context.Context, user uuid.UUID, token string,
) (uuid.UUID, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return uuid.Nil, err
	}
	defer tx.Rollback(ctx)

	var (
		conv     uuid.UUID
		expires  *time.Time
		maxUses  *int
		useCount int
		revoked  bool
	)
	err = tx.QueryRow(ctx, `
		SELECT conversation_id, expires_at, max_uses, use_count, revoked
		FROM invite_links WHERE token = $1
		FOR UPDATE
	`, token).Scan(&conv, &expires, &maxUses, &useCount, &revoked)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, errors.New("invite not found")
	}
	if err != nil {
		return uuid.Nil, err
	}
	if revoked {
		return uuid.Nil, errors.New("invite revoked")
	}
	if expires != nil && time.Now().After(*expires) {
		return uuid.Nil, errors.New("invite expired")
	}
	if maxUses != nil && useCount >= *maxUses {
		return uuid.Nil, errors.New("invite already used up")
	}

	// Insert member if not yet a member.
	tag, err := tx.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (conversation_id, user_id) DO NOTHING
	`, conv, user)
	if err != nil {
		return uuid.Nil, err
	}
	// Increment counter only on real insert.
	if tag.RowsAffected() > 0 {
		if _, err := tx.Exec(ctx,
			`UPDATE invite_links SET use_count = use_count + 1 WHERE token=$1`, token); err != nil {
			return uuid.Nil, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return uuid.Nil, err
	}
	return conv, nil
}

func randomToken(n int) string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = alphabet[secureRandomInt(len(alphabet))]
	}
	return string(b)
}

func secureRandomInt(max int) int {
	var b [4]byte
	if _, err := cryptorand.Read(b[:]); err != nil {
		// fallback to time-based (extremely unlikely path)
		return int(time.Now().UnixNano()) % max
	}
	v := int(b[0])<<24 | int(b[1])<<16 | int(b[2])<<8 | int(b[3])
	if v < 0 {
		v = -v
	}
	return v % max
}

// roleAndType returns the user's role and the conversation type.
func (s *Service) roleAndType(
	ctx context.Context, conv, user uuid.UUID,
) (role string, ctype string, err error) {
	err = s.pool.QueryRow(ctx, `
		SELECT cm.role, c.type
		FROM conversations c
		JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id=$2
		WHERE c.id=$1
	`, conv, user).Scan(&role, &ctype)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", ErrNotMember
	}
	return role, ctype, err
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

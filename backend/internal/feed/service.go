package feed

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Post struct {
	ID            uuid.UUID `json:"id"`
	AuthorID      uuid.UUID `json:"author_id"`
	AuthorName    string    `json:"author_name"`
	AuthorAvatar  string    `json:"author_avatar"`
	Body          string    `json:"body"`
	Media         []string  `json:"media"`
	Visibility    string    `json:"visibility"`
	CreatedAt     time.Time `json:"created_at"`
	ReactionCount int       `json:"reaction_count"`
	CommentCount  int       `json:"comment_count"`
	MyReaction    string    `json:"my_reaction,omitempty"`
}

type Comment struct {
	ID         uuid.UUID `json:"id"`
	PostID     uuid.UUID `json:"post_id"`
	UserID     uuid.UUID `json:"user_id"`
	UserName   string    `json:"user_name"`
	UserAvatar string    `json:"user_avatar"`
	Body       string    `json:"body"`
	CreatedAt  time.Time `json:"created_at"`
}

var (
	ErrPostNotFound = errors.New("post not found")
	ErrForbidden    = errors.New("not allowed to view this post")
)

type Service struct{ pool *pgxpool.Pool }

func NewService(pool *pgxpool.Pool) *Service { return &Service{pool: pool} }

func (s *Service) Create(ctx context.Context, author uuid.UUID, body string, media []string, visibility string) (Post, error) {
	if visibility == "" {
		visibility = "friends"
	}
	if visibility != "public" && visibility != "friends" && visibility != "private" {
		return Post{}, errors.New("invalid visibility")
	}
	mediaJSON, err := json.Marshal(media)
	if err != nil {
		return Post{}, err
	}
	var id uuid.UUID
	var createdAt time.Time
	err = s.pool.QueryRow(ctx, `
		INSERT INTO feed_posts (user_id, body, media, visibility)
		VALUES ($1, $2, $3::jsonb, $4)
		RETURNING id, created_at
	`, author, body, string(mediaJSON), visibility).Scan(&id, &createdAt)
	if err != nil {
		return Post{}, err
	}
	return s.Get(ctx, id, author)
}

func (s *Service) Get(ctx context.Context, postID, viewer uuid.UUID) (Post, error) {
	row := s.pool.QueryRow(ctx, `
		SELECT p.id, p.user_id, u.display_name, COALESCE(u.avatar_url,''),
		       COALESCE(p.body,''), p.media::text, p.visibility, p.created_at,
		       (SELECT COUNT(*) FROM feed_reactions WHERE post_id = p.id),
		       (SELECT COUNT(*) FROM feed_comments  WHERE post_id = p.id),
		       COALESCE((SELECT reaction FROM feed_reactions WHERE post_id = p.id AND user_id = $2), '')
		FROM feed_posts p
		JOIN users u ON u.id = p.user_id
		WHERE p.id = $1
	`, postID, viewer)
	var p Post
	var mediaRaw string
	if err := row.Scan(&p.ID, &p.AuthorID, &p.AuthorName, &p.AuthorAvatar,
		&p.Body, &mediaRaw, &p.Visibility, &p.CreatedAt,
		&p.ReactionCount, &p.CommentCount, &p.MyReaction); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Post{}, ErrPostNotFound
		}
		return Post{}, err
	}
	_ = json.Unmarshal([]byte(mediaRaw), &p.Media)
	if !s.canView(ctx, p, viewer) {
		return Post{}, ErrForbidden
	}
	return p, nil
}

// Timeline: own posts + friends' posts (friends|public).
func (s *Service) Timeline(ctx context.Context, viewer uuid.UUID, limit int, before *time.Time) ([]Post, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	args := []any{viewer, limit}
	q := `
		SELECT p.id, p.user_id, u.display_name, COALESCE(u.avatar_url,''),
		       COALESCE(p.body,''), p.media::text, p.visibility, p.created_at,
		       (SELECT COUNT(*) FROM feed_reactions WHERE post_id = p.id),
		       (SELECT COUNT(*) FROM feed_comments  WHERE post_id = p.id),
		       COALESCE((SELECT reaction FROM feed_reactions WHERE post_id = p.id AND user_id = $1), '')
		FROM feed_posts p
		JOIN users u ON u.id = p.user_id
		WHERE
		    -- mình
		    p.user_id = $1
		    OR
		    -- public của bất kỳ ai
		    p.visibility = 'public'
		    OR
		    -- bạn bè (friendships accepted) HOẶC có chung conversation (Telegram-style: chat = contact)
		    (p.visibility = 'friends' AND (
		        EXISTS (
		            SELECT 1 FROM friendships f
		            WHERE f.status = 'accepted'
		              AND ((f.user_low = $1 AND f.user_high = p.user_id)
		                OR (f.user_high = $1 AND f.user_low = p.user_id))
		        )
		        OR EXISTS (
		            SELECT 1 FROM conversation_members cm1
		            JOIN conversation_members cm2 ON cm2.conversation_id = cm1.conversation_id
		            WHERE cm1.user_id = $1 AND cm2.user_id = p.user_id
		        )
		    ))
	`
	if before != nil {
		q += " AND p.created_at < $3"
		args = append(args, *before)
	}
	q += " ORDER BY p.created_at DESC LIMIT $2"

	rows, err := s.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Post, 0, limit)
	for rows.Next() {
		var p Post
		var mediaRaw string
		if err := rows.Scan(&p.ID, &p.AuthorID, &p.AuthorName, &p.AuthorAvatar,
			&p.Body, &mediaRaw, &p.Visibility, &p.CreatedAt,
			&p.ReactionCount, &p.CommentCount, &p.MyReaction); err != nil {
			return nil, err
		}
		_ = json.Unmarshal([]byte(mediaRaw), &p.Media)
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Service) React(ctx context.Context, postID, user uuid.UUID, reaction string) error {
	if reaction == "" {
		_, err := s.pool.Exec(ctx, `DELETE FROM feed_reactions WHERE post_id=$1 AND user_id=$2`, postID, user)
		return err
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO feed_reactions (post_id, user_id, reaction)
		VALUES ($1, $2, $3)
		ON CONFLICT (post_id, user_id) DO UPDATE SET reaction = EXCLUDED.reaction
	`, postID, user, reaction)
	return err
}

func (s *Service) AddComment(ctx context.Context, postID, user uuid.UUID, body string) (Comment, error) {
	if body == "" {
		return Comment{}, errors.New("empty comment")
	}
	var c Comment
	err := s.pool.QueryRow(ctx, `
		WITH inserted AS (
		    INSERT INTO feed_comments (post_id, user_id, body)
		    VALUES ($1, $2, $3)
		    RETURNING id, post_id, user_id, body, created_at
		)
		SELECT i.id, i.post_id, i.user_id, u.display_name, COALESCE(u.avatar_url,''), i.body, i.created_at
		FROM inserted i JOIN users u ON u.id = i.user_id
	`, postID, user, body).Scan(&c.ID, &c.PostID, &c.UserID, &c.UserName, &c.UserAvatar, &c.Body, &c.CreatedAt)
	return c, err
}

func (s *Service) ListComments(ctx context.Context, postID uuid.UUID) ([]Comment, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id, c.post_id, c.user_id, u.display_name, COALESCE(u.avatar_url,''), c.body, c.created_at
		FROM feed_comments c JOIN users u ON u.id = c.user_id
		WHERE c.post_id = $1
		ORDER BY c.created_at ASC
	`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Comment, 0)
	for rows.Next() {
		var c Comment
		if err := rows.Scan(&c.ID, &c.PostID, &c.UserID, &c.UserName, &c.UserAvatar, &c.Body, &c.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Service) canView(ctx context.Context, p Post, viewer uuid.UUID) bool {
	if p.AuthorID == viewer || p.Visibility == "public" {
		return true
	}
	if p.Visibility == "private" {
		return false
	}
	// friends: accepted friendship OR shared conversation
	var n int
	err := s.pool.QueryRow(ctx, `
		SELECT 1
		WHERE EXISTS (
		    SELECT 1 FROM friendships
		    WHERE status='accepted'
		      AND ((user_low=$1 AND user_high=$2) OR (user_high=$1 AND user_low=$2))
		)
		OR EXISTS (
		    SELECT 1 FROM conversation_members cm1
		    JOIN conversation_members cm2 ON cm2.conversation_id = cm1.conversation_id
		    WHERE cm1.user_id = $1 AND cm2.user_id = $2
		)
	`, viewer, p.AuthorID).Scan(&n)
	return err == nil
}

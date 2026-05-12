// Seed program — populates the database with realistic Vietnamese demo data.
// Idempotent: re-running is a no-op for already-seeded rows.
// SECURITY: demo-only. Refuses to run if APP_ENV=production.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"golang.org/x/crypto/bcrypt"
)

type seedUser struct {
	Phone string
	Name  string
}

var users = []seedUser{
	{"0911000001", "Alice Nguyễn"},
	{"0911000002", "Bảo Trần"},
	{"0911000003", "Châu Lê"},
	{"0911000004", "Đào Phạm"},
	{"0911000005", "Em Hoàng"},
	{"0911000006", "Phúc Võ"},
}

// Direct conversation message scripts (Vietnamese)
var directScripts = [][]string{
	// Alice <-> Bảo
	{
		"Hôm nay đi cà phê không?",
		"Có chứ, 3h chiều ở The Coffee House nhé",
		"Ok, đặt bàn trước cho mình nha",
		"Đã đặt rồi, bàn 2 cạnh cửa sổ",
		"Tuyệt, gặp lát nữa!",
		"😊",
	},
	// Alice <-> Châu
	{
		"Châu ơi tài liệu thuyết trình xong chưa?",
		"Mình xong slide rồi, gửi tối nay nha",
		"Ok cảm ơn bạn, mai 9h chốt nhé",
		"Yên tâm, không trễ đâu",
	},
	// Alice <-> Đào
	{
		"Cuối tuần đi biển không?",
		"Đi đâu vậy?",
		"Vũng Tàu, mình rủ thêm 4-5 đứa",
		"Nghe hay đó, đi luôn!",
		"Mình sẽ làm group sau, hold space cuối tuần nhé",
	},
}

var groupName = "Team Lumo 🚀"
var groupMessages = []string{
	"Chào team, tuần này họp sprint vào thứ 6 lúc 10h nhé",
	"Có agenda gì chưa anh?",
	"Mình sẽ gửi trước 1 ngày",
	"Em sẽ chuẩn bị phần demo backend",
	"Tốt quá, em cũng làm slide UI",
	"Anyway hôm nay deploy thành công rồi đó các bạn 🎉",
	"Yayyy 🥳",
}

func main() {
	_ = godotenv.Load()

	if os.Getenv("APP_ENV") == "production" {
		log.Fatal("[seed] refusing to run in production")
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://zalo:zalo@localhost:5432/zalo?sslmode=disable"
	}
	password := os.Getenv("SEED_PASSWORD")
	if password == "" {
		password = "demo1234"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("pg: %v", err)
	}
	defer pool.Close()

	// Pre-hash once (cost=4 for speed; demo only).
	hashBytes, err := bcrypt.GenerateFromPassword([]byte(password), 4)
	if err != nil {
		log.Fatalf("bcrypt: %v", err)
	}
	hash := string(hashBytes)

	// Step 1 — users
	ids := make(map[string]uuid.UUID, len(users))
	for _, u := range users {
		var id uuid.UUID
		err := pool.QueryRow(ctx, `
			INSERT INTO users (phone, password_hash, display_name)
			VALUES ($1, $2, $3)
			ON CONFLICT (phone) DO UPDATE SET display_name = users.display_name
			RETURNING id
		`, u.Phone, hash, u.Name).Scan(&id)
		if err != nil {
			log.Fatalf("upsert user %s: %v", u.Phone, err)
		}
		ids[u.Phone] = id
	}
	log.Printf("[seed] users: %d", len(ids))

	alice := ids["0911000001"]

	// Step 2 — direct conversations Alice <-> {Bảo, Châu, Đào}
	directPeers := []string{"0911000002", "0911000003", "0911000004"}
	directConvs := make([]uuid.UUID, 0, len(directPeers))
	for i, peerPhone := range directPeers {
		peer := ids[peerPhone]
		convID, err := ensureDirect(ctx, pool, alice, peer)
		if err != nil {
			log.Fatalf("direct %s: %v", peerPhone, err)
		}
		directConvs = append(directConvs, convID)

		// Friendship (auto-friend on direct chat). Insert if absent.
		if err := ensureFriendship(ctx, pool, alice, peer); err != nil {
			log.Fatalf("friendship: %v", err)
		}

		// Seed messages alternating Alice/peer.
		if i < len(directScripts) {
			if err := ensureMessages(ctx, pool, convID, []uuid.UUID{alice, peer}, directScripts[i]); err != nil {
				log.Fatalf("messages: %v", err)
			}
		}
	}
	log.Printf("[seed] direct conversations: %d", len(directConvs))

	// Step 3 — group conversation Alice + Bảo + Châu + Đào + Em
	groupMembers := []uuid.UUID{
		alice,
		ids["0911000002"],
		ids["0911000003"],
		ids["0911000004"],
		ids["0911000005"],
	}
	groupID, err := ensureGroup(ctx, pool, groupName, alice, groupMembers)
	if err != nil {
		log.Fatalf("group: %v", err)
	}
	if err := ensureMessages(ctx, pool, groupID, groupMembers, groupMessages); err != nil {
		log.Fatalf("group messages: %v", err)
	}
	log.Printf("[seed] group %q ok", groupName)

	// Step 4 — pending friend request: Phúc (id 06) -> Alice (incoming)
	if err := ensurePendingRequest(ctx, pool, ids["0911000006"], alice); err != nil {
		log.Fatalf("pending: %v", err)
	}
	log.Printf("[seed] pending friend request: Phúc -> Alice")

	// Step 5 — a friends-only post by Bảo so Alice sees it in her feed
	if err := ensureFeedPost(ctx, pool, ids["0911000002"], "Cuối tuần này có ai đi Vũng Tàu không? 🌊"); err != nil {
		log.Fatalf("feed post: %v", err)
	}
	log.Printf("[seed] feed post seeded")

	log.Println("[seed] done. Login as 0911000001 / " + password + " to see all demo data.")
}

func ensureDirect(ctx context.Context, pool *pgxpool.Pool, a, b uuid.UUID) (uuid.UUID, error) {
	var id uuid.UUID
	err := pool.QueryRow(ctx, `
		SELECT c.id
		FROM conversations c
		JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1
		JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2
		WHERE c.type = 'direct'
		LIMIT 1
	`, a, b).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, err
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	defer tx.Rollback(ctx)
	if err := tx.QueryRow(ctx, `
		INSERT INTO conversations (type, created_by) VALUES ('direct', $1) RETURNING id
	`, a).Scan(&id); err != nil {
		return uuid.Nil, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id, role)
		VALUES ($1,$2,'member'),($1,$3,'member')
	`, id, a, b); err != nil {
		return uuid.Nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return uuid.Nil, err
	}
	return id, nil
}

func ensureGroup(ctx context.Context, pool *pgxpool.Pool, title string, creator uuid.UUID, members []uuid.UUID) (uuid.UUID, error) {
	var id uuid.UUID
	err := pool.QueryRow(ctx, `
		SELECT id FROM conversations WHERE type='group' AND title=$1 LIMIT 1
	`, title).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, err
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	defer tx.Rollback(ctx)
	if err := tx.QueryRow(ctx, `
		INSERT INTO conversations (type, title, created_by) VALUES ('group',$1,$2) RETURNING id
	`, title, creator).Scan(&id); err != nil {
		return uuid.Nil, err
	}
	for i, m := range members {
		role := "member"
		if i == 0 {
			role = "owner"
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, role)
			VALUES ($1,$2,$3) ON CONFLICT DO NOTHING
		`, id, m, role); err != nil {
			return uuid.Nil, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return uuid.Nil, err
	}
	return id, nil
}

func ensureFriendship(ctx context.Context, pool *pgxpool.Pool, a, b uuid.UUID) error {
	low, high := a, b
	if low.String() > high.String() {
		low, high = high, low
	}
	_, err := pool.Exec(ctx, `
		INSERT INTO friendships (user_low, user_high, requested_by, status, accepted_at)
		VALUES ($1,$2,$3,'accepted',NOW())
		ON CONFLICT (user_low, user_high) DO UPDATE SET status='accepted'
	`, low, high, a)
	return err
}

func ensurePendingRequest(ctx context.Context, pool *pgxpool.Pool, requester, target uuid.UUID) error {
	low, high := requester, target
	if low.String() > high.String() {
		low, high = high, low
	}
	_, err := pool.Exec(ctx, `
		INSERT INTO friendships (user_low, user_high, requested_by, status)
		VALUES ($1,$2,$3,'pending')
		ON CONFLICT (user_low, user_high) DO NOTHING
	`, low, high, requester)
	return err
}

func ensureMessages(ctx context.Context, pool *pgxpool.Pool, conv uuid.UUID, senders []uuid.UUID, bodies []string) error {
	// Skip if conversation already has any messages.
	var existing int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM messages WHERE conversation_id=$1`, conv).Scan(&existing); err != nil {
		return err
	}
	if existing > 0 {
		return nil
	}

	base := time.Now().Add(-time.Duration(len(bodies)) * 2 * time.Minute)
	var lastTime time.Time
	var lastBody string
	for i, body := range bodies {
		sender := senders[i%len(senders)]
		ts := base.Add(time.Duration(i) * 2 * time.Minute)
		if _, err := pool.Exec(ctx, `
			INSERT INTO messages (conversation_id, sender_id, type, body, created_at)
			VALUES ($1, $2, 'text', $3, $4)
		`, conv, sender, body, ts); err != nil {
			return err
		}
		lastTime = ts
		lastBody = body
	}
	_, err := pool.Exec(ctx, `
		UPDATE conversations SET last_message_at=$2, last_message_preview=$3 WHERE id=$1
	`, conv, lastTime, lastBody)
	return err
}

func ensureFeedPost(ctx context.Context, pool *pgxpool.Pool, author uuid.UUID, body string) error {
	var count int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM feed_posts WHERE user_id=$1 AND body=$2`, author, body).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil
	}
	_, err := pool.Exec(ctx, `
		INSERT INTO feed_posts (user_id, body, visibility) VALUES ($1, $2, 'friends')
	`, author, body)
	return err
}

// unused but reserved for richer seed runs
var _ = fmt.Sprintf

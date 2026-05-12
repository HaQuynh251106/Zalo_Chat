package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/db"
)

func main() {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		databaseURL = "postgres://zalo:zalo@localhost:5432/zalo?sslmode=disable"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	pool, err := db.NewPostgres(ctx, databaseURL)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer pool.Close()

	summary, err := db.ApplyMigrations(ctx, pool, "./migrations")
	if err != nil {
		log.Fatalf("migrations: %v", err)
	}
	log.Printf("[migrate] done: applied=%d skipped=%d", summary.Applied, summary.Skipped)
}

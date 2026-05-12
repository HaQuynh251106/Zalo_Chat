package db

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

func NewPostgres(ctx context.Context, url string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("parse pg url: %w", err)
	}
	cfg.MaxConns = 20
	cfg.MinConns = 2
	cfg.MaxConnLifetime = time.Hour

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("connect pg: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		return nil, fmt.Errorf("ping pg: %w", err)
	}
	return pool, nil
}

func NewRedis(ctx context.Context, addr, password string, dbIdx int) (*redis.Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       dbIdx,
	})
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := rdb.Ping(pingCtx).Err(); err != nil {
		return nil, fmt.Errorf("ping redis: %w", err)
	}
	return rdb, nil
}

type MigrationSummary struct {
	Applied int
	Skipped int
}

func ApplyMigrations(ctx context.Context, pool *pgxpool.Pool, dir string) (MigrationSummary, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return MigrationSummary{}, fmt.Errorf("read migrations dir %s: %w", dir, err)
	}

	files := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}
		files = append(files, entry.Name())
	}
	sort.Strings(files)

	var summary MigrationSummary
	for _, filename := range files {
		body, err := os.ReadFile(filepath.Join(dir, filename))
		if err != nil {
			return summary, fmt.Errorf("read migration %s: %w", filename, err)
		}
		checksum := checksum(body)

		var applied bool
		if filename == "000_schema_migrations.sql" {
			applied, err = applyLedgerMigration(ctx, pool, filename, checksum, string(body))
		} else {
			applied, err = applyMigration(ctx, pool, filename, checksum, string(body))
		}
		if err != nil {
			return summary, err
		}
		if applied {
			summary.Applied++
		} else {
			summary.Skipped++
		}
	}
	return summary, nil
}

func applyLedgerMigration(ctx context.Context, pool *pgxpool.Pool, filename, checksum, sql string) (bool, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin migration %s: %w", filename, err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, sql); err != nil {
		return false, fmt.Errorf("apply migration %s: %w", filename, err)
	}
	applied, err := checkApplied(ctx, tx, filename, checksum)
	if err != nil {
		return false, err
	}
	if applied {
		if err := tx.Commit(ctx); err != nil {
			return false, fmt.Errorf("commit migration %s: %w", filename, err)
		}
		log.Printf("[migrate] skip (already applied): %s", filename)
		return false, nil
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)
	`, filename, checksum); err != nil {
		return false, fmt.Errorf("record migration %s: %w", filename, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit migration %s: %w", filename, err)
	}
	log.Printf("[migrate] applied: %s", filename)
	return true, nil
}

func applyMigration(ctx context.Context, pool *pgxpool.Pool, filename, checksum, sql string) (bool, error) {
	applied, err := migrationApplied(ctx, pool, filename, checksum)
	if err != nil {
		return false, err
	}
	if applied {
		log.Printf("[migrate] skip (already applied): %s", filename)
		return false, nil
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin migration %s: %w", filename, err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, sql); err != nil {
		return false, fmt.Errorf("apply migration %s: %w", filename, err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)
	`, filename, checksum); err != nil {
		return false, fmt.Errorf("record migration %s: %w", filename, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit migration %s: %w", filename, err)
	}
	log.Printf("[migrate] applied: %s", filename)
	return true, nil
}

type checksumQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func migrationApplied(ctx context.Context, pool *pgxpool.Pool, filename, checksum string) (bool, error) {
	return checkApplied(ctx, pool, filename, checksum)
}

func checkApplied(ctx context.Context, q checksumQuerier, filename, checksum string) (bool, error) {
	var existing string
	err := q.QueryRow(ctx, `
		SELECT checksum FROM schema_migrations WHERE filename=$1
	`, filename).Scan(&existing)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("check migration %s: %w", filename, err)
	}
	if existing != checksum {
		return false, fmt.Errorf("migration %s already applied with different content", filename)
	}
	return true, nil
}

func checksum(body []byte) string {
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:])
}

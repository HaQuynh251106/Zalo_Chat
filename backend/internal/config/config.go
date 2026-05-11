package config

import (
	"os"
	"strconv"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	HTTPAddr       string
	DatabaseURL    string
	RedisAddr      string
	RedisPassword  string
	RedisDB        int
	JWTSecret      string
	JWTAccessTTL   time.Duration
	JWTRefreshTTL  time.Duration
	AllowedOrigins []string
	WSWriteTimeout time.Duration
	WSPongWait     time.Duration
	UploadDir      string
	PublicBaseURL  string
}

func Load() *Config {
	_ = godotenv.Load()

	return &Config{
		HTTPAddr:       getenv("HTTP_ADDR", ":8080"),
		DatabaseURL:    getenv("DATABASE_URL", "postgres://zalo:zalo@localhost:5432/zalo?sslmode=disable"),
		RedisAddr:      getenv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:  getenv("REDIS_PASSWORD", ""),
		RedisDB:        getenvInt("REDIS_DB", 0),
		JWTSecret:      getenv("JWT_SECRET", "change-me-in-production"),
		JWTAccessTTL:   getenvDuration("JWT_ACCESS_TTL", 24*time.Hour),
		JWTRefreshTTL:  getenvDuration("JWT_REFRESH_TTL", 30*24*time.Hour),
		AllowedOrigins: []string{getenv("ALLOWED_ORIGINS", "*")},
		WSWriteTimeout: 10 * time.Second,
		WSPongWait:     60 * time.Second,
		UploadDir:      getenv("UPLOAD_DIR", "./uploads"),
		PublicBaseURL:  getenv("PUBLIC_BASE_URL", ""),
	}
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	if v, ok := os.LookupEnv(key); ok {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func getenvDuration(key string, fallback time.Duration) time.Duration {
	if v, ok := os.LookupEnv(key); ok {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}

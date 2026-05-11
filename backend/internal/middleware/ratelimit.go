package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"golang.org/x/time/rate"
)

type IPRateLimiter struct {
	mu       sync.Mutex
	limiters map[string]*rate.Limiter
	seen     map[string]time.Time
	rate     rate.Limit
	burst    int
}

func NewIPRateLimiter(eventsPerSecond rate.Limit, burst int) *IPRateLimiter {
	l := &IPRateLimiter{
		limiters: make(map[string]*rate.Limiter),
		seen:     make(map[string]time.Time),
		rate:     eventsPerSecond,
		burst:    burst,
	}
	go l.cleanup()
	return l
}

func (l *IPRateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		limiter := l.forIP(clientIP(r))
		if !limiter.Allow() {
			httpx.Error(w, http.StatusTooManyRequests, "too many requests")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (l *IPRateLimiter) forIP(ip string) *rate.Limiter {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	limiter, ok := l.limiters[ip]
	if !ok {
		limiter = rate.NewLimiter(l.rate, l.burst)
		l.limiters[ip] = limiter
	}
	l.seen[ip] = now
	return limiter
}

func (l *IPRateLimiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		l.mu.Lock()
		cutoff := time.Now().Add(-10 * time.Minute)
		for ip, seenAt := range l.seen {
			if seenAt.Before(cutoff) {
				delete(l.seen, ip)
				delete(l.limiters, ip)
			}
		}
		l.mu.Unlock()
	}
}

func clientIP(r *http.Request) string {
	if h := r.Header.Get("X-Forwarded-For"); h != "" {
		return strings.TrimSpace(strings.Split(h, ",")[0])
	}
	if h := r.Header.Get("X-Real-IP"); h != "" {
		return strings.TrimSpace(h)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

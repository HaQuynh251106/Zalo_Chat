package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/auth"
	"github.com/a1234/zalo-clone/backend/internal/call"
	"github.com/a1234/zalo-clone/backend/internal/config"
	"github.com/a1234/zalo-clone/backend/internal/contact"
	"github.com/a1234/zalo-clone/backend/internal/conversation"
	"github.com/a1234/zalo-clone/backend/internal/db"
	"github.com/a1234/zalo-clone/backend/internal/feed"
	"github.com/a1234/zalo-clone/backend/internal/media"
	"github.com/a1234/zalo-clone/backend/internal/message"
	"github.com/a1234/zalo-clone/backend/internal/reaction"
	"github.com/a1234/zalo-clone/backend/internal/router"
	"github.com/a1234/zalo-clone/backend/internal/session"
	"github.com/a1234/zalo-clone/backend/internal/user"
	"github.com/a1234/zalo-clone/backend/internal/wallet"
	"github.com/a1234/zalo-clone/backend/internal/ws"
)

func main() {
	cfg := config.Load()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := db.NewPostgres(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer pool.Close()

	migrations, err := db.ApplyMigrations(ctx, pool, "./migrations")
	if err != nil {
		log.Fatalf("migrations: %v", err)
	}
	log.Printf("[migrate] done: applied=%d skipped=%d", migrations.Applied, migrations.Skipped)

	rdb, err := db.NewRedis(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	if err != nil {
		log.Printf("[warn] redis unavailable: %v (continuing without presence cache)", err)
	} else {
		defer rdb.Close()
	}

	issuer := auth.NewIssuer(cfg.JWTSecret, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)

	authSvc := auth.NewService(pool, issuer)
	userSvc := user.NewService(pool)
	contactSvc := contact.NewService(pool)
	convSvc := conversation.NewService(pool)
	msgSvc := message.NewService(pool)
	feedSvc := feed.NewService(pool)
	callSvc := call.NewService(pool)
	reactionSvc := reaction.NewService(pool)
	walletSvc := wallet.NewService(pool, msgSvc)

	hub := ws.NewHub(pool, rdb)

	mediaH, err := media.NewHandler(cfg.UploadDir, cfg.PublicBaseURL)
	if err != nil {
		log.Fatalf("media handler: %v", err)
	}

	r := router.New(router.Deps{
		Issuer:      issuer,
		AuthH:       auth.NewHandler(authSvc),
		SessionH:    session.NewHandler(authSvc),
		UserH:       user.NewHandler(userSvc),
		ContactH:    contact.NewHandler(contactSvc, hub),
		ConvH:       conversation.NewHandler(convSvc, hub, userSvc.VerifyHidePin),
		MsgH:        message.NewHandler(msgSvc, hub),
		FeedH:       feed.NewHandler(feedSvc),
		MediaH:      mediaH,
		CallH:       call.NewHandler(callSvc, hub),
		ReactionH:   reaction.NewHandler(reactionSvc, hub),
		WalletH:     wallet.NewHandler(walletSvc, hub),
		WSH:         ws.NewHandler(hub, cfg.WSWriteTimeout, cfg.WSPongWait),
		AllowedOrgs: cfg.AllowedOrigins,
	})

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("[server] listening on %s", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("http: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("[server] shutting down...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
		os.Exit(1)
	}
}

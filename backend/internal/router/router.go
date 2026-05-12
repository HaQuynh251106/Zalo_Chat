package router

import (
	"net/http"
	"time"

	"github.com/a1234/zalo-clone/backend/internal/auth"
	"github.com/a1234/zalo-clone/backend/internal/call"
	"github.com/a1234/zalo-clone/backend/internal/contact"
	"github.com/a1234/zalo-clone/backend/internal/conversation"
	"github.com/a1234/zalo-clone/backend/internal/feed"
	"github.com/a1234/zalo-clone/backend/internal/httpx"
	"github.com/a1234/zalo-clone/backend/internal/media"
	"github.com/a1234/zalo-clone/backend/internal/message"
	"github.com/a1234/zalo-clone/backend/internal/middleware"
	"github.com/a1234/zalo-clone/backend/internal/reaction"
	"github.com/a1234/zalo-clone/backend/internal/session"
	"github.com/a1234/zalo-clone/backend/internal/user"
	"github.com/a1234/zalo-clone/backend/internal/wallet"
	"github.com/a1234/zalo-clone/backend/internal/ws"
	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"golang.org/x/time/rate"
)

type Deps struct {
	Issuer      *auth.TokenIssuer
	AuthH       *auth.Handler
	SessionH    *session.Handler
	UserH       *user.Handler
	ContactH    *contact.Handler
	ConvH       *conversation.Handler
	MsgH        *message.Handler
	FeedH       *feed.Handler
	MediaH      *media.Handler
	CallH       *call.Handler
	ReactionH   *reaction.Handler
	WalletH     *wallet.Handler
	WSH         *ws.Handler
	AllowedOrgs []string
}

func New(d Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(middleware.SecurityHeaders)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   d.AllowedOrgs,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Static serve uploaded media (public).
	if d.MediaH != nil {
		r.Handle("/static/*", d.MediaH.Static())
	}

	r.Route("/api/v1", func(r chi.Router) {
		authLimiter := middleware.NewIPRateLimiter(rate.Every(2*time.Second), 5)
		// Public
		r.With(authLimiter.Middleware).Post("/auth/register", d.AuthH.Register)
		r.With(authLimiter.Middleware).Post("/auth/login", d.AuthH.Login)
		r.With(authLimiter.Middleware).Post("/auth/refresh", d.AuthH.Refresh)

		// Protected
		r.Group(func(r chi.Router) {
			r.Use(middleware.RequireAuth(d.Issuer))

			r.Get("/me", d.UserH.Me)
			r.Put("/me", d.UserH.UpdateMe)
			r.Put("/me/push-token", d.UserH.UpdatePushToken)
			r.Get("/me/hide-pin", d.UserH.HidePinStatus)
			r.Post("/me/hide-pin", d.UserH.SetHidePin)
			r.Post("/me/hide-pin/verify", d.UserH.VerifyHidePin)
			r.Get("/me/devices", d.SessionH.ListDevices)
			r.Delete("/me/devices", d.SessionH.LogoutAllDevices)
			r.Delete("/me/devices/{deviceID}", d.SessionH.LogoutDevice)
			r.Get("/users/search", d.UserH.SearchByPhone)
			r.Post("/auth/logout", d.SessionH.LogoutCurrent)

			r.Get("/contacts", d.ContactH.List)
			r.Post("/contacts/request", d.ContactH.Request)
			r.Post("/contacts/accept", d.ContactH.Accept)
			r.Post("/contacts/cancel", d.ContactH.Cancel)

			r.Get("/conversations", d.ConvH.List)
			r.Post("/conversations/direct", d.ConvH.OpenDirect)
			r.Post("/conversations/group", d.ConvH.CreateGroup)
			r.Post("/conversations/{id}/read", d.ConvH.MarkRead)
			r.Get("/conversations/{id}/members", d.ConvH.Members)
			r.Post("/conversations/{id}/members", d.ConvH.AddMembers)
			r.Delete("/conversations/{id}/members/{userID}", d.ConvH.KickMember)
			r.Patch("/conversations/{id}", d.ConvH.UpdateInfo)
			r.Post("/conversations/{id}/leave", d.ConvH.Leave)
			r.Post("/conversations/{id}/invite", d.ConvH.CreateInvite)
			r.Post("/conversations/join", d.ConvH.JoinViaInvite)
			r.Post("/conversations/{id}/hide", d.ConvH.Hide)
			r.Post("/conversations/{id}/unhide", d.ConvH.Unhide)
			r.Post("/conversations/hidden", d.ConvH.ListHidden)

			r.Get("/conversations/{id}/messages", d.MsgH.List)
			r.Post("/conversations/{id}/messages", d.MsgH.Send)
			r.Post("/conversations/{id}/mute", d.ConvH.SetMute)
			r.Post("/messages/{msgID}/recall", d.MsgH.Recall)
			r.Post("/messages/{msgID}/reactions", d.ReactionH.Set)
			r.Post("/messages/{msgID}/pin", d.MsgH.Pin)
			r.Post("/messages/{msgID}/unpin", d.MsgH.Unpin)
			r.Post("/messages/{msgID}/hide", d.MsgH.HideForMe)
			r.Get("/conversations/{id}/pinned", d.MsgH.ListPinned)

			// Feed (Nhật ký)
			r.Get("/feed", d.FeedH.Timeline)
			r.Post("/feed", d.FeedH.Create)
			r.Get("/feed/{id}", d.FeedH.Get)
			r.Post("/feed/{id}/react", d.FeedH.React)
			r.Get("/feed/{id}/comments", d.FeedH.ListComments)
			r.Post("/feed/{id}/comments", d.FeedH.AddComment)

			// Media upload
			r.Post("/upload", d.MediaH.Upload)

			// Call signaling
			r.Post("/calls", d.CallH.Initiate)
			r.Get("/calls/recent", d.CallH.Recent)
			r.Post("/calls/{id}/accept", d.CallH.Accept)
			r.Post("/calls/{id}/reject", d.CallH.Reject)
			r.Post("/calls/{id}/end", d.CallH.End)
			r.Post("/calls/{id}/signal", d.CallH.Signal)

			// Wallet
			r.Get("/wallet/me", d.WalletH.Me)
			r.Get("/wallet/transactions", d.WalletH.History)
			r.Post("/wallet/topup", d.WalletH.Topup)
			r.Post("/wallet/transfer", d.WalletH.Transfer)
			r.Post("/wallet/red-pocket/{msgID}/open", d.WalletH.OpenRedPocket)

			r.Get("/ws", d.WSH.ServeHTTP)
		})
	})

	return r
}

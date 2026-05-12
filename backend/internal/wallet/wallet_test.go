package wallet

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
)

func TestTopupRejectsInvalidAmountsBeforeDB(t *testing.T) {
	svc := NewService(nil, nil)

	tests := []struct {
		name   string
		amount int64
		want   error
	}{
		{name: "zero", amount: 0, want: ErrInvalidAmount},
		{name: "below minimum", amount: MinTopupCents - 1, want: ErrAmountTooSmall},
		{name: "above maximum", amount: MaxTopupCents + 1, want: ErrAmountTooLarge},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.Topup(context.Background(), uuid.New(), tc.amount)
			if !errors.Is(err, tc.want) {
				t.Fatalf("expected %v, got %v", tc.want, err)
			}
		})
	}
}

func TestTransferRejectsSelfAndInvalidAmountsBeforeDB(t *testing.T) {
	svc := NewService(nil, nil)
	userID := uuid.New()
	peerID := uuid.New()

	tests := []struct {
		name   string
		from   uuid.UUID
		to     uuid.UUID
		amount int64
		want   error
	}{
		{name: "self", from: userID, to: userID, amount: MinTransferCents, want: ErrSelfTransfer},
		{name: "zero", from: userID, to: peerID, amount: 0, want: ErrInvalidAmount},
		{name: "below minimum", from: userID, to: peerID, amount: MinTransferCents - 1, want: ErrAmountTooSmall},
		{name: "above maximum", from: userID, to: peerID, amount: MaxTransferCents + 1, want: ErrAmountTooLarge},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.Transfer(context.Background(), tc.from, tc.to, tc.amount, "")
			if !errors.Is(err, tc.want) {
				t.Fatalf("expected %v, got %v", tc.want, err)
			}
		})
	}
}

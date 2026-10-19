import SwiftUI
import AppKit

/// The "Buy us a coffee" button.
///
/// This was originally Stripe's hosted Buy Button embedded in a `WKWebView`,
/// which is the snippet Stripe generates. It didn't survive contact with a
/// real app: the custom element upgraded, the iframe appeared, and then Stripe
/// left the button stuck on its loading shimmer — forever, on every launch.
/// A skeleton on a dark popover is worse than no button at all, because it
/// looks like a rendering bug rather than a payment option.
///
/// So this draws the button natively and hands off to Stripe's hosted payment
/// page in the default browser. Same Stripe checkout, same payment link, same
/// account — but nothing that can half-render. The page itself is a far better
/// place to collect a card than a 284pt-wide iframe in a popover.
struct StripeBuyButton: View {
    /// Stripe's hosted payment page for this account.
    static let paymentLink = URL(string: "https://buy.stripe.com/fZu14mb8B9Li9Xd5BObEA00")!
    static let buyButtonID = "buy_btn_1USD7jAe4Pa3AR9tvGlMbjqP"
    static let publishableKey = "pk_live_51PvhoNAe4Pa3AR9tKQcqIgoT0Y7k0NG495AfC1Ld6Hj3tXI5MPjgs8rSyG0wITDRZRqpI8be9plbHHVyqQ0adNJa00IOFZO0KM"

    var body: some View {
        Button {
            Analytics.shared.track("checkout_started", ["source": "native_button"])
            NSWorkspace.shared.open(Self.paymentLink)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Buy us a coffee")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.52, blue: 0.22),
                                Color(red: 0.94, green: 0.38, blue: 0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Opens Stripe's secure checkout in your browser")
        .onAppear {
            Analytics.shared.track("support_view", [:])
        }
    }
}

//
//  ChatListHeader.swift
//  FlirttimeNew
//

import SwiftUI
import Combine

private final class ChatHeaderWallet: ObservableObject {
    @Published var balance: Int = CoinWallet.shared.balance
    private var bag = Set<AnyCancellable>()

    init() {
        CoinWallet.shared.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.balance = value }
            .store(in: &bag)
    }
}

private final class ChatHeaderNotifications: ObservableObject {
    @Published var unreadCount: Int = NotificationBadgeStore.shared.unreadCount
    private var bag = Set<AnyCancellable>()

    init() {
        NotificationBadgeStore.shared.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.unreadCount = value }
            .store(in: &bag)
    }
}

struct ChatListHeader: View {
    var onCoins: () -> Void = {}
    var onNotifications: () -> Void = {}
    var onGoLive: () -> Void = {}

    @StateObject private var wallet = ChatHeaderWallet()
    @StateObject private var notifications = ChatHeaderNotifications()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SwiftUI.Image("FlirtTimeTitle")
                .resizable()
                .scaledToFit()
                .frame(height: 24)
                .accessibilityLabel("FlirtTime")

            Spacer(minLength: 4)

            Button(action: onGoLive) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                    SwiftUI.Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("Go Live")
                        .font(.chatBold(size: 13))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.18, blue: 0.42), Color(red: 0.95, green: 0.08, blue: 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go Live")

            Button(action: onCoins) {
                HStack(spacing: 6) {
                    SwiftUI.Image("singleCoin")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("\(wallet.balance)")
                        .font(.chatBold(size: 15))
                        .foregroundColor(Color.chatTextPrimary)
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.chatPrimaryLight, Color.chatPrimary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 18, height: 18)
                        SwiftUI.Image(systemName: "plus")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coins")

            Button(action: onNotifications) {
                ZStack(alignment: .topTrailing) {
                    SwiftUI.Image("Notification")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)

                    if notifications.unreadCount > 0 {
                        Text(notifications.unreadCount > 9 ? "9+" : "\(notifications.unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.chatPrimary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            CoinWallet.shared.refresh()
            NotificationBadgeStore.shared.refresh()
        }
        .applyRTLEnvironment()
    }
}
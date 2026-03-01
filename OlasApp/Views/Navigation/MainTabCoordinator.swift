import NDKSwiftCore
import SwiftUI

@MainActor
@Observable
final class MainTabCoordinator {
    let walletViewModel: WalletViewModel
    let muteListManager: MuteListManager
    private(set) var sessionData: NDKSessionData?

    private let ndk: NDK

    init(ndk: NDK) {
        self.ndk = ndk
        self.walletViewModel = WalletViewModel(ndk: ndk)
        self.muteListManager = MuteListManager(ndk: ndk)
    }

    func performSetup(userPubkey: String?, muteListSources: [String], walletType: WalletType) async {
        if walletType == .cashu {
            await walletViewModel.loadWallet()
        }
        muteListManager.userPubkey = userPubkey
        muteListManager.updateMuteListSources(muteListSources)
        muteListManager.startSubscription()

        // Capture session data for follow list observation
        // NDKAuthManager calls startSession in a background Task, so we wait for it
        var attempts = 0
        while ndk.sessionData == nil && attempts < 100 {
            try? await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
        sessionData = ndk.sessionData
        if let sessionData {
            Task { await sessionData.syncWebOfTrust() }
        }
    }

    func updateMuteListSources(_ sources: [String]) {
        muteListManager.updateMuteListSources(sources)
    }
}

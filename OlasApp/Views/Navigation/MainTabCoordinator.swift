import NDKSwiftCore
import SwiftUI

@MainActor
@Observable
final class MainTabCoordinator {
    let walletViewModel: WalletViewModel
    let muteListManager: MuteListManager

    private let ndk: NDK

    init(ndk: NDK) {
        self.ndk = ndk
        self.walletViewModel = WalletViewModel(ndk: ndk)
        self.muteListManager = MuteListManager(ndk: ndk)
    }

    func performSetup(userPubkey: String?, muteListSources: [String]) async {
        await walletViewModel.loadWallet()
        muteListManager.userPubkey = userPubkey
        muteListManager.updateMuteListSources(muteListSources)
        muteListManager.startSubscription()
    }

    func updateMuteListSources(_ sources: [String]) {
        muteListManager.updateMuteListSources(sources)
    }
}

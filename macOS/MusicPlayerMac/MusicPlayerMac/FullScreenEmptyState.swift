import SwiftUI

struct FullScreenEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.title2.bold())
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
    }
}

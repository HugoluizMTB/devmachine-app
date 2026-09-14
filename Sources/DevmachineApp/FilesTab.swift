import SwiftUI

struct FilesTab: View {
    let alias: String
    let session: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Files — coming next")
                .font(.system(size: 12))
                .foregroundStyle(Color.dmMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

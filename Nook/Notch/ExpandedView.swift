import SwiftUI

struct ExpandedView: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ExpandedPlayer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.showsCalendarColumn {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                UpNextList()
                    .frame(width: 168)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }
}

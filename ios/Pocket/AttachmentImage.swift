import SwiftUI

struct AttachmentImage: View {
    @EnvironmentObject private var model: AppModel
    let sessionId: String
    let ref: PocketImageRef
    var size: CGFloat = 150

    @State private var image: UIImage?
    @State private var zoomed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.layer2)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.dim2)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.lineStrong)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard image != nil else { return }
            Haptics.tap()
            zoomed = true
        }
        .task(id: ref.attachmentId) {
            image = await model.loadImage(sessionId: sessionId, ref: ref)
        }
        .fullScreenCover(isPresented: $zoomed) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            zoomed = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
            .onTapGesture { zoomed = false }
        }
    }
}

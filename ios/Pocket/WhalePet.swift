import SwiftUI
import ImageIO
import UIKit

// MARK: - Animated GIF (frames driven by TimelineView, so SwiftUI owns the layout)

enum GIFAssets {
    static let whale: (frames: [UIImage], duration: Double)? = load("rua")

    static func load(_ name: String) -> (frames: [UIImage], duration: Double)? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: image))
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let delay = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, delay > 0 {
                    duration += delay
                } else if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                    duration += delay
                }
            }
        }
        guard !frames.isEmpty else { return nil }
        return (frames, max(duration, Double(count) * 0.08))
    }
}

struct AnimatedGIF: View {
    let name: String
    @State private var started = Date()

    private var asset: (frames: [UIImage], duration: Double)? {
        name == "rua" ? GIFAssets.whale : GIFAssets.load(name)
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                if let asset, !asset.frames.isEmpty {
                    let elapsed = max(0, context.date.timeIntervalSince(started))
                    let perFrame = asset.duration / Double(asset.frames.count)
                    let index = Int(elapsed / perFrame) % asset.frames.count
                    Image(uiImage: asset.frames[index])
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Color.clear
                }
            }
        }
        .clipped()
        .onAppear { started = Date() }
    }
}

// MARK: - Floating desktop pet

struct WhalePet: View {
    @EnvironmentObject private var model: AppModel
    var onOpenDetails: () -> Void

    @State private var open = false
    @State private var petting = false
    @State private var bob = false
    @State private var drag = CGSize.zero
    @State private var resting = CGSize.zero
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if open { bubble.transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity)) }

            Group {
                if petting {
                    AnimatedGIF(name: "rua")
                } else {
                    Image(uiImage: UIImage(named: "pet") ?? UIImage())
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
            .frame(width: 76, height: 76)
            .offset(y: bob ? -3 : 0)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.7, anchor: .bottomTrailing)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { open.toggle() }
                Task {
                    await model.loadWhale()
                    petting = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    petting = false
                }
            }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            drag = CGSize(
                                width: resting.width + value.translation.width,
                                height: resting.height + value.translation.height
                            )
                        }
                        .onEnded { _ in resting = drag }
                )
        }
        .offset(drag)
        .padding(.trailing, 10)
        .padding(.bottom, 4)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { bob = true }
            Task { await model.loadWhale() }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("大肥鱼")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
                Text(model.whale?.date ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.dim2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("¥")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                Text(String(format: "%.2f", model.whale?.balance ?? 0))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.fg)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Text("今日 " + String(format: "¥%.2f", model.whale?.today ?? 0))
                Text(model.whale?.offPeak == true ? "谷时 5 折" : "峰时")
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(Theme.dim)

            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
                .padding(.vertical, 1)

            Button {
                Haptics.tap()
                onOpenDetails()
            } label: {
                HStack(spacing: 4) {
                    Text("消耗明细")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.fgSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 176, alignment: .leading)
        .background(Theme.layer2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.lineStrong)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}

import SwiftUI

// MARK: - ExpandableSection
//
// Текстовый блок с плавным fade-out и кнопкой More / Less.
// Автоматически определяет нужно ли раскрытие (isTruncated).
//
// Использование:
//   ExpandableSection(text: desc, font: .subheadline, lineSpacing: 2, linesLimit: 3)

struct ExpandableSection: View {
    var title:       String?
    let text:        String
    var font:        Font        = .subheadline
    var lineSpacing: CGFloat     = 2
    var linesLimit:  Int         = 3

    @State private var showFull:      Bool    = false
    @State private var isTruncated:   Bool    = false
    @State private var fullHeight:    CGFloat = 0
    @State private var limitedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.headline)
                    .frame(height: 55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(nil, value: showFull)
            }

            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
                .lineLimit(nil)
                .frame(
                    height: showFull ? max(fullHeight, 55) : max(limitedHeight, 55),
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: (showFull || !isTruncated) ? 1.0 : 0.75),
                            .init(color: .clear,  location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    )
                }
                .overlay(alignment: .topLeading) {
                    // Measure full height
                    Text(text)
                        .font(font)
                        .lineSpacing(lineSpacing)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .getSize { fullHeight = $0.height }
                    // Measure limited height
                    Text(text)
                        .font(font)
                        .lineSpacing(lineSpacing)
                        .lineLimit(linesLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .getSize { limitedHeight = $0.height }
                }
                .onChange(of: fullHeight)    { isTruncated = fullHeight > limitedHeight }
                .onChange(of: limitedHeight) { isTruncated = fullHeight > limitedHeight }

            if isTruncated {
                HStack {
                    Spacer()
                    MoreLessButton(showFull: $showFull)
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - MoreLessButton

struct MoreLessButton: View {
    @Binding var showFull: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.5)) { showFull.toggle() }
        } label: {
            Text(showFull
                 ? "less... \(Image(systemName: "arrow.up.to.line.compact"))"
                 : "...more \(Image(systemName: "arrow.down.to.line.compact"))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.myColors.myBlue)
                .frame(minWidth: 60, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View.getSize

extension View {
    func getSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onChange(geo.size) }
                    .onChange(of: geo.size) { _, newSize in onChange(newSize) }
            }
        )
    }
}

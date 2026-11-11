// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var player: PlaybackController
    @AppStorage("lyrics.style") private var style = "Apple Music"
    @AppStorage("lyrics.position") private var position = "Center"
    @AppStorage("lyrics.follow") private var autoFollow = true
    @AppStorage("lyrics.click") private var clickToSeek = true
    @AppStorage("lyrics.size") private var textSize = 28.0
    @AppStorage("lyrics.english") private var showEnglish = false
    @AppStorage("lyrics.spacing") private var lineSpacing = 22.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var browsing = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var english: [LyricLine]?
    @State private var translationError: String?
    @State private var translating = false
    private struct TranslationRequest: Hashable {
        let lines: [LyricLine]
        let enabled: Bool
    }
    private var lines: [LyricLine] { showEnglish ? english ?? player.lyrics : player.lyrics }
    private var active: Int? { LyricsParser.activeIndex(in: lines, at: player.position) }
    private var alignment: Alignment { position == "Left" ? .leading : position == "Right" ? .trailing : .center }
    private var textAlignment: TextAlignment { position == "Left" ? .leading : position == "Right" ? .trailing : .center }
    private var animation: Animation? {
        if reduceMotion || style == "None" { return nil }
        return style == "Apple Music" ? .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.55) : .easeInOut(duration: 0.35)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !player.lyrics.isEmpty {
                HStack {
                    if translating { ProgressView().accessibilityLabel("Translating lyrics") }
                    if let error = translationError, showEnglish {
                        Text(error).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        showEnglish.toggle()
                    } label: {
                        Label(showEnglish ? "Original lyrics" : "Translate to English", systemImage: "globe")
                    }.font(.caption)
                }.padding(.horizontal, 24)
            }
            lyricScroll
        }
        .task(id: TranslationRequest(lines: player.lyrics, enabled: showEnglish)) {
            english = nil
            translationError = nil
            translating = false
            guard showEnglish, !player.lyrics.isEmpty else { return }
            translating = true
            do {
                let translated = try await LyricTranslation.shared.english(player.lyrics)
                guard !Task.isCancelled else { return }
                english = translated
            } catch {
                guard !Task.isCancelled else { return }
                translationError = error.localizedDescription
            }
            translating = false
        }
    }

    private var lyricScroll: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    if player.lyricsLoading { ProgressView("Loading lyrics…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if player.lyrics.isEmpty {
                        Text("Lyrics aren’t available for this song.").foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: lineSpacing) {
                                ForEach(lines) { line in
                                    let highlighted = active == line.id
                                    lyricText(line, highlighted: highlighted)
                                        .font(PlayTheme.font(CGFloat(textSize), weight: highlighted ? .bold : .semibold))
                                        .multilineTextAlignment(textAlignment)
                                        .frame(maxWidth: .infinity, alignment: alignment)
                                        .opacity(line.time == nil || highlighted ? 1 : 0.45)
                                        .scaleEffect(style == "Apple Music" && !highlighted ? 0.96 : 1, anchor: position == "Left" ? .leading : position == "Right" ? .trailing : .center)
                                        .animation(animation, value: highlighted)
                                        .shadow(color: style == "Glow" && highlighted ? PlayTheme.accent.opacity(0.7) : .clear, radius: 9)
                                        .offset(x: style == "Slide" && !highlighted ? -10 : 0)
                                        .overlay {
                                            if style == "Karaoke", highlighted, !line.words.contains(where: { $0.time != nil }) {
                                                GeometryReader { measured in
                                                    Text(line.text).font(PlayTheme.font(CGFloat(textSize), weight: .bold))
                                                        .multilineTextAlignment(textAlignment)
                                                        .frame(maxWidth: .infinity, alignment: alignment)
                                                        .foregroundColor(PlayTheme.accent)
                                                        .mask(alignment: .leading) { Rectangle().frame(width: measured.size.width * CGFloat(progress(line))) }
                                                }.allowsHitTesting(false)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture { if clickToSeek, let time = line.time { browsing = false; player.seek(time) } }
                                        .id(line.id)
                                }
                            }.padding(.horizontal, 24).padding(.vertical, geometry.size.height / 2)
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                            resumeTask?.cancel(); browsing = true
                        }.onEnded { _ in
                            resumeTask?.cancel()
                            resumeTask = Task {
                                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                                catch { return }
                                browsing = false
                            }
                        })
                        if browsing && autoFollow {
                            Button("Resume following") { resumeTask?.cancel(); browsing = false }
                                .buttonStyle(.borderedProminent).padding(.bottom, 8)
                        }
                    }
                }
            }
            .onChange(of: active) { _ in follow(proxy) }
            .onChange(of: browsing) { _ in follow(proxy) }
            .onChange(of: autoFollow) { _ in follow(proxy) }
            .onChange(of: position) { _ in follow(proxy) }
            .task(id: lines) { await Task.yield(); follow(proxy) }
            .onDisappear { resumeTask?.cancel() }
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard autoFollow, !browsing, let active = active else { return }
        withAnimation(animation) { proxy.scrollTo(active, anchor: .center) }
    }
    private func lyricText(_ line: LyricLine, highlighted: Bool) -> Text {
        guard style == "Karaoke", highlighted, line.words.contains(where: { $0.time != nil }) else {
            return Text(line.text.isEmpty ? "♪" : line.text)
        }
        return line.words.reduce(Text("")) { result, word in
            let sung = word.time.map { $0 <= player.position } ?? false
            return result + Text(word.text).foregroundColor(sung ? PlayTheme.accent : .primary)
        }
    }
    private func progress(_ line: LyricLine) -> Double {
        guard let start = line.time, let index = lines.firstIndex(where: { $0.id == line.id }) else { return 0 }
        let end = lines.dropFirst(index + 1).compactMap(\.time).first ?? player.duration
        guard end > start else { return 1 }
        return min(1, max(0, (player.position - start) / (end - start)))
    }
}

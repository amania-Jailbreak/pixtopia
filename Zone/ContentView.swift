import SwiftUI
import Combine
import Foundation
import OSLog
import Photos
import Security
import UIKit
import WebKit

private let pixivAPILogger = Logger(subsystem: "jp.amania.pixtopia", category: "PixivAPI")

@main
struct ZoneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var store = FeedStore()
    @StateObject private var sessionStore = SessionStore()
    @State private var selectedTab = 0
    @State private var isShowingReviewDemo = false

    var body: some View {
        Group {
            if isShowingReviewDemo {
                ReviewDemoView {
                    isShowingReviewDemo = false
                }
            } else if sessionStore.isLoggedIn, let credentials = sessionStore.credentials {
                MainTabView(
                    store: store,
                    sessionStore: sessionStore,
                    credentials: credentials,
                    selectedTab: $selectedTab
                )
            } else {
                OnboardingView(
                    sessionStore: sessionStore,
                    onOpenReviewDemo: { isShowingReviewDemo = true }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sessionStore.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: isShowingReviewDemo)
    }
}

private struct MainTabView: View {
    @ObservedObject var store: FeedStore
    @ObservedObject var sessionStore: SessionStore
    let credentials: PixivSessionCredentials
    @Binding var selectedTab: Int
    @State private var feedMode: FeedMode = .recommended
    @State private var currentUserExtra: PixivUserExtra?
    @State private var isShowingLaunchSplash = true
    @State private var requestedSearchTag: String?
    @State private var tabReselectionTokens = [0, 0, 0, 0]
    @State private var isMangaViewerActive = false

    var body: some View {
        ZStack {
            selectedContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isMangaViewerActive {
                        ZoneBottomBar(
                            selectedTab: $selectedTab,
                            onReselect: scrollSelectedTabToTop
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

            if isShowingLaunchSplash {
                ZoneLaunchSplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .tint(ZoneTheme.accent)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.18), value: isMangaViewerActive)
        .task(id: credentials.savedAt) {
            async let contextLookup = PixivAPIClient(credentials: credentials)
                .fetchCurrentUserContext()

            await store.load(using: credentials)
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingLaunchSplash = false
            }

            do {
                let context = try await contextLookup
                currentUserExtra = context.extra
                sessionStore.updateUserID(context.userID)
            } catch {
                pixivAPILogger.error("current user lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case 1:
            DiscoverView(
                store: store,
                credentials: credentials,
                requestedTag: $requestedSearchTag,
                scrollToTopToken: tabReselectionTokens[1],
                onMangaViewerChanged: { isMangaViewerActive = $0 }
            )
        case 2:
            LibraryView(
                store: store,
                credentials: credentials,
                onSearchTag: openTagSearch,
                scrollToTopToken: tabReselectionTokens[2],
                onMangaViewerChanged: { isMangaViewerActive = $0 }
            )
        case 3:
            MyPageView(
                credentials: credentials,
                extra: currentUserExtra,
                scrollToTopToken: tabReselectionTokens[3],
                onLogout: sessionStore.logout
            )
        default:
            HomeView(
                store: store,
                credentials: credentials,
                feedMode: $feedMode,
                onSearchTag: openTagSearch,
                scrollToTopToken: tabReselectionTokens[0],
                onMangaViewerChanged: { isMangaViewerActive = $0 }
            )
        }
    }

    private func openTagSearch(_ tag: String) {
        requestedSearchTag = tag
        selectedTab = 1
    }

    private func scrollSelectedTabToTop(_ tab: Int) {
        guard tabReselectionTokens.indices.contains(tab) else { return }
        tabReselectionTokens[tab] &+= 1
    }
}

private struct ZoneLaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var triangleRotation = 0.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            HStack(spacing: 18) {
                Image(systemName: "triangle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(ZoneTheme.accent)
                    .rotationEffect(.degrees(triangleRotation), anchor: .center)

                Text("PIXTOPIA")
                    .font(.system(size: 44, weight: .black))
                    .tracking(4)
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("pixtopiaを起動中")
        }
        .task {
            guard !reduceMotion else { return }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.5)) {
                    triangleRotation += 360
                }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }
}

private struct ZoneBottomBar: View {
    @Binding var selectedTab: Int
    let onReselect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            tabButton(tab: 0, title: nil, systemImage: "triangle.fill", accessibilityLabel: "pixtopia")
            tabButton(tab: 1, title: "探す", systemImage: "sparkle.magnifyingglass", accessibilityLabel: "探す")
            tabButton(tab: 2, title: "保存", systemImage: "bookmark.fill", accessibilityLabel: "保存")
            tabButton(tab: 3, title: "マイページ", systemImage: "person.crop.circle", accessibilityLabel: "マイページ")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.82))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func tabButton(
        tab: Int,
        title: String?,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            if isSelected {
                onReselect(tab)
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                if let title {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? ZoneTheme.accent : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected ? ZoneTheme.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isSelected ? "もう一度押すと先頭へ戻ります" : "このタブを開きます")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Models

struct Artwork: Identifiable {
    let id: String
    let kind: String
    let pageCount: Int
    let title: String
    let creator: String
    let handle: String
    let tags: [String]
    let likes: Int
    let bookmarks: Int
    let comments: Int
    let symbol: String
    let palette: [Color]
    let imageURL: URL?
    let isBookmarkable: Bool
    let bookmarkID: String?
    var profileImageURL: URL? = nil
}

enum FeedMode: String, CaseIterable, Identifiable, Hashable {
    case recommended = "おすすめ"
    case following = "フォロー中"
    case ranking = "ランキング"

    var id: String { rawValue }
}

private struct PixivUserReference: Identifiable {
    let id: String
    let name: String
    let profileImageURL: URL?

    init(artwork: Artwork) {
        id = artwork.handle.hasPrefix("@") ? String(artwork.handle.dropFirst()) : artwork.handle
        name = artwork.creator
        profileImageURL = artwork.profileImageURL
    }
}

fileprivate enum ArtworkSearchKind: String, CaseIterable, Identifiable {
    case illustrations = "イラスト"
    case manga = "漫画"

    var id: Self { self }

    var endpointComponent: String {
        switch self {
        case .illustrations: "illustrations"
        case .manga: "manga"
        }
    }
}

fileprivate enum ArtworkSearchMode: String, CaseIterable, Identifiable {
    case all
    case safe
    case r18

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "ALL"
        case .safe: "SFW"
        case .r18: "R-18"
        }
    }
}

fileprivate enum ArtworkSearchOrder: String, CaseIterable, Identifiable {
    case latest = "新着順"
    case popular = "人気順"

    var id: Self { self }
}

@MainActor
final class FeedStore: ObservableObject {
    @Published var artworks: [Artwork] = []
    @Published private(set) var likedIDs = Set<String>()
    @Published private(set) var pendingLikeIDs = Set<String>()
    @Published private(set) var bookmarkIDs: [String: String] = [:]
    @Published private(set) var pendingBookmarkIDs = Set<String>()
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadError: String?
    @Published private(set) var bookmarkedArtworks: [Artwork] = []
    @Published private(set) var isLoadingBookmarks = false
    @Published private(set) var isLoadingMoreBookmarks = false
    @Published private(set) var bookmarkLoadError: String?

    private var nextFeedCursor: PixivFeedCursor?
    private var hasMoreFeed = true
    private var savedArtworkCache: [String: Artwork] = [:]
    private var bookmarkOffset = 0
    private var hasMoreBookmarks = false
    private var bookmarkListUserID: String?
    private var hasLoadedBookmarks = false
    private let bookmarkPageLimit = 30

    var savedArtworks: [Artwork] {
        let remoteArtworks = bookmarkedArtworks.filter { bookmarkIDs[$0.id] != nil }
        let remoteIDs = Set(remoteArtworks.map(\.id))
        let additionalArtworks = savedArtworkCache.values
            .filter { bookmarkIDs[$0.id] != nil && !remoteIDs.contains($0.id) }
            .sorted { $0.id > $1.id }
        return remoteArtworks + additionalArtworks
    }

    func isLiked(_ artwork: Artwork) -> Bool {
        likedIDs.contains(artwork.id)
    }

    func isLikePending(_ artwork: Artwork) -> Bool {
        pendingLikeIDs.contains(artwork.id)
    }

    func like(_ artwork: Artwork, using credentials: PixivSessionCredentials) async {
        guard !likedIDs.contains(artwork.id), !pendingLikeIDs.contains(artwork.id) else { return }

        pendingLikeIDs.insert(artwork.id)
        defer { pendingLikeIDs.remove(artwork.id) }

        do {
            try await PixivAPIClient(credentials: credentials).likeArtwork(illustID: artwork.id)
            likedIDs.insert(artwork.id)
        } catch {
            pixivAPILogger.error("like failed artwork=\(artwork.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[PixivAPI] like failed artwork=\(artwork.id) error=\(error.localizedDescription)")
            #endif
        }
    }

    func isSaved(_ artwork: Artwork) -> Bool {
        bookmarkIDs[artwork.id] != nil
    }

    func isBookmarkPending(_ artwork: Artwork) -> Bool {
        pendingBookmarkIDs.contains(artwork.id)
    }

    func registerBookmarkState(from artworks: [Artwork]) {
        for artwork in artworks {
            guard let bookmarkID = artwork.bookmarkID else { continue }
            bookmarkIDs[artwork.id] = bookmarkID
            savedArtworkCache[artwork.id] = artwork
        }
    }

    func toggleBookmark(_ artwork: Artwork, using credentials: PixivSessionCredentials) async {
        guard artwork.isBookmarkable, !pendingBookmarkIDs.contains(artwork.id) else { return }

        pendingBookmarkIDs.insert(artwork.id)
        defer { pendingBookmarkIDs.remove(artwork.id) }

        do {
            let client = PixivAPIClient(credentials: credentials)
            if let bookmarkID = bookmarkIDs[artwork.id] {
                try await client.deleteBookmark(bookmarkID: bookmarkID)
                bookmarkIDs.removeValue(forKey: artwork.id)
                savedArtworkCache.removeValue(forKey: artwork.id)
                if let index = bookmarkedArtworks.firstIndex(where: { $0.id == artwork.id }),
                   index < bookmarkOffset {
                    bookmarkOffset = max(bookmarkOffset - 1, 0)
                }
                bookmarkedArtworks.removeAll { $0.id == artwork.id }
            } else {
                let bookmarkID = try await client.addBookmark(illustID: artwork.id)
                bookmarkIDs[artwork.id] = bookmarkID
                savedArtworkCache[artwork.id] = artwork
                if hasLoadedBookmarks,
                   !bookmarkedArtworks.contains(where: { $0.id == artwork.id }) {
                    bookmarkedArtworks.insert(artwork, at: 0)
                }
            }
        } catch {
            pixivAPILogger.error("bookmark mutation failed artwork=\(artwork.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[PixivAPI] bookmark mutation failed artwork=\(artwork.id) error=\(error.localizedDescription)")
            #endif
        }
    }

    func load(using credentials: PixivSessionCredentials) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        isLoadingMore = false
        loadError = nil

        do {
            let client = PixivAPIClient(credentials: credentials)
            var loadedArtworks: [Artwork] = []
            var cursor: PixivFeedCursor?

            for _ in 0..<3 {
                let page = try await client.fetchFeedPage(after: cursor)
                loadedArtworks.append(contentsOf: page.artworks)
                cursor = page.nextCursor

                guard page.nextCursor != nil else { break }
            }

            artworks = uniqueArtworks(loadedArtworks)
            registerBookmarkState(from: artworks)
            nextFeedCursor = cursor
            hasMoreFeed = cursor != nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }

    func loadNextPageIfNeeded(after artwork: Artwork, using credentials: PixivSessionCredentials) async {
        guard !isLoading, !isLoadingMore, hasMoreFeed,
              let index = artworks.firstIndex(where: { $0.id == artwork.id }),
              artworks.count - index <= 5 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await PixivAPIClient(credentials: credentials)
                .fetchFeedPage(after: nextFeedCursor)
            appendUnique(page.artworks)
            nextFeedCursor = page.nextCursor
            hasMoreFeed = page.nextCursor != nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func loadBookmarks(userID: String, using credentials: PixivSessionCredentials) async {
        guard !isLoadingBookmarks else { return }
        guard bookmarkListUserID != userID || !hasLoadedBookmarks else { return }

        isLoadingBookmarks = true
        isLoadingMoreBookmarks = false
        bookmarkLoadError = nil
        bookmarkListUserID = userID
        bookmarkedArtworks = []
        bookmarkOffset = 0
        hasMoreBookmarks = false
        defer { isLoadingBookmarks = false }

        do {
            let page = try await PixivAPIClient(credentials: credentials).fetchBookmarks(
                userID: userID,
                offset: 0,
                limit: bookmarkPageLimit
            )
            bookmarkedArtworks = uniqueArtworks(page.artworks)
            registerBookmarkState(from: bookmarkedArtworks)
            bookmarkOffset = page.nextOffset
            hasMoreBookmarks = page.nextOffset < page.total && page.itemCount > 0
            hasLoadedBookmarks = true
        } catch {
            bookmarkLoadError = error.localizedDescription
            hasLoadedBookmarks = false
        }
    }

    func loadNextBookmarksIfNeeded(after artwork: Artwork, using credentials: PixivSessionCredentials) async {
        guard let userID = bookmarkListUserID,
              hasLoadedBookmarks,
              hasMoreBookmarks,
              !isLoadingBookmarks,
              !isLoadingMoreBookmarks,
              let index = bookmarkedArtworks.firstIndex(where: { $0.id == artwork.id }),
              bookmarkedArtworks.count - index <= 6 else { return }

        isLoadingMoreBookmarks = true
        defer { isLoadingMoreBookmarks = false }

        do {
            let page = try await PixivAPIClient(credentials: credentials).fetchBookmarks(
                userID: userID,
                offset: bookmarkOffset,
                limit: bookmarkPageLimit
            )
            let existingIDs = Set(bookmarkedArtworks.map(\.id))
            let newArtworks = page.artworks.filter { !existingIDs.contains($0.id) }
            bookmarkedArtworks.append(contentsOf: newArtworks)
            registerBookmarkState(from: newArtworks)
            bookmarkOffset = page.nextOffset
            hasMoreBookmarks = page.nextOffset < page.total && page.itemCount > 0
        } catch {
            bookmarkLoadError = error.localizedDescription
        }
    }

    private func appendUnique(_ newArtworks: [Artwork]) {
        let existingIDs = Set(artworks.map(\.id))
        let uniqueNewArtworks = newArtworks.filter { !existingIDs.contains($0.id) }
        artworks.append(contentsOf: uniqueNewArtworks)
        registerBookmarkState(from: uniqueNewArtworks)
    }

    private func uniqueArtworks(_ source: [Artwork]) -> [Artwork] {
        var seenIDs = Set<String>()
        return source.filter { seenIDs.insert($0.id).inserted }
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var store: FeedStore
    let credentials: PixivSessionCredentials
    @Binding var feedMode: FeedMode
    let onSearchTag: (String) -> Void
    let scrollToTopToken: Int
    let onMangaViewerChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedUser: PixivUserReference?
    @State private var scrollLockedArtworkID: String?
    @State private var currentArtworkID: String?

    var body: some View {
        ReelPager(
            items: store.artworks,
            currentID: $currentArtworkID,
            resetKey: AnyHashable("\(credentials.savedAt.timeIntervalSinceReferenceDate)|\(scrollToTopToken)"),
            isPagingEnabled: scrollLockedArtworkID == nil,
            onPageChanged: { artwork in
                Task {
                    await store.loadNextPageIfNeeded(after: artwork, using: credentials)
                }
            },
            onRefresh: {
                await store.load(using: credentials)
                return store.loadError == nil
            }
        ) { artwork in
            ArtworkCard(
                artwork: artwork,
                credentials: credentials,
                isLiked: store.isLiked(artwork),
                isLikePending: store.isLikePending(artwork),
                isSaved: store.isSaved(artwork),
                isSavePending: store.isBookmarkPending(artwork),
                onLike: {
                    Task { await store.like(artwork, using: credentials) }
                },
                onSave: {
                    Task { await store.toggleBookmark(artwork, using: credentials) }
                },
                onCreatorTap: { selectedUser = PixivUserReference(artwork: artwork) },
                onTagTap: onSearchTag,
                onScrollLockChanged: { isLocked in
                    updateScrollLock(for: artwork.id, isLocked: isLocked)
                },
                onMangaViewerChanged: onMangaViewerChanged
            )
        }
        .background(.black)
        .overlay {
            if let loadError = store.loadError {
                ContentUnavailableView(
                    "作品を読み込めませんでした",
                    systemImage: "wifi.exclamationmark",
                    description: Text(loadError)
                )
                .padding(.horizontal, 28)
            }
        }
        .overlay(alignment: .bottom) {
            if store.isLoadingMore {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    TimelineView(.animation(paused: !store.isLoading || reduceMotion)) { timeline in
                        let rotation = store.isLoading && !reduceMotion
                            ? timeline.date.timeIntervalSinceReferenceDate * 1_800
                            : 0
                        Image(systemName: "triangle.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(ZoneTheme.accent)
                            .rotationEffect(.degrees(rotation))
                    }
                    Text("PIXTOPIA")
                        .font(.headline.weight(.black))
                        .tracking(2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("pixtopia")
                .accessibilityValue(store.isLoading ? "更新中" : "")

                Spacer()

                Menu {
                    ForEach(FeedMode.allCases) { mode in
                        Button {
                            feedMode = mode
                        } label: {
                            if feedMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("フィードを絞り込む")
                .accessibilityValue(feedMode.rawValue)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedUser) { user in
            PixivUserProfileView(
                user: user,
                store: store,
                credentials: credentials,
                onSearchTag: { tag in
                    selectedUser = nil
                    onSearchTag(tag)
                }
            )
        }
    }

    private func updateScrollLock(for artworkID: String, isLocked: Bool) {
        if isLocked {
            scrollLockedArtworkID = artworkID
        } else if scrollLockedArtworkID == artworkID {
            scrollLockedArtworkID = nil
        }
    }
}

private enum ReelPagerMotion {
    static let startingVelocity: CGFloat = 1_500
    static let maximumStartingVelocity: CGFloat = 2_200
    static let peakVelocity: CGFloat = 5_000
    static let maximumPeakVelocity: CGFloat = 6_000
    static let endingVelocity: CGFloat = 1_400
    static let accelerationDistanceRatio: CGFloat = 0.38
    static let accelerationExponent: CGFloat = 1.8
    static let decelerationExponent: CGFloat = 0.55
    static let pageChangeDistanceRatio: CGFloat = 0.12
    static let flickVelocity: CGFloat = 350
    static let edgeResistance: CGFloat = 0.25
    static let refreshDistance: CGFloat = 80
    static let reducedMotionDuration: TimeInterval = 0.12
}

@MainActor
private final class ReelPagerMotionController: NSObject, ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    private(set) var dragVelocity: CGFloat = 0
    private(set) var isDragging = false
    private(set) var isSettling = false

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var targetOffset: CGFloat = 0
    private var settleDirection: CGFloat = 0
    private var settleStartOffset: CGFloat = 0
    private var settleTotalDistance: CGFloat = 0
    private var settleStartVelocity: CGFloat = 0
    private var settlePeakVelocity: CGFloat = 0
    private var settleCompletion: (() -> Void)?
    private var dragOrigin: CGFloat = 0
    private var previousDragTranslation: CGFloat = 0
    private var previousDragTime: Date?
    private var reducedMotionElapsed: TimeInterval = 0
    private var reducedMotionStartOffset: CGFloat = 0
    private var usesReducedMotion = false

    func beginDragIfNeeded(at time: Date) {
        guard !isDragging else { return }
        cancelSettling(keepOffset: true)
        isDragging = true
        dragOrigin = offset
        previousDragTranslation = 0
        previousDragTime = time
        dragVelocity = 0
    }

    func updateDrag(translation: CGFloat, at time: Date, resistance: CGFloat) {
        beginDragIfNeeded(at: time)
        let elapsed = max(time.timeIntervalSince(previousDragTime ?? time), 1.0 / 240.0)
        dragVelocity = (translation - previousDragTranslation) / elapsed
        previousDragTranslation = translation
        previousDragTime = time
        offset = dragOrigin + translation * resistance
    }

    func endDrag() -> CGFloat {
        isDragging = false
        previousDragTime = nil
        return dragVelocity
    }

    func settle(
        to targetOffset: CGFloat,
        releaseVelocity: CGFloat,
        reduceMotion: Bool,
        completion: @escaping () -> Void
    ) {
        cancelSettling(keepOffset: true)
        let remaining = targetOffset - offset
        guard abs(remaining) > 0.5 else {
            offset = targetOffset
            completion()
            return
        }

        self.targetOffset = targetOffset
        settleDirection = remaining > 0 ? 1 : -1
        settleStartOffset = offset
        settleTotalDistance = abs(remaining)
        settleStartVelocity = min(
            max(abs(releaseVelocity) * 0.18, ReelPagerMotion.startingVelocity),
            ReelPagerMotion.maximumStartingVelocity
        )
        settlePeakVelocity = min(
            ReelPagerMotion.peakVelocity + abs(releaseVelocity) * 0.12,
            ReelPagerMotion.maximumPeakVelocity
        )
        settleCompletion = completion
        usesReducedMotion = reduceMotion
        reducedMotionElapsed = 0
        reducedMotionStartOffset = offset
        isSettling = true
        startDisplayLink()
    }

    func reset(to offset: CGFloat = 0) {
        cancelSettling(keepOffset: false)
        isDragging = false
        dragVelocity = 0
        self.offset = offset
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        lastTimestamp = nil
        let displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        let deltaTime: TimeInterval
        if let lastTimestamp {
            deltaTime = min(max(displayLink.timestamp - lastTimestamp, 1.0 / 240.0), 1.0 / 30.0)
        } else {
            deltaTime = displayLink.duration
        }
        lastTimestamp = displayLink.timestamp

        if usesReducedMotion {
            reducedMotionElapsed += deltaTime
            let progress = min(reducedMotionElapsed / ReelPagerMotion.reducedMotionDuration, 1)
            offset = reducedMotionStartOffset + (targetOffset - reducedMotionStartOffset) * progress
            if progress >= 1 { finishSettling() }
            return
        }

        let remaining = abs(targetOffset - offset)
        let traveled = min(abs(offset - settleStartOffset), settleTotalDistance)
        let progress = settleTotalDistance > 0 ? traveled / settleTotalDistance : 1
        let velocity = settleVelocity(at: progress)
        let distance = min(velocity * deltaTime, remaining)
        offset += distance * settleDirection
        if remaining - distance <= 0.5 {
            offset = targetOffset
            finishSettling()
        }
    }

    private func settleVelocity(at progress: CGFloat) -> CGFloat {
        let accelerationEnd = ReelPagerMotion.accelerationDistanceRatio
        if progress < accelerationEnd {
            let localProgress = max(progress / accelerationEnd, 0)
            let curvedProgress = pow(localProgress, ReelPagerMotion.accelerationExponent)
            return settleStartVelocity + (settlePeakVelocity - settleStartVelocity) * curvedProgress
        }

        let localProgress = min(
            max((progress - accelerationEnd) / (1 - accelerationEnd), 0),
            1
        )
        let curvedProgress = pow(localProgress, ReelPagerMotion.decelerationExponent)
        return settlePeakVelocity
            - (settlePeakVelocity - ReelPagerMotion.endingVelocity) * curvedProgress
    }

    private func finishSettling() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        isSettling = false
        let completion = settleCompletion
        settleCompletion = nil
        completion?()
    }

    private func cancelSettling(keepOffset: Bool) {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        settleCompletion = nil
        isSettling = false
        if !keepOffset { offset = 0 }
    }

    deinit {
        displayLink?.invalidate()
    }
}

private struct ReelPager<Item: Identifiable, Page: View>: View {
    let items: [Item]
    @Binding var currentID: Item.ID?
    let resetKey: AnyHashable
    let isPagingEnabled: Bool
    let onPageChanged: (Item) -> Void
    let onRefresh: (() async -> Bool)?
    @ViewBuilder let page: (Item) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = ReelPagerMotionController()
    @State private var currentIndex = 0
    @State private var rawDragTranslation: CGFloat = 0
    @State private var isRefreshing = false
    @State private var lastReportedID: Item.ID?

    private var itemIDs: [Item.ID] {
        items.map(\.id)
    }

    var body: some View {
        GeometryReader { proxy in
            let pageSize = proxy.size

            ZStack {
                ForEach(visibleIndices, id: \.self) { index in
                    page(items[index])
                        .frame(width: pageSize.width, height: pageSize.height)
                        .offset(
                            y: CGFloat(index - currentIndex) * pageSize.height + motion.offset
                        )
                        .id(items[index].id)
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(verticalDrag(pageHeight: max(pageSize.height, 1)))
            .accessibilityScrollAction { edge in
                switch edge {
                case .top:
                    settleByAccessibility(delta: -1, pageHeight: max(pageSize.height, 1))
                case .bottom:
                    settleByAccessibility(delta: 1, pageHeight: max(pageSize.height, 1))
                default:
                    break
                }
            }
            .onAppear {
                synchronizeCurrentItem(resetToFirst: false)
                reportCurrentPageIfNeeded()
            }
            .onChange(of: itemIDs) {
                synchronizeCurrentItem(resetToFirst: false)
            }
            .onChange(of: resetKey) {
                synchronizeCurrentItem(resetToFirst: true)
            }
            .onChange(of: pageSize) {
                motion.reset()
                synchronizeCurrentItem(resetToFirst: false)
            }
            .onChange(of: isPagingEnabled) {
                if !isPagingEnabled {
                    motion.reset()
                    rawDragTranslation = 0
                }
            }
        }
    }

    private var visibleIndices: [Int] {
        guard !items.isEmpty else { return [] }
        return Array(max(currentIndex - 1, 0)...min(currentIndex + 1, items.count - 1))
    }

    private func verticalDrag(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard isPagingEnabled,
                      abs(value.translation.height) >= abs(value.translation.width) else { return }
                rawDragTranslation = value.translation.height
                let isBeyondFirst = currentIndex == 0 && value.translation.height > 0
                let isBeyondLast = currentIndex == items.count - 1 && value.translation.height < 0
                let resistance = isBeyondFirst || isBeyondLast ? ReelPagerMotion.edgeResistance : 1
                let limitedTranslation = min(
                    max(value.translation.height, -pageHeight),
                    pageHeight
                )
                motion.updateDrag(
                    translation: limitedTranslation,
                    at: value.time,
                    resistance: resistance
                )
            }
            .onEnded { value in
                guard isPagingEnabled,
                      abs(value.translation.height) >= abs(value.translation.width),
                      motion.isDragging else { return }
                rawDragTranslation = value.translation.height
                finishDrag(pageHeight: pageHeight)
            }
    }

    private func finishDrag(pageHeight: CGFloat) {
        let releaseVelocity = motion.endDrag()
        let distanceThreshold = pageHeight * ReelPagerMotion.pageChangeDistanceRatio

        if currentIndex == 0,
           rawDragTranslation >= ReelPagerMotion.refreshDistance,
           let onRefresh,
           !isRefreshing {
            settle(to: currentIndex, pageHeight: pageHeight, releaseVelocity: releaseVelocity)
            isRefreshing = true
            Task { @MainActor in
                let succeeded = await onRefresh()
                isRefreshing = false
                if succeeded { synchronizeCurrentItem(resetToFirst: true) }
            }
            rawDragTranslation = 0
            return
        }

        let shouldMoveNext = currentIndex < items.count - 1 && (
            motion.offset <= -distanceThreshold || releaseVelocity <= -ReelPagerMotion.flickVelocity
        )
        let shouldMovePrevious = currentIndex > 0 && (
            motion.offset >= distanceThreshold || releaseVelocity >= ReelPagerMotion.flickVelocity
        )
        let targetIndex = shouldMoveNext
            ? currentIndex + 1
            : (shouldMovePrevious ? currentIndex - 1 : currentIndex)
        settle(to: targetIndex, pageHeight: pageHeight, releaseVelocity: releaseVelocity)
        rawDragTranslation = 0
    }

    private func settleByAccessibility(delta: Int, pageHeight: CGFloat) {
        guard isPagingEnabled else { return }
        let targetIndex = min(max(currentIndex + delta, 0), items.count - 1)
        guard targetIndex != currentIndex else { return }
        settle(
            to: targetIndex,
            pageHeight: pageHeight,
            releaseVelocity: ReelPagerMotion.startingVelocity
        )
    }

    private func settle(to targetIndex: Int, pageHeight: CGFloat, releaseVelocity: CGFloat) {
        guard items.indices.contains(targetIndex) else {
            motion.reset()
            return
        }
        let targetOffset = CGFloat(currentIndex - targetIndex) * pageHeight
        motion.settle(
            to: targetOffset,
            releaseVelocity: releaseVelocity,
            reduceMotion: reduceMotion
        ) {
            currentIndex = targetIndex
            currentID = items[targetIndex].id
            motion.reset()
            reportCurrentPageIfNeeded()
        }
    }

    private func synchronizeCurrentItem(resetToFirst: Bool) {
        guard !items.isEmpty else {
            currentIndex = 0
            currentID = nil
            motion.reset()
            return
        }

        let nextIndex: Int
        if resetToFirst {
            nextIndex = 0
        } else if let currentID,
                  let preservedIndex = items.firstIndex(where: { $0.id == currentID }) {
            nextIndex = preservedIndex
        } else {
            nextIndex = min(currentIndex, items.count - 1)
        }

        currentIndex = nextIndex
        currentID = items[nextIndex].id
        motion.reset()
        reportCurrentPageIfNeeded()
    }

    private func reportCurrentPageIfNeeded() {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        guard lastReportedID != item.id else { return }
        lastReportedID = item.id
        onPageChanged(item)
    }
}

private struct ArtworkCard: View {
    let artwork: Artwork
    let credentials: PixivSessionCredentials
    let isLiked: Bool
    let isLikePending: Bool
    let isSaved: Bool
    let isSavePending: Bool
    let onLike: () -> Void
    let onSave: () -> Void
    let onCreatorTap: () -> Void
    let onTagTap: (String) -> Void
    let onScrollLockChanged: (Bool) -> Void
    let onMangaViewerChanged: (Bool) -> Void
    @State private var isHUDVisible = true
    @State private var isMangaViewerActive = false
    @State private var imageSaveState: ArtworkImageSaveState = .idle
    @State private var imageSaveError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            if isMangaViewerActive {
                InlineMangaViewer(
                    artwork: artwork,
                    credentials: credentials,
                    onExit: exitMangaViewer
                )
                .transition(.opacity)
            } else {
                ArtworkVisual(artwork: artwork, credentials: credentials)
                    .contentShape(Rectangle())
                    .overlay {
                        MultiTapGestureView(
                            onSingleTap: handleArtworkTap,
                            onDoubleTap: onSave,
                            onTripleTap: onLike
                        )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        handleArtworkTap()
                    }
                    .accessibilityAction(named: "ブックマーク") {
                        onSave()
                    }
                    .accessibilityAction(named: "いいね") {
                        onLike()
                    }
                    .accessibilityLabel(artwork.title)
                    .accessibilityHint(
                        artwork.kind == "manga" && artwork.pageCount > 1
                            ? "1回タップで漫画ビューワー、2回でブックマーク、3回でいいねします"
                            : "1回タップでHUD切り替え、2回でブックマーク、3回でいいねします"
                    )
            }

            if isHUDVisible {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.08), .black.opacity(0.93)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .transition(.opacity)

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: onCreatorTap) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.2))

                                    if let profileImageURL = artwork.profileImageURL {
                                        PixivImageView(
                                            url: profileImageURL,
                                            credentials: credentials,
                                            contentMode: .fill
                                        )
                                        .clipShape(Circle())
                                    } else {
                                        Text(String(artwork.creator.prefix(1)))
                                            .font(.subheadline.weight(.bold))
                                    }
                                }
                                .frame(width: 34, height: 34)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artwork.creator)
                                        .font(.subheadline.weight(.bold))
                                    Text(artwork.handle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(artwork.creator)のプロフィールを開く")

                        Text(artwork.title)
                            .font(.title2.weight(.bold))
                            .lineLimit(2)
                            .allowsHitTesting(false)

                        HStack(spacing: 6) {
                            ForEach(artwork.tags.prefix(3), id: \.self) { tag in
                                Button {
                                    onTagTap(tag)
                                } label: {
                                        Text("#\(tag)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.white.opacity(0.78))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(tag)を検索")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ActionRail(
                        artwork: artwork,
                        isLiked: isLiked,
                        isLikePending: isLikePending,
                        isSaved: isSaved,
                        isSavePending: isSavePending,
                        imageSaveState: imageSaveState,
                        onLike: onLike,
                        onSave: onSave,
                        onImageSave: saveImageToPhotos
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .onChange(of: locksVerticalScroll) {
            onScrollLockChanged(locksVerticalScroll)
        }
        .onChange(of: isMangaViewerActive) {
            onMangaViewerChanged(isMangaViewerActive)
        }
        .onDisappear {
            onScrollLockChanged(false)
            onMangaViewerChanged(false)
        }
        .alert("画像を保存できませんでした", isPresented: Binding(
            get: { imageSaveError != nil },
            set: { if !$0 { imageSaveError = nil } }
        )) {
            Button("閉じる", role: .cancel) { imageSaveError = nil }
        } message: {
            Text(imageSaveError ?? "もう一度お試しください")
        }
    }

    private var locksVerticalScroll: Bool {
        !isHUDVisible || isMangaViewerActive
    }

    private func handleArtworkTap() {
        withAnimation(.easeOut(duration: 0.18)) {
            if artwork.kind == "manga" && artwork.pageCount > 1 {
                isHUDVisible = false
                isMangaViewerActive = true
            } else {
                isHUDVisible.toggle()
            }
        }
    }

    private func exitMangaViewer() {
        withAnimation(.easeOut(duration: 0.18)) {
            isMangaViewerActive = false
            isHUDVisible = true
        }
    }

    private func saveImageToPhotos() {
        guard imageSaveState == .idle else { return }
        imageSaveState = .saving

        Task { @MainActor in
            do {
                let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard authorization == .authorized || authorization == .limited else {
                    throw ArtworkImageSaveError.photoAccessDenied
                }

                let detail = try await PixivAPIClient(credentials: credentials)
                    .fetchArtworkDetail(for: artwork)
                guard let imageURL = detail.pages.first?.url,
                      let image = await PixivImageRepository.shared.image(
                        for: imageURL,
                        credentials: credentials
                      ) else {
                    throw ArtworkImageSaveError.imageUnavailable
                }

                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                imageSaveState = .saved
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .seconds(1.5))
                imageSaveState = .idle
            } catch {
                imageSaveState = .idle
                imageSaveError = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

private enum ArtworkImageSaveState: Equatable {
    case idle
    case saving
    case saved
}

private enum ArtworkImageSaveError: LocalizedError {
    case photoAccessDenied
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            return "写真への追加が許可されていません。設定から写真へのアクセスを許可してください。"
        case .imageUnavailable:
            return "保存する画像を取得できませんでした。"
        }
    }
}

private final class StrictTapGestureRecognizer: UITapGestureRecognizer {
    var maximumMovement: CGFloat = 4
    var onMovementExceeded: (() -> Void)?
    private var initialLocation: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        initialLocation = touches.first.map { $0.location(in: view) }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let initialLocation,
           let currentLocation = touches.first.map({ $0.location(in: view) }),
           hypot(currentLocation.x - initialLocation.x, currentLocation.y - initialLocation.y) > maximumMovement {
            onMovementExceeded?()
            state = .failed
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onMovementExceeded?()
        super.touchesCancelled(touches, with: event)
    }

    override func reset() {
        initialLocation = nil
        super.reset()
    }
}

private struct MultiTapGestureView: UIViewRepresentable {
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onTripleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSingleTap: onSingleTap,
            onDoubleTap: onDoubleTap,
            onTripleTap: onTripleTap
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let tapRecognizer = StrictTapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tapRecognizer.delegate = context.coordinator
        tapRecognizer.onMovementExceeded = context.coordinator.cancelPendingTapResolution
        tapRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(tapRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onTripleTap = onTripleTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSingleTap: () -> Void
        var onDoubleTap: () -> Void
        var onTripleTap: () -> Void
        private var tapCount = 0
        private var pendingResolution: DispatchWorkItem?
        private let resolutionDelay: TimeInterval = 0.22

        init(
            onSingleTap: @escaping () -> Void,
            onDoubleTap: @escaping () -> Void,
            onTripleTap: @escaping () -> Void
        ) {
            self.onSingleTap = onSingleTap
            self.onDoubleTap = onDoubleTap
            self.onTripleTap = onTripleTap
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        func cancelPendingTapResolution() {
            pendingResolution?.cancel()
            pendingResolution = nil
            tapCount = 0
        }

        @objc func handleTap() {
            pendingResolution?.cancel()
            tapCount += 1

            if tapCount >= 3 {
                tapCount = 0
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onTripleTap()
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let resolvedTapCount = tapCount
                tapCount = 0

                if resolvedTapCount == 2 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDoubleTap()
                } else {
                    onSingleTap()
                }
            }
            pendingResolution = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + resolutionDelay, execute: workItem)
        }
    }
}

private struct InlineMangaViewer: View {
    let artwork: Artwork
    let credentials: PixivSessionCredentials
    let onExit: () -> Void
    @State private var pages: [PixivArtworkPage] = []
    @State private var currentPageID: String?
    @State private var errorMessage: String?

    private var currentPageIndex: Int {
        guard let currentPageID,
              let index = pages.firstIndex(where: { $0.id == currentPageID }) else { return 0 }
        return index
    }

    var body: some View {
        ZStack {
            Color.black

            if !pages.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages) { page in
                            PixivImageView(
                                url: page.url,
                                credentials: credentials,
                                contentMode: .fit
                            )
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollPosition(id: $currentPageID)
                .onChange(of: currentPageID) {
                    prefetchCurrentPageAndNextThree()
                }
                .onTapGesture(perform: onExit)
                .accessibilityLabel("漫画ビューワー")
                .accessibilityHint("左右にスワイプしてページを切り替えます。タップで通常表示に戻ります")
                .accessibilityAction(named: "通常表示に戻る", onExit)
            } else if let errorMessage {
                ContentUnavailableView(
                    "漫画を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(errorMessage)\nタップして戻る")
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onExit)
            } else {
                ProgressView("漫画を読み込み中…")
                    .tint(.white)
            }
        }
        .overlay(alignment: .bottom) {
            if !pages.isEmpty {
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(currentPageIndex + 1),
                        total: Double(max(pages.count, 1))
                    )
                    .tint(ZoneTheme.accent)

                    Text("\(currentPageIndex + 1) / \(pages.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: artwork.id) {
            await loadPages()
        }
    }

    @MainActor
    private func loadPages() async {
        do {
            let detail = try await PixivAPIClient(credentials: credentials)
                .fetchArtworkDetail(for: artwork)
            pages = detail.pages
            currentPageID = pages.first?.id
            prefetchCurrentPageAndNextThree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func prefetchCurrentPageAndNextThree() {
        guard !pages.isEmpty else { return }
        let upperBound = min(currentPageIndex + 4, pages.count)
        let urls = pages[currentPageIndex..<upperBound].map(\.url)
        PixivImageRepository.shared.prefetch(urls: urls, credentials: credentials)
    }
}

private struct ActionRail: View {
    let artwork: Artwork
    let isLiked: Bool
    let isLikePending: Bool
    let isSaved: Bool
    let isSavePending: Bool
    let imageSaveState: ArtworkImageSaveState
    let onLike: () -> Void
    let onSave: () -> Void
    let onImageSave: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onLike) {
                if isLikePending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.24), in: Circle())
                } else {
                    RailButton(
                        icon: isLiked ? "heart.fill" : "heart",
                        label: nil,
                        tint: isLiked ? .pink : .white
                    )
                }
            }
            .disabled(isLiked || isLikePending)
            .accessibilityLabel(isLikePending ? "いいね処理中" : (isLiked ? "いいね済み" : "いいね"))

            Button(action: onSave) {
                if isSavePending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.24), in: Circle())
                } else {
                    RailButton(
                        icon: isSaved ? "bookmark.fill" : "bookmark",
                        label: nil,
                        tint: isSaved ? ZoneTheme.accent : .white
                    )
                }
            }
            .disabled(isSavePending || !artwork.isBookmarkable)
            .accessibilityLabel(isSavePending ? "保存処理中" : (isSaved ? "保存を取り消す" : "保存"))

            Button(action: onImageSave) {
                switch imageSaveState {
                case .idle:
                    RailButton(icon: "arrow.down.to.line", label: "画像保存")
                case .saving:
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.24), in: Circle())
                case .saved:
                    RailButton(icon: "checkmark", label: "保存済み", tint: .green)
                }
            }
            .disabled(imageSaveState != .idle)
            .accessibilityLabel(
                imageSaveState == .saving
                    ? "画像を保存中"
                    : (imageSaveState == .saved ? "画像を保存しました" : "画像を写真に保存")
            )

            ShareLink(item: "https://www.pixiv.net/artworks/\(artwork.id)") {
                RailButton(icon: "paperplane", label: "共有")
            }
            .accessibilityLabel("作品を共有")
        }
    }
}

private struct RailButton: View {
    let icon: String
    let label: String?
    var tint: Color = .white

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.24), in: Circle())
            if let label {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }
}

// MARK: - Discover and Library

struct DiscoverView: View {
    @ObservedObject var store: FeedStore
    let credentials: PixivSessionCredentials
    @Binding var requestedTag: String?
    let scrollToTopToken: Int
    let onMangaViewerChanged: (Bool) -> Void
    @State private var searchText = ""
    @State private var submittedTag: String?
    @State private var searchResults: [Artwork] = []
    @State private var suggestions: [PixivTagSuggestion] = []
    @State private var isSearching = false
    @State private var isLoadingSearchMore = false
    @State private var searchError: String?
    @State private var nextSearchPage = 1
    @State private var searchLastPage = 1
    @State private var selectedUser: PixivUserReference?
    @State private var searchKind: ArtworkSearchKind = .illustrations
    @State private var submittedSearchKind: ArtworkSearchKind = .illustrations
    @State private var searchMode: ArtworkSearchMode = .all
    @State private var submittedSearchMode: ArtworkSearchMode = .all
    @State private var searchOrder: ArtworkSearchOrder = .latest
    @State private var submittedSearchOrder: ArtworkSearchOrder = .latest
    @State private var scrollLockedArtworkID: String?
    @State private var currentArtworkID: String?
    @FocusState private var isSearchFieldFocused: Bool

    private var displayedArtworks: [Artwork] {
        submittedTag == nil ? store.artworks : searchResults
    }

    private var searchReelResetKey: AnyHashable {
        AnyHashable([
            submittedTag ?? "__home_feed__",
            submittedSearchKind.rawValue,
            submittedSearchMode.rawValue,
            submittedSearchOrder.rawValue,
            String(scrollToTopToken)
        ].joined(separator: "|"))
    }

    var body: some View {
        Group {
            if isSearching {
                ProgressView("#\(submittedTag ?? searchText) を検索中…")
            } else if let searchError {
                ContentUnavailableView {
                    Label("検索できませんでした", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(searchError)
                } actions: {
                    Button("もう一度試す") {
                        Task { await submitSearch() }
                    }
                }
            } else if submittedTag != nil && searchResults.isEmpty {
                ContentUnavailableView.search(text: submittedTag ?? "")
            } else {
                ReelPager(
                    items: displayedArtworks,
                    currentID: $currentArtworkID,
                    resetKey: searchReelResetKey,
                    isPagingEnabled: scrollLockedArtworkID == nil,
                    onPageChanged: { artwork in
                        Task {
                            if submittedTag == nil {
                                await store.loadNextPageIfNeeded(after: artwork, using: credentials)
                            } else {
                                await loadNextSearchPageIfNeeded(after: artwork)
                            }
                        }
                    },
                    onRefresh: nil
                ) { artwork in
                    ArtworkCard(
                        artwork: artwork,
                        credentials: credentials,
                        isLiked: store.isLiked(artwork),
                        isLikePending: store.isLikePending(artwork),
                        isSaved: store.isSaved(artwork),
                        isSavePending: store.isBookmarkPending(artwork),
                        onLike: {
                            Task { await store.like(artwork, using: credentials) }
                        },
                        onSave: {
                            Task { await store.toggleBookmark(artwork, using: credentials) }
                        },
                        onCreatorTap: { selectedUser = PixivUserReference(artwork: artwork) },
                        onTagTap: beginTagSearch,
                        onScrollLockChanged: { isLocked in
                            updateScrollLock(for: artwork.id, isLocked: isLocked)
                        },
                        onMangaViewerChanged: onMangaViewerChanged
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .overlay(alignment: .bottom) {
            if isLoadingSearchMore || (submittedTag == nil && store.isLoadingMore) {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            searchHeader
        }
        .task(id: searchText) {
            await updateSuggestions()
        }
        .task(id: requestedTag) {
            guard let requestedTag else { return }
            await beginRequestedTagSearch(requestedTag)
        }
        .onChange(of: searchText) {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submittedTag = nil
                searchResults = []
                suggestions = []
                searchError = nil
                nextSearchPage = 1
                searchLastPage = 1
                isLoadingSearchMore = false
                currentArtworkID = nil
            }
        }
        .onChange(of: searchKind) {
            guard let submittedTag else { return }
            Task { await submitSearch(tag: submittedTag) }
        }
        .onChange(of: searchMode) {
            guard let submittedTag else { return }
            Task { await submitSearch(tag: submittedTag) }
        }
        .onChange(of: searchOrder) {
            guard let submittedTag else { return }
            Task { await submitSearch(tag: submittedTag) }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedUser) { user in
            PixivUserProfileView(
                user: user,
                store: store,
                credentials: credentials,
                onSearchTag: { tag in
                    selectedUser = nil
                    requestedTag = tag
                }
            )
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("タグを検索", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        isSearchFieldFocused = false
                        Task { await submitSearch() }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("検索文字を消去")
                }

                Menu {
                    Section("作品の種類") {
                        ForEach(ArtworkSearchKind.allCases) { kind in
                            Button {
                                searchKind = kind
                            } label: {
                                if searchKind == kind {
                                    Label(kind.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(kind.rawValue)
                                }
                            }
                        }
                    }

                    Section("年齢区分") {
                        ForEach(ArtworkSearchMode.allCases) { mode in
                            Button {
                                searchMode = mode
                            } label: {
                                if searchMode == mode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    }

                    Section("並び順") {
                        ForEach(ArtworkSearchOrder.allCases) { order in
                            Button {
                                searchOrder = order
                            } label: {
                                if searchOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: searchKind == .illustrations ? "photo" : "book.pages")
                        Text(searchMode.title)
                            .font(.caption2.weight(.semibold))
                        if searchOrder == .popular {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(ZoneTheme.accent)
                    .frame(minWidth: 52, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("検索オプション")
                .accessibilityValue("\(searchKind.rawValue)、\(searchMode.title)、\(searchOrder.rawValue)")

                Button {
                    isSearchFieldFocused = false
                    Task { await submitSearch() }
                } label: {
                    Text("検索")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ZoneTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("タグを検索")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(isSearchFieldFocused ? 0.28 : 0.1), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if isSearchFieldFocused && !suggestions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                replaceActiveTag(with: suggestion.tagName)
                            } label: {
                                HStack {
                                    Label(suggestion.tagName, systemImage: "number")
                                    Spacer()
                                    if let accessCount = suggestion.accessCountValue {
                                        Text(compactNumber(accessCount))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .accessibilityLabel(
                                suggestion.accessCountValue.map {
                                    "\(suggestion.tagName)、\(compactNumber($0))件"
                                } ?? suggestion.tagName
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    @MainActor
    private func updateSuggestions() async {
        let keyword = activeTagKeyword
        guard !keyword.isEmpty else {
            suggestions = []
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
            let fetchedSuggestions = try await PixivAPIClient(credentials: credentials)
                .fetchTagSuggestions(keyword: keyword)
            guard !Task.isCancelled else { return }
            suggestions = Array(fetchedSuggestions.prefix(10))
        } catch is CancellationError {
            return
        } catch {
            suggestions = []
        }
    }

    private var activeTagKeyword: String {
        guard let lastWhitespace = searchText.lastIndex(where: { $0.isWhitespace }) else {
            return searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let start = searchText.index(after: lastWhitespace)
        return String(searchText[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replaceActiveTag(with tag: String) {
        let prefix: String
        if let lastWhitespace = searchText.lastIndex(where: { $0.isWhitespace }) {
            prefix = String(searchText[...lastWhitespace])
        } else {
            prefix = ""
        }

        searchText = prefix + tag + " "
        suggestions = []
        isSearchFieldFocused = true
    }

    private func beginTagSearch(_ tag: String) {
        requestedTag = tag
    }

    @MainActor
    private func beginRequestedTagSearch(_ tag: String) async {
        searchText = tag
        isSearchFieldFocused = false
        await submitSearch(tag: tag)
        if requestedTag == tag {
            requestedTag = nil
        }
    }

    @MainActor
    private func submitSearch(tag: String? = nil) async {
        let keyword = (tag ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        let requestedKind = searchKind
        let requestedMode = searchMode
        let requestedOrder = searchOrder

        submittedTag = keyword
        submittedSearchKind = requestedKind
        submittedSearchMode = requestedMode
        submittedSearchOrder = requestedOrder
        currentArtworkID = nil
        isSearching = true
        isLoadingSearchMore = false
        searchError = nil
        suggestions = []
        defer { isSearching = false }

        do {
            let client = PixivAPIClient(credentials: credentials)
            var loadedArtworks: [Artwork] = []
            var lastPage = 1
            var nextPage = 1

            if requestedOrder == .popular {
                loadedArtworks = try await loadPopularSearchResults(
                    keyword: keyword,
                    client: client,
                    kind: requestedKind,
                    mode: requestedMode
                )
                nextPage = 2
            } else {
                for requestedPage in 1...3 {
                    let page = try await client.searchArtworks(
                        tag: keyword,
                        page: requestedPage,
                        kind: requestedKind,
                        mode: requestedMode
                    )
                    appendUnique(page.artworks, to: &loadedArtworks)
                    lastPage = max(page.lastPage, requestedPage)
                    nextPage = requestedPage + 1

                    guard requestedPage < lastPage else { break }
                }
            }

            guard submittedTag == keyword,
                  submittedSearchKind == requestedKind,
                  submittedSearchMode == requestedMode,
                  submittedSearchOrder == requestedOrder else { return }
            searchResults = loadedArtworks
            store.registerBookmarkState(from: loadedArtworks)
            searchLastPage = lastPage
            nextSearchPage = nextPage
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
    }

    @MainActor
    private func loadNextSearchPageIfNeeded(after artwork: Artwork) async {
        guard let submittedTag,
              submittedSearchOrder == .latest,
              !isSearching,
              !isLoadingSearchMore,
              nextSearchPage <= searchLastPage,
              let index = searchResults.firstIndex(where: { $0.id == artwork.id }),
              searchResults.count - index <= 5 else { return }

        let requestedPage = nextSearchPage
        let requestedKind = submittedSearchKind
        let requestedMode = submittedSearchMode
        isLoadingSearchMore = true
        defer { isLoadingSearchMore = false }

        do {
            let page = try await PixivAPIClient(credentials: credentials)
                .searchArtworks(
                    tag: submittedTag,
                    page: requestedPage,
                    kind: requestedKind,
                    mode: requestedMode
                )
            guard self.submittedTag == submittedTag,
                  submittedSearchKind == requestedKind,
                  submittedSearchMode == requestedMode else { return }
            appendUnique(page.artworks, to: &searchResults)
            store.registerBookmarkState(from: page.artworks)
            searchLastPage = max(page.lastPage, requestedPage)
            nextSearchPage = requestedPage + 1
        } catch is CancellationError {
            return
        } catch {
            // 既に表示している検索結果は残し、次の表示時に再試行する。
        }
    }

    private func appendUnique(_ newArtworks: [Artwork], to destination: inout [Artwork]) {
        var existingIDs = Set(destination.map(\.id))
        destination.append(contentsOf: newArtworks.filter { existingIDs.insert($0.id).inserted })
    }

    private func updateScrollLock(for artworkID: String, isLocked: Bool) {
        if isLocked {
            scrollLockedArtworkID = artworkID
        } else if scrollLockedArtworkID == artworkID {
            scrollLockedArtworkID = nil
        }
    }

    private func loadPopularSearchResults(
        keyword: String,
        client: PixivAPIClient,
        kind: ArtworkSearchKind,
        mode: ArtworkSearchMode
    ) async throws -> [Artwork] {
        var results: [Artwork] = []

        for threshold in Self.popularityThresholds {
            try Task.checkCancellation()
            let page = try await client.searchArtworks(
                tag: "\(keyword) \(threshold)users入り",
                page: 1,
                kind: kind,
                mode: mode
            )
            let matchingArtworks = page.artworks.filter {
                popularityRank(for: $0) == threshold
            }
            appendUnique(matchingArtworks, to: &results)
        }

        return results
    }

    private func popularityRank(for artwork: Artwork) -> Int {
        Self.popularityThresholds.first { threshold in
            artwork.tags.contains { $0.contains("\(threshold)users入り") }
        } ?? 0
    }

    private static let popularityThresholds = [
        100_000, 50_000, 30_000, 10_000, 5_000, 1_000, 500, 100, 50
    ]
}

struct LibraryView: View {
    @ObservedObject var store: FeedStore
    let credentials: PixivSessionCredentials
    let onSearchTag: (String) -> Void
    let scrollToTopToken: Int
    let onMangaViewerChanged: (Bool) -> Void
    @State private var selectedUser: PixivUserReference?
    @State private var scrollLockedArtworkID: String?
    @State private var currentArtworkID: String?

    var body: some View {
        Group {
            if credentials.userID == nil || (store.isLoadingBookmarks && store.savedArtworks.isEmpty) {
                ProgressView("ブックマークを読み込み中…")
            } else if let bookmarkLoadError = store.bookmarkLoadError,
                      store.savedArtworks.isEmpty {
                ContentUnavailableView {
                    Label("ブックマークを読み込めませんでした", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(bookmarkLoadError)
                } actions: {
                    Button("もう一度試す") {
                        Task { await loadBookmarks() }
                    }
                }
            } else if store.savedArtworks.isEmpty {
                ContentUnavailableView(
                    "保存した作品はありません",
                    systemImage: "bookmark",
                    description: Text("Pixivでブックマークした作品がここに表示されます")
                )
            } else {
                ReelPager(
                    items: store.savedArtworks,
                    currentID: $currentArtworkID,
                    resetKey: AnyHashable("\(credentials.userID ?? "")|\(scrollToTopToken)"),
                    isPagingEnabled: scrollLockedArtworkID == nil,
                    onPageChanged: { artwork in
                        Task {
                            await store.loadNextBookmarksIfNeeded(
                                after: artwork,
                                using: credentials
                            )
                        }
                    },
                    onRefresh: nil
                ) { artwork in
                    ArtworkCard(
                        artwork: artwork,
                        credentials: credentials,
                        isLiked: store.isLiked(artwork),
                        isLikePending: store.isLikePending(artwork),
                        isSaved: store.isSaved(artwork),
                        isSavePending: store.isBookmarkPending(artwork),
                        onLike: {
                            Task { await store.like(artwork, using: credentials) }
                        },
                        onSave: {
                            Task { await store.toggleBookmark(artwork, using: credentials) }
                        },
                        onCreatorTap: { selectedUser = PixivUserReference(artwork: artwork) },
                        onTagTap: onSearchTag,
                        onScrollLockChanged: { isLocked in
                            updateScrollLock(for: artwork.id, isLocked: isLocked)
                        },
                        onMangaViewerChanged: onMangaViewerChanged
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .overlay(alignment: .bottom) {
            if store.isLoadingMoreBookmarks {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(ZoneTheme.accent)
                Text("保存")
                    .font(.headline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .task(id: credentials.userID) {
            await loadBookmarks()
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedUser) { user in
            PixivUserProfileView(
                user: user,
                store: store,
                credentials: credentials,
                onSearchTag: { tag in
                    selectedUser = nil
                    onSearchTag(tag)
                }
            )
        }
    }

    @MainActor
    private func loadBookmarks() async {
        guard let userID = credentials.userID else { return }
        await store.loadBookmarks(userID: userID, using: credentials)
    }

    private func updateScrollLock(for artworkID: String, isLocked: Bool) {
        if isLocked {
            scrollLockedArtworkID = artworkID
        } else if scrollLockedArtworkID == artworkID {
            scrollLockedArtworkID = nil
        }
    }
}

private struct PixivUserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let user: PixivUserReference
    @ObservedObject var store: FeedStore
    let credentials: PixivSessionCredentials
    let onSearchTag: (String) -> Void
    @State private var profile: PixivUserProfile?
    @State private var artworkIDs: [String] = []
    @State private var artworks: [Artwork] = []
    @State private var nextArtworkIndex = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var isShowingPixivProfile = false
    @State private var pendingFollowAction: PixivFollowAutomationAction?
    @State private var followOverride: Bool?
    @State private var followError: String?
    @State private var scrollLockedArtworkID: String?
    @State private var currentArtworkID: String?

    private let pageSize = 30

    private var isFollowed: Bool {
        followOverride ?? profile?.isFollowed ?? false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                profileHeader

                Divider()
                    .overlay(.white.opacity(0.08))

                Group {
                    if isLoading && artworks.isEmpty {
                        ProgressView("作品を読み込み中…")
                    } else if let loadError, artworks.isEmpty {
                        ContentUnavailableView {
                            Label("プロフィールを読み込めませんでした", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(loadError)
                        } actions: {
                            Button("もう一度試す") {
                                Task { await load() }
                            }
                        }
                    } else if artworks.isEmpty {
                        ContentUnavailableView(
                            "公開作品はありません",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    } else {
                        ReelPager(
                            items: artworks,
                            currentID: $currentArtworkID,
                            resetKey: AnyHashable(user.id),
                            isPagingEnabled: scrollLockedArtworkID == nil,
                            onPageChanged: { artwork in
                                Task { await loadNextIfNeeded(after: artwork) }
                            },
                            onRefresh: nil
                        ) { artwork in
                            ArtworkCard(
                                artwork: artwork,
                                credentials: credentials,
                                isLiked: store.isLiked(artwork),
                                isLikePending: store.isLikePending(artwork),
                                isSaved: store.isSaved(artwork),
                                isSavePending: store.isBookmarkPending(artwork),
                                onLike: {
                                    Task { await store.like(artwork, using: credentials) }
                                },
                                onSave: {
                                    Task { await store.toggleBookmark(artwork, using: credentials) }
                                },
                                onCreatorTap: {},
                                onTagTap: { tag in
                                    dismiss()
                                    onSearchTag(tag)
                                },
                                onScrollLockChanged: { isLocked in
                                    updateScrollLock(for: artwork.id, isLocked: isLocked)
                                },
                                onMangaViewerChanged: { _ in }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .overlay(alignment: .bottom) {
                    if isLoadingMore {
                        ProgressView()
                            .tint(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                }
            }
            .background(.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: user.id) {
            await load()
        }
        .sheet(isPresented: $isShowingPixivProfile) {
            NavigationStack {
                PixivAuthenticatedWebView(
                    url: URL(string: "https://www.pixiv.net/users/\(user.id)")!,
                    credentials: credentials
                )
                .navigationTitle(profile?.name ?? user.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { isShowingPixivProfile = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .background {
            if let pendingFollowAction {
                PixivFollowAutomationWebView(
                    userID: user.id,
                    credentials: credentials,
                    action: pendingFollowAction,
                    onResult: handleFollowResult
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .alert("フォロー状態を変更できませんでした", isPresented: Binding(
            get: { followError != nil },
            set: { if !$0 { followError = nil } }
        )) {
            Button("Pixivで開く") {
                followError = nil
                isShowingPixivProfile = true
            }
            Button("閉じる", role: .cancel) { followError = nil }
        } message: {
            Text(followError ?? "もう一度お試しください")
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(ZoneTheme.accent.opacity(0.22))
                    Image(systemName: "person.fill")
                        .foregroundStyle(ZoneTheme.accent)

                    if let imageURL = profile?.preferredImageURL ?? user.profileImageURL {
                        PixivImageView(url: imageURL, credentials: credentials, contentMode: .fill)
                            .clipShape(Circle())
                    }
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile?.name ?? user.name)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text("@\(user.id)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    guard pendingFollowAction == nil else { return }
                    followError = nil
                    pendingFollowAction = isFollowed ? .unfollow : .follow
                } label: {
                    Group {
                        if pendingFollowAction != nil {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text(isFollowed ? "フォロー解除" : "フォロー")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minWidth: 92, minHeight: 40)
                    .background(ZoneTheme.accent, in: Capsule())
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(pendingFollowAction != nil)
                .accessibilityLabel(pendingFollowAction != nil ? "フォロー状態を変更中" : (isFollowed ? "フォロー解除" : "フォロー"))
                .accessibilityHint(isFollowed ? "Pixiv上でこのユーザーのフォローを解除します" : "Pixiv上でこのユーザーをフォローします")
            }

            if let profile {
                Text("フォロー中 \(profile.following)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        artworkIDs = []
        artworks = []
        nextArtworkIndex = 0
        defer { isLoading = false }

        let client = PixivAPIClient(credentials: credentials)
        do {
            profile = try await client.fetchUserProfile(userID: user.id)
        } catch {
            pixivAPILogger.error("user profile failed user=\(user.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }

        do {
            artworkIDs = try await client.fetchUserArtworkIDs(userID: user.id)
            await loadNextBatch()
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func handleFollowResult(_ result: PixivFollowAutomationResult) {
        pendingFollowAction = nil
        switch result {
        case .followed, .alreadyFollowing:
            followOverride = true
        case .unfollowed, .alreadyNotFollowing:
            followOverride = false
        case .failed(let message):
            followError = message
        }
    }

    private func updateScrollLock(for artworkID: String, isLocked: Bool) {
        if isLocked {
            scrollLockedArtworkID = artworkID
        } else if scrollLockedArtworkID == artworkID {
            scrollLockedArtworkID = nil
        }
    }

    @MainActor
    private func loadNextIfNeeded(after artwork: Artwork) async {
        guard let index = artworks.firstIndex(where: { $0.id == artwork.id }),
              artworks.count - index <= 5 else { return }
        await loadNextBatch()
    }

    @MainActor
    private func loadNextBatch() async {
        guard !isLoadingMore, nextArtworkIndex < artworkIDs.count else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let endIndex = min(nextArtworkIndex + pageSize, artworkIDs.count)
        let requestedIDs = Array(artworkIDs[nextArtworkIndex..<endIndex])
        do {
            let page = try await PixivAPIClient(credentials: credentials).fetchUserArtworks(
                userID: user.id,
                ids: requestedIDs,
                isFirstPage: nextArtworkIndex == 0
            )
            var existingIDs = Set(artworks.map(\.id))
            artworks.append(contentsOf: page.filter { existingIDs.insert($0.id).inserted })
            store.registerBookmarkState(from: page)
            nextArtworkIndex = endIndex
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct MyPageView: View {
    let credentials: PixivSessionCredentials
    let extra: PixivUserExtra?
    let scrollToTopToken: Int
    let onLogout: () -> Void
    @State private var profile: PixivUserProfile?
    @State private var isLoadingProfile = false
    @State private var profileError: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(ZoneTheme.accent.opacity(0.22))
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundStyle(ZoneTheme.accent)

                            if let imageURL = profile?.preferredImageURL {
                                PixivImageView(
                                    url: imageURL,
                                    credentials: credentials,
                                    contentMode: .fill
                                )
                                .clipShape(Circle())
                            }
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile?.name ?? (isLoadingProfile ? "読み込み中…" : "Pixivアカウント"))
                                .font(.headline)
                            Text(credentials.userID.map { "user ID: \($0)" } ?? "接続済み")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if profile?.premium == true {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Pixiv Premium")
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(profile?.name ?? "Pixivアカウント")。接続済み")
                    }
                    .id("my-page-top")

                    if let profile {
                        Section("プロフィール") {
                            if let comment = profile.comment, !comment.isEmpty {
                                Text(comment)
                            }
                            if let region = profile.region?.name {
                                Label(region, systemImage: "mappin.and.ellipse")
                            }
                            if let age = profile.age?.name {
                                Label(age, systemImage: "calendar")
                            }
                            if let gender = profile.gender?.name {
                                Label(gender, systemImage: "person")
                            }
                        }
                    } else if let profileError {
                        Section {
                            Label(profileError, systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let extra {
                        Section("つながり") {
                            LabeledContent("フォロー中", value: "\(extra.following)")
                            LabeledContent("フォロワー", value: "\(extra.followers)")
                            LabeledContent("マイピク", value: "\(extra.mypixivCount)")
                        }
                    }

                    Section {
                        NavigationLink {
                            SettingsView(onLogout: onLogout)
                        } label: {
                            Label("設定", systemImage: "gearshape")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(ZoneTheme.background)
                .navigationTitle("マイページ")
                .onChange(of: scrollToTopToken) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("my-page-top", anchor: .top)
                    }
                }
            }
        }
        .task(id: credentials.userID) {
            await loadProfile()
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func loadProfile() async {
        guard let userID = credentials.userID else { return }
        isLoadingProfile = true
        profileError = nil
        defer { isLoadingProfile = false }

        do {
            profile = try await PixivAPIClient(credentials: credentials)
                .fetchUserProfile(userID: userID)
        } catch {
            profileError = error.localizedDescription
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    let onLogout: () -> Void
    @State private var isConfirmingLogout = false

    var body: some View {
        Form {
            Section("Pixiv連携") {
                HStack {
                    Label("接続状態", systemImage: "person.crop.circle.badge.checkmark")
                    Spacer()
                    Text("接続済み")
                        .foregroundStyle(.secondary)
                }

                Text("Pixivのログインセッションを使って、streetフィードから作品を取得しています。セッション情報は端末のKeychainに保存されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://www.pixiv.net")!) {
                    Label("pixivを開く", systemImage: "arrow.up.right.square")
                }
            }

            Section("表示") {
                Label("縦スワイプで次の作品へ", systemImage: "rectangle.portrait.and.arrow.forward")
                Label("作品は保存・共有できます", systemImage: "bookmark.and.arrow.down")
            }

            Section {
                Button("ログアウト", role: .destructive) {
                    isConfirmingLogout = true
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } footer: {
                Text("端末に保存されたPixivのセッション情報を削除します。")
            }
        }
        .navigationTitle("設定")
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Pixivからログアウトしますか？",
            isPresented: $isConfirmingLogout,
            titleVisibility: .visible
        ) {
            Button("ログアウト", role: .destructive, action: onLogout)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("再度利用するにはPixivへのログインが必要です。")
        }
    }
}

private struct PixivArtworkDetail {
    let title: String
    let description: String
    let creator: String
    let handle: String
    let tags: [String]
    let likeCount: Int
    let bookmarkCount: Int
    let commentCount: Int
    let pages: [PixivArtworkPage]
}

private struct PixivArtworkPage: Identifiable {
    let id: String
    let url: URL
    let width: Int
    let height: Int

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(max(height, 1))
    }
}

// MARK: - Artwork preview

private struct ArtworkVisual: View {
    let artwork: Artwork
    let credentials: PixivSessionCredentials

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: artwork.palette,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: proxy.size.width * 0.78)
                    .blur(radius: 1)
                    .offset(x: proxy.size.width * 0.25, y: -proxy.size.height * 0.18)

                Circle()
                    .fill(.black.opacity(0.24))
                    .frame(width: proxy.size.width * 0.66)
                    .blur(radius: 2)
                    .offset(x: -proxy.size.width * 0.32, y: proxy.size.height * 0.21)

                Canvas { context, size in
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * 0.07, y: size.height * 0.74))
                    path.addCurve(
                        to: CGPoint(x: size.width * 0.93, y: size.height * 0.28),
                        control1: CGPoint(x: size.width * 0.32, y: size.height * 0.16),
                        control2: CGPoint(x: size.width * 0.63, y: size.height * 0.92)
                    )
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.48)),
                        style: StrokeStyle(lineWidth: max(2, size.width * 0.009), lineCap: .round)
                    )

                    let orb = Path(ellipseIn: CGRect(
                        x: size.width * 0.58,
                        y: size.height * 0.22,
                        width: size.width * 0.16,
                        height: size.width * 0.16
                    ))
                    context.fill(orb, with: .color(.white.opacity(0.78)))
                }

                VStack(spacing: 12) {
                    Image(systemName: artwork.symbol)
                        .font(.system(size: min(proxy.size.width * 0.17, 74), weight: .thin))
                        .symbolRenderingMode(.hierarchical)
                    Text("ILLUSTRATION")
                        .font(.caption2.weight(.bold))
                        .tracking(3)
                        .opacity(0.7)
                }
                .foregroundStyle(.white.opacity(0.82))
                .rotationEffect(.degrees(-8))

                if let imageURL = artwork.imageURL {
                    Color.black

                    PixivImageView(url: imageURL, credentials: credentials, contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct PixivImageView: View {
    let url: URL
    let credentials: PixivSessionCredentials
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        image = await PixivImageRepository.shared.image(for: url, credentials: credentials)
    }
}

@MainActor
private final class PixivImageRepository {
    static let shared = PixivImageRepository()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 16
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    func image(for url: URL, credentials: PixivSessionCredentials) async -> UIImage? {
        let key = cacheKey(for: url, credentials: credentials)

        if let cachedImage = cache.object(forKey: key as NSString) {
            return cachedImage
        }

        if let existingTask = inFlightTasks[key] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(credentials.cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else { return nil }
                return UIImage(data: data)
            } catch {
                return nil
            }
        }

        inFlightTasks[key] = task
        let loadedImage = await task.value
        inFlightTasks[key] = nil

        if let loadedImage {
            let cost = loadedImage.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(loadedImage, forKey: key as NSString, cost: cost)
        }

        return loadedImage
    }

    func prefetch(urls: [URL], credentials: PixivSessionCredentials) {
        for url in urls {
            Task {
                _ = await image(for: url, credentials: credentials)
            }
        }
    }

    private func cacheKey(for url: URL, credentials: PixivSessionCredentials) -> String {
        "\(credentials.savedAt.timeIntervalSinceReferenceDate)|\(url.absoluteString)"
    }
}

// MARK: - Onboarding and login

private struct OnboardingView: View {
    @ObservedObject var sessionStore: SessionStore
    let onOpenReviewDemo: () -> Void
    @State private var showingLogin = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.22), Color(red: 0.25, green: 0.13, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(ZoneTheme.accent.opacity(0.18))
                        .frame(width: 164, height: 164)
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 68, weight: .medium))
                        .foregroundStyle(ZoneTheme.accent)
                }
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("好きな作品を、\nもっと軽やかに")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("pixtopiaはPixivの作品をショート動画のように\n縦スワイプで楽しむビューアです")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showingLogin = true
                    } label: {
                        Label("Pixivにログイン", systemImage: "person.crop.circle.badge.arrow.right")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(ZoneTheme.accent, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .accessibilityHint("Pixivのログイン画面を開きます")

                    Button(action: onOpenReviewDemo) {
                        Label("審査用デモを試す", systemImage: "play.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityHint("ログインせずにローカルのサンプル作品で主要機能を確認します")

                    Text("ログイン情報は端末のKeychainに保存されます")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingLogin) {
            PixivLoginView { credentials in
                if sessionStore.save(credentials) {
                    showingLogin = false
                }
            }
        }
        .alert("ログイン情報を保存できませんでした", isPresented: Binding(
            get: { sessionStore.errorMessage != nil },
            set: { if !$0 { sessionStore.errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) { sessionStore.errorMessage = nil }
        } message: {
            Text(sessionStore.errorMessage ?? "もう一度お試しください")
        }
    }
}

// MARK: - App Review Demo

private struct ReviewDemoView: View {
    let onExit: () -> Void
    @State private var selectedTab = 0
    @State private var resetTokens = [0, 0, 0, 0]
    @State private var currentArtworkID: String?
    @State private var likedIDs = Set<String>()
    @State private var savedIDs: Set<String> = [ReviewDemoData.artworks[1].id]
    @State private var searchText = ""
    @State private var isMangaViewerActive = false

    private var visibleArtworks: [Artwork] {
        switch selectedTab {
        case 1:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return ReviewDemoData.artworks }
            return ReviewDemoData.artworks.filter { artwork in
                artwork.title.localizedCaseInsensitiveContains(query)
                    || artwork.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        case 2:
            return ReviewDemoData.artworks.filter { savedIDs.contains($0.id) }
        default:
            return ReviewDemoData.artworks
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            reviewDemoHeader

            if selectedTab == 3 {
                reviewDemoProfile
            } else {
                if selectedTab == 1 {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("サンプル作品を検索", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button("クリア") { searchText = "" }
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                }

                if visibleArtworks.isEmpty {
                    ContentUnavailableView(
                        selectedTab == 2 ? "保存した作品はありません" : "作品が見つかりません",
                        systemImage: selectedTab == 2 ? "bookmark" : "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ReelPager(
                        items: visibleArtworks,
                        currentID: $currentArtworkID,
                        resetKey: AnyHashable("\(selectedTab)|\(resetTokens[selectedTab])|\(searchText)"),
                        isPagingEnabled: !isMangaViewerActive,
                        onPageChanged: { _ in },
                        onRefresh: nil
                    ) { artwork in
                        ReviewDemoArtworkCard(
                            artwork: artwork,
                            isLiked: likedIDs.contains(artwork.id),
                            isSaved: savedIDs.contains(artwork.id),
                            onLike: { toggle(artwork.id, in: &likedIDs) },
                            onSave: { toggle(artwork.id, in: &savedIDs) },
                            onMangaViewerChanged: { isMangaViewerActive = $0 }
                        )
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isMangaViewerActive {
                ZoneBottomBar(
                    selectedTab: $selectedTab,
                    onReselect: { tab in resetTokens[tab] &+= 1 }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.18), value: isMangaViewerActive)
        .onChange(of: selectedTab) {
            currentArtworkID = nil
            isMangaViewerActive = false
        }
    }

    private var reviewDemoHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "triangle.fill")
                .foregroundStyle(ZoneTheme.accent)
            Text("PIXTOPIA")
                .font(.headline.weight(.black))
                .tracking(2)
            Text("DEMO")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ZoneTheme.accent.opacity(0.18), in: Capsule())
                .foregroundStyle(ZoneTheme.accent)

            Spacer()

            Button("終了", action: onExit)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("審査用デモを閉じてログイン画面へ戻ります")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var reviewDemoProfile: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(ZoneTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("審査用デモアカウント")
                            .font(.headline)
                        Text("外部アカウント未接続")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("デモについて") {
                Label("すべての作品はアプリ内で生成したサンプルです", systemImage: "checkmark.shield")
                Label("ネットワーク通信とPixivログインは行いません", systemImage: "wifi.slash")
                LabeledContent("保存した作品", value: "\(savedIDs.count)")
            }

            Section {
                Button("デモを終了", role: .destructive, action: onExit)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ZoneTheme.background)
    }

    private func toggle(_ id: String, in values: inout Set<String>) {
        if values.contains(id) {
            values.remove(id)
        } else {
            values.insert(id)
        }
    }
}

private struct ReviewDemoArtworkCard: View {
    let artwork: Artwork
    let isLiked: Bool
    let isSaved: Bool
    let onLike: () -> Void
    let onSave: () -> Void
    let onMangaViewerChanged: (Bool) -> Void
    @State private var isHUDVisible = true
    @State private var isMangaViewerActive = false
    @State private var mangaPage = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if isMangaViewerActive {
                reviewMangaViewer
            } else {
                ReviewDemoArtworkVisual(artwork: artwork, page: 0)
                    .contentShape(Rectangle())
                    .overlay {
                        MultiTapGestureView(
                            onSingleTap: handleSingleTap,
                            onDoubleTap: onSave,
                            onTripleTap: onLike
                        )
                    }
            }

            if isHUDVisible {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(ZoneTheme.accent.opacity(0.28))
                                .frame(width: 36, height: 36)
                                .overlay(Image(systemName: "person.fill").foregroundStyle(ZoneTheme.accent))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artwork.creator).font(.subheadline.weight(.bold))
                                Text(artwork.handle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(artwork.title)
                            .font(.title2.weight(.bold))
                        Text(artwork.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        Button(action: onLike) {
                            RailButton(icon: isLiked ? "heart.fill" : "heart", label: "いいね", tint: isLiked ? .pink : .white)
                        }
                        Button(action: onSave) {
                            RailButton(icon: isSaved ? "bookmark.fill" : "bookmark", label: "保存", tint: isSaved ? ZoneTheme.accent : .white)
                        }
                        ShareLink(item: "pixtopia 審査用デモ: \(artwork.title)") {
                            RailButton(icon: "paperplane", label: "共有")
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 26)
            }
        }
        .onChange(of: isMangaViewerActive) {
            onMangaViewerChanged(isMangaViewerActive)
        }
        .onDisappear {
            onMangaViewerChanged(false)
        }
        .accessibilityElement(children: .contain)
    }

    private var reviewMangaViewer: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $mangaPage) {
                ForEach(0..<artwork.pageCount, id: \.self) { page in
                    ReviewDemoArtworkVisual(artwork: artwork, page: page)
                        .tag(page)
                        .onTapGesture { closeMangaViewer() }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 6) {
                ProgressView(value: Double(mangaPage + 1), total: Double(artwork.pageCount))
                    .tint(ZoneTheme.accent)
                Text("\(mangaPage + 1) / \(artwork.pageCount)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .allowsHitTesting(false)
        }
        .accessibilityLabel("サンプル漫画ビューワー")
        .accessibilityHint("左右にスワイプしてページを切り替え、タップで戻ります")
    }

    private func handleSingleTap() {
        withAnimation(.easeOut(duration: 0.18)) {
            if artwork.kind == "manga" && artwork.pageCount > 1 {
                isHUDVisible = false
                isMangaViewerActive = true
            } else {
                isHUDVisible.toggle()
            }
        }
    }

    private func closeMangaViewer() {
        withAnimation(.easeOut(duration: 0.18)) {
            isMangaViewerActive = false
            isHUDVisible = true
            mangaPage = 0
        }
    }
}

private struct ReviewDemoArtworkVisual: View {
    let artwork: Artwork
    let page: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: artwork.palette.reversed(),
                    startPoint: page.isMultiple(of: 2) ? .topLeading : .bottomTrailing,
                    endPoint: page.isMultiple(of: 2) ? .bottomTrailing : .topLeading
                )

                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: proxy.size.width * 0.8)
                    .offset(x: proxy.size.width * 0.25, y: -proxy.size.height * 0.18)
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .fill(.black.opacity(0.2))
                    .frame(width: proxy.size.width * 0.7, height: proxy.size.height * 0.42)
                    .rotationEffect(.degrees(Double(page * 11 - 8)))

                VStack(spacing: 16) {
                    Image(systemName: artwork.symbol)
                        .font(.system(size: 82, weight: .thin))
                        .symbolRenderingMode(.hierarchical)
                    Text(artwork.kind == "manga" ? "SAMPLE PAGE \(page + 1)" : "SAMPLE ARTWORK")
                        .font(.caption.weight(.black))
                        .tracking(3)
                }
                .foregroundStyle(.white.opacity(0.86))
            }
        }
        .background(.black)
    }
}

private enum ReviewDemoData {
    static let artworks: [Artwork] = [
        Artwork(
            id: "demo-1", kind: "illust", pageCount: 1,
            title: "夜明けのグラデーション", creator: "Demo Artist", handle: "@review_demo",
            tags: ["オリジナル", "空", "デモ"], likes: 0, bookmarks: 0, comments: 0,
            symbol: "sparkles", palette: [.indigo, .purple, .pink], imageURL: nil,
            isBookmarkable: true, bookmarkID: nil
        ),
        Artwork(
            id: "demo-2", kind: "manga", pageCount: 4,
            title: "4ページのサンプル漫画", creator: "Demo Studio", handle: "@review_manga",
            tags: ["漫画", "サンプル", "横スワイプ"], likes: 0, bookmarks: 0, comments: 0,
            symbol: "book.pages", palette: [.blue, .cyan, .mint], imageURL: nil,
            isBookmarkable: true, bookmarkID: "demo-bookmark"
        ),
        Artwork(
            id: "demo-3", kind: "illust", pageCount: 1,
            title: "雨上がりの光", creator: "Sample Creator", handle: "@sample_creator",
            tags: ["風景", "光", "オリジナル"], likes: 0, bookmarks: 0, comments: 0,
            symbol: "cloud.sun.fill", palette: [.teal, .blue, .indigo], imageURL: nil,
            isBookmarkable: true, bookmarkID: nil
        )
    ]
}

private struct PixivLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    let onAuthenticated: (PixivSessionCredentials) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                PixivWebView(
                    onAuthenticated: onAuthenticated,
                    onFailure: { message in errorMessage = message }
                )

                if let errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Button("閉じる") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(24)
                }
            }
            .navigationTitle("Pixivにログイン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.light)
    }
}

private struct PixivAuthenticatedWebView: UIViewRepresentable {
    let url: URL
    let credentials: PixivSessionCredentials

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = credentials.userAgent
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.customUserAgent = credentials.userAgent

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = credentials.cookies.compactMap { $0.makeHTTPCookie() }
        let group = DispatchGroup()

        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak webView] in
            guard let webView else { return }
            var request = URLRequest(url: url)
            request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

private enum PixivFollowAutomationAction: String {
    case follow
    case unfollow
}

private enum PixivFollowAutomationResult {
    case followed
    case alreadyFollowing
    case unfollowed
    case alreadyNotFollowing
    case failed(String)
}

private struct PixivFollowAutomationWebView: UIViewRepresentable {
    let userID: String
    let credentials: PixivSessionCredentials
    let action: PixivFollowAutomationAction
    let onResult: (PixivFollowAutomationResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, onResult: onResult)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "zoneFollow")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = credentials.userAgent
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let requestKey = "\(userID):\(action.rawValue)"
        guard context.coordinator.loadedRequestKey != requestKey else { return }
        context.coordinator.loadedRequestKey = requestKey
        webView.customUserAgent = credentials.userAgent

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = credentials.cookies.compactMap { $0.makeHTTPCookie() }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) { group.leave() }
        }

        group.notify(queue: .main) { [weak webView] in
            guard let webView,
                  let url = URL(string: "https://www.pixiv.net/users/\(userID)") else { return }
            var request = URLRequest(url: url)
            request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "zoneFollow")
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedRequestKey: String?
        private var didComplete = false
        private let action: PixivFollowAutomationAction
        private let onResult: (PixivFollowAutomationResult) -> Void

        init(
            action: PixivFollowAutomationAction,
            onResult: @escaping (PixivFollowAutomationResult) -> Void
        ) {
            self.action = action
            self.onResult = onResult
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = #"""
            (() => {
              if (window.__zoneFollowAutomationStarted) return;
              window.__zoneFollowAutomationStarted = true;

              const action = '\#(action.rawValue)';
              const send = value => window.webkit.messageHandlers.zoneFollow.postMessage(value);
              const label = element => (element.innerText || element.textContent || element.getAttribute('aria-label') || '')
                .replace(/\s+/g, ' ').trim();
              const followLabels = new Set(['フォロー', 'フォローする', 'Follow']);
              const followingLabels = new Set(['フォロー中', 'フォローしています', 'Following']);
              const unfollowLabels = new Set(['フォロー解除', 'フォローを解除', 'フォロー解除する', 'Unfollow']);
              const controls = root => Array.from(root.querySelectorAll('button, [role="button"]'));
              const findControl = (root, labels) => controls(root).find(element => labels.has(label(element)));
              const targetLabels = action === 'follow'
                ? followLabels
                : new Set([...followingLabels, ...unfollowLabels]);
              const successLabels = action === 'follow' ? followingLabels : followLabels;

              let findAttempts = 0;
              const findTimer = setInterval(() => {
                findAttempts += 1;
                const button = findControl(document, targetLabels);
                if (!button) {
                  if (findAttempts >= 60) {
                    clearInterval(findTimer);
                    send('buttonNotFound');
                  }
                  return;
                }

                clearInterval(findTimer);
                const container = button.parentElement || document;
                button.click();

                if (action === 'unfollow') {
                  setTimeout(() => {
                    const confirmation = controls(document).find(element =>
                      element !== button && unfollowLabels.has(label(element))
                    );
                    if (confirmation) confirmation.click();
                  }, 300);
                }

                let confirmationAttempts = 0;
                const confirmationTimer = setInterval(() => {
                  confirmationAttempts += 1;
                  if (findControl(container, successLabels)) {
                    clearInterval(confirmationTimer);
                    send(action === 'follow' ? 'followed' : 'unfollowed');
                  } else if (confirmationAttempts >= 40) {
                    clearInterval(confirmationTimer);
                    send('confirmationTimedOut');
                  }
                }, 250);
              }, 250);
            })();
            """#

            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let self, let error else { return }
                self.complete(.failed("フォロー操作を開始できませんでした: \(error.localizedDescription)"))
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let value = message.body as? String else { return }
            switch value {
            case "followed":
                complete(.followed)
            case "alreadyFollowing":
                complete(.alreadyFollowing)
            case "unfollowed":
                complete(.unfollowed)
            case "alreadyNotFollowing":
                complete(.alreadyNotFollowing)
            case "buttonNotFound":
                complete(.failed(action == .follow
                    ? "Pixivのフォローボタンを見つけられませんでした。"
                    : "Pixivのフォロー解除ボタンを見つけられませんでした。"))
            default:
                complete(.failed("Pixiv上でフォロー完了を確認できませんでした。"))
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            complete(.failed("Pixivプロフィールを読み込めませんでした: \(error.localizedDescription)"))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            complete(.failed("Pixivプロフィールを開けませんでした: \(error.localizedDescription)"))
        }

        private func complete(_ result: PixivFollowAutomationResult) {
            guard !didComplete else { return }
            didComplete = true
            DispatchQueue.main.async { [onResult] in
                onResult(result)
            }
        }
    }
}

private struct PixivWebView: UIViewRepresentable {
    let onAuthenticated: (PixivSessionCredentials) -> Void
    let onFailure: (String) -> Void

    private static let csrfCaptureScript = #"""
    (() => {
        const host = location.hostname.toLowerCase();
        const isPixivHost = host === 'pixiv.net' || host.endsWith('.pixiv.net');
        if (!isPixivHost || window.__zoneCsrfCaptureInstalled) return;
        window.__zoneCsrfCaptureInstalled = true;

        const send = (value) => {
            if (typeof value !== 'string' || value.length === 0) return;
            const handler = window.webkit && window.webkit.messageHandlers
                && window.webkit.messageHandlers.zoneCsrf;
            if (handler) handler.postMessage(value);
        };

        const inspectHeaders = (headers) => {
            if (!headers) return;
            if (typeof Headers !== 'undefined' && headers instanceof Headers) {
                send(headers.get('x-csrf-token'));
                return;
            }
            if (Array.isArray(headers)) {
                headers.forEach((pair) => {
                    if (pair && String(pair[0]).toLowerCase() === 'x-csrf-token') send(String(pair[1]));
                });
                return;
            }
            if (typeof headers === 'object') {
                Object.keys(headers).forEach((key) => {
                    if (key.toLowerCase() === 'x-csrf-token') send(String(headers[key]));
                });
            }
        };

        if (typeof window.fetch === 'function') {
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
                try {
                    inspectHeaders(init && init.headers);
                    if (typeof Request !== 'undefined' && input instanceof Request) {
                        inspectHeaders(input.headers);
                    }
                } catch (_) {}
                return originalFetch.apply(this, arguments);
            };
        }

        const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
            if (String(name).toLowerCase() === 'x-csrf-token') send(String(value));
            return originalSetRequestHeader.apply(this, arguments);
        };
    })();
    """#

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthenticated: onAuthenticated, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let userContentController = WKUserContentController()
        userContentController.addUserScript(WKUserScript(
            source: Self.csrfCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        userContentController.add(context.coordinator, name: "zoneCsrf")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        guard let loginURL = URL(string: "https://accounts.pixiv.net/login") else {
            onFailure("ログイン画面のURLを開けませんでした")
            return webView
        }
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let onAuthenticated: (PixivSessionCredentials) -> Void
        private let onFailure: (String) -> Void
        private var isCheckingSession = false
        private var latestCSRFToken: String?

        init(
            onAuthenticated: @escaping (PixivSessionCredentials) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onAuthenticated = onAuthenticated
            self.onFailure = onFailure
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "zoneCsrf",
                  let token = message.body as? String,
                  !token.isEmpty else { return }
            latestCSRFToken = token
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                onFailure("ログイン先のURLを確認できませんでした")
                return
            }

            let scheme = url.scheme?.lowercased()
            let isHTTPS = scheme == "https"
            let isInternalBlankPage = scheme == "about" && url.absoluteString == "about:blank"

            if isHTTPS || isInternalBlankPage {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                onFailure("対応していないログイン先へ移動しようとしました")
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Apple・Google・Twitter/XなどのOAuthがtarget=_blankやwindow.openで開始されても、
            // 別ウィンドウを作らず、このログインWebView内で続行する。
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url,
                  url.host?.lowercased() == "www.pixiv.net",
                  !isCheckingSession else { return }

            isCheckingSession = true
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    let credentials = try await PixivSessionExtractor.extract(
                        from: webView,
                        csrfHint: latestCSRFToken
                    )
                    guard credentials.isUsable else {
                        isCheckingSession = false
                        onFailure("ログイン後のセッション情報を確認できませんでした")
                        return
                    }
                    onAuthenticated(credentials)
                } catch {
                    isCheckingSession = false
                    onFailure(error.localizedDescription)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            isCheckingSession = false
            reportNavigationFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            isCheckingSession = false
            reportNavigationFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isCheckingSession = false
            onFailure("ログイン画面が停止しました。閉じてもう一度お試しください")
        }

        private func reportNavigationFailure(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            onFailure("ログイン画面を読み込めませんでした: \(error.localizedDescription)")
        }
    }
}

// MARK: - Pixiv session storage

struct PixivSessionCredentials: Codable {
    let csrfToken: String
    let userAgent: String
    let cookies: [PixivCookie]
    let userID: String?
    let savedAt: Date

    var isUsable: Bool {
        !csrfToken.isEmpty && !userAgent.isEmpty && !cookies.isEmpty
    }

    var cookieHeader: String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

struct PixivCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate
    }

    func makeHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expires {
            properties[.expires] = expires
        }
        return HTTPCookie(properties: properties)
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var credentials: PixivSessionCredentials?
    @Published var errorMessage: String?

    private let keychain = KeychainSessionStore()

    init() {
        credentials = try? keychain.load()
    }

    var isLoggedIn: Bool {
        credentials?.isUsable == true
    }

    @discardableResult
    func save(_ credentials: PixivSessionCredentials) -> Bool {
        do {
            try keychain.save(credentials)
            self.credentials = credentials
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateUserID(_ userID: String) {
        guard let credentials, credentials.userID != userID else { return }
        _ = save(PixivSessionCredentials(
            csrfToken: credentials.csrfToken,
            userAgent: credentials.userAgent,
            cookies: credentials.cookies,
            userID: userID,
            savedAt: credentials.savedAt
        ))
    }

    func logout() {
        try? keychain.delete()
        credentials = nil

        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where Self.isPixivCookie(cookie) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        webCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                let domain = cookie.domain
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if domain == "pixiv.net" || domain.hasSuffix(".pixiv.net") {
                    webCookieStore.delete(cookie)
                }
            }
        }
    }

    private static func isPixivCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "pixiv.net" || domain.hasSuffix(".pixiv.net")
    }
}

private struct KeychainSessionStore {
    private let service = "jp.amania.pixtopia"
    private let account = "pixiv-session"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func save(_ credentials: PixivSessionCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updateQuery = baseQuery
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    func load() throws -> PixivSessionCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(PixivSessionCredentials.self, from: data)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Keychainへの保存に失敗しました (\(status))"
    }
}

private enum PixivSessionExtractor {
    static func extract(from webView: WKWebView, csrfHint: String? = nil) async throws -> PixivSessionCredentials {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let pixivCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "pixiv.net" || domain.hasSuffix(".pixiv.net")
        }

        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String ?? ""
        let csrfFromPage = try await webView.evaluateJavaScript(
            """
            (() => {
                const selectors = [
                    'meta[name="csrf-token"]',
                    'meta[name="csrf_token"]',
                    'meta[property="x-csrf-token"]'
                ];
                for (const selector of selectors) {
                    const element = document.querySelector(selector);
                    if (element && element.content) return element.content;
                }
                return null;
            })();
            """
        ) as? String

        let csrfFromCookie = pixivCookies.first {
            $0.name.localizedCaseInsensitiveContains("csrf")
        }?.value

        return PixivSessionCredentials(
            csrfToken: csrfHint ?? csrfFromPage ?? csrfFromCookie ?? "",
            userAgent: userAgent,
            cookies: pixivCookies.map(PixivCookie.init(cookie:)),
            userID: nil,
            savedAt: Date()
        )
    }
}

// MARK: - Pixiv boundary

/// Pixivとのデータ交換をUIから切り離すための境界。
protocol PixivRepository {
    func fetchFeed() async throws -> [Artwork]
}

struct PixivFeedPage {
    let artworks: [Artwork]
    let nextCursor: PixivFeedCursor?
}

struct PixivFeedCursor {
    let page: Int
}

struct PixivAPIClient: PixivRepository {
    let credentials: PixivSessionCredentials
    private let session: URLSession

    init(credentials: PixivSessionCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func fetchFeed() async throws -> [Artwork] {
        try await fetchFeedPage(after: nil).artworks
    }

    func fetchFeedPage(after cursor: PixivFeedCursor?) async throws -> PixivFeedPage {
        guard let url = URL(string: "https://www.pixiv.net/ajax/street/v2/main") else {
            throw PixivAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(StreetRequest(page: cursor?.page ?? 1))
        request.setValue(credentials.csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue(credentials.cookieHeader, forHTTPHeaderField: "cookie")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")

        logRequestHeaders(request)
        pixivAPILogger.debug("street request method=POST page=\(cursor?.page ?? 1, privacy: .public)")
        #if DEBUG
        print("[PixivAPI] street request method=POST page=\(cursor?.page ?? 1)")
        #endif

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PixivAPIError.invalidResponse
        }
        pixivAPILogger.debug("street response status=\(httpResponse.statusCode, privacy: .public)")
        #if DEBUG
        print("[PixivAPI] street response status=\(httpResponse.statusCode)")
        #endif
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseSummary = String(data: data, encoding: .utf8)
                .map { String($0.prefix(240)) }
            pixivAPILogger.error("street response status=\(httpResponse.statusCode, privacy: .public) body=\(responseSummary ?? "<non-utf8>", privacy: .public)")
            #if DEBUG
            print("[PixivAPI] street response body=\(responseSummary ?? "<non-utf8>")")
            #endif
            throw PixivAPIError.httpStatus(httpResponse.statusCode, responseSummary)
        }

        let envelope = try JSONDecoder().decode(StreetResponse.self, from: data)
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "Pixiv APIがエラーを返しました" : envelope.message)
        }

        let artworks = envelope.body.contents.compactMap { $0.makeArtwork() }
        guard !artworks.isEmpty else { throw PixivAPIError.emptyFeed }
        return PixivFeedPage(
            artworks: artworks,
            nextCursor: envelope.body.nextParams?.cursor
        )
    }

    fileprivate func fetchArtworkDetail(for artwork: Artwork) async throws -> PixivArtworkDetail {
        guard let detailURL = URL(string: "https://www.pixiv.net/ajax/illust/\(artwork.id)") else {
            throw PixivAPIError.invalidURL
        }

        let detailRequest = makeRequest(url: detailURL, method: "GET")
        let detailData = try await loadData(for: detailRequest)
        let envelope = try JSONDecoder().decode(IllustDetailResponse.self, from: detailData)
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "作品詳細APIがエラーを返しました" : envelope.message)
        }

        let body = envelope.body
        var pages: [PixivArtworkPage] = []

        if artwork.kind == "manga" || body.pageCount > 1 {
            guard let pagesURL = URL(string: "https://www.pixiv.net/ajax/illust/\(artwork.id)/pages") else {
                throw PixivAPIError.invalidURL
            }
            let pagesData = try await loadData(for: makeRequest(url: pagesURL, method: "GET"))
            let pagesEnvelope = try JSONDecoder().decode(IllustPagesResponse.self, from: pagesData)
            pages = pagesEnvelope.body.compactMap { page in
                guard let imageURL = page.preferredURL else { return nil }
                return PixivArtworkPage(
                    id: imageURL.absoluteString,
                    url: imageURL,
                    width: page.width,
                    height: page.height
                )
            }
        }

        if pages.isEmpty, let imageURL = body.preferredURL {
            pages = [PixivArtworkPage(
                id: imageURL.absoluteString,
                url: imageURL,
                width: body.width,
                height: body.height
            )]
        }

        guard !pages.isEmpty else { throw PixivAPIError.emptyFeed }

        return PixivArtworkDetail(
            title: body.title,
            description: body.description ?? "",
            creator: body.userName,
            handle: "@\(body.userAccount ?? body.userId)",
            tags: body.tags?.tags.map(\.tag) ?? [],
            likeCount: body.likeCount,
            bookmarkCount: body.bookmarkCount,
            commentCount: body.commentCount,
            pages: pages
        )
    }

    fileprivate func fetchTagSuggestions(keyword: String) async throws -> [PixivTagSuggestion] {
        var components = URLComponents(string: "https://www.pixiv.net/rpc/cps.php")
        components?.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        guard let url = components?.url else { throw PixivAPIError.invalidURL }

        let data = try await loadData(for: makeRequest(url: url, method: "GET"))
        return try JSONDecoder().decode(PixivTagSuggestionResponse.self, from: data).candidates
    }

    fileprivate func searchArtworks(
        tag: String,
        page: Int,
        kind: ArtworkSearchKind,
        mode: ArtworkSearchMode
    ) async throws -> PixivArtworkSearchPage {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.pixiv.net"
        components.path = "/ajax/search/\(kind.endpointComponent)/\(tag)"
        components.queryItems = [
            URLQueryItem(name: "p", value: String(max(page, 1))),
            URLQueryItem(name: "mode", value: mode.rawValue)
        ]
        guard let url = components.url else { throw PixivAPIError.invalidURL }

        let data = try await loadData(for: makeRequest(url: url, method: "GET"))
        let envelope: PixivArtworkSearchResponse
        do {
            envelope = try JSONDecoder().decode(PixivArtworkSearchResponse.self, from: data)
        } catch {
            logDecodingError(error, endpoint: "search mode=\(mode.rawValue)")
            throw error
        }
        guard !envelope.error else {
            throw PixivAPIError.server("Pixiv検索APIがエラーを返しました")
        }
        guard let section = envelope.body.section(for: kind) else {
            throw PixivAPIError.server("Pixiv検索APIのレスポンス形式を確認できませんでした")
        }
        return PixivArtworkSearchPage(
            artworks: section.data.compactMap { $0.makeArtwork() },
            page: page,
            lastPage: section.lastPage ?? page
        )
    }

    fileprivate func fetchCurrentUserContext() async throws -> PixivCurrentUserContext {
        guard let url = URL(string: "https://www.pixiv.net/ajax/user/extra") else {
            throw PixivAPIError.invalidURL
        }

        let (data, response) = try await loadResponse(for: makeRequest(url: url, method: "GET"))
        let envelope = try JSONDecoder().decode(PixivUserExtraResponse.self, from: data)
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "ユーザー情報を取得できませんでした" : envelope.message)
        }
        guard let userID = response.value(forHTTPHeaderField: "x-userid")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            throw PixivAPIError.missingUserID
        }
        return PixivCurrentUserContext(userID: userID, extra: envelope.body)
    }

    fileprivate func fetchUserProfile(userID: String) async throws -> PixivUserProfile {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.pixiv.net"
        components.path = "/ajax/user/\(userID)"
        components.queryItems = [URLQueryItem(name: "full", value: "1")]
        guard let url = components.url else { throw PixivAPIError.invalidURL }

        let data = try await loadData(for: makeRequest(url: url, method: "GET"))
        let envelope = try JSONDecoder().decode(PixivUserProfileResponse.self, from: data)
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "プロフィールを取得できませんでした" : envelope.message)
        }
        return envelope.body
    }

    fileprivate func fetchUserArtworkIDs(userID: String) async throws -> [String] {
        guard let url = URL(string: "https://www.pixiv.net/ajax/user/\(userID)/profile/all") else {
            throw PixivAPIError.invalidURL
        }

        let data = try await loadData(for: makeRequest(url: url, method: "GET"))
        let envelope = try JSONDecoder().decode(PixivUserWorksIndexResponse.self, from: data)
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "ユーザーの作品一覧を取得できませんでした" : envelope.message)
        }
        return Array(Set(envelope.body.illusts.ids + envelope.body.manga.ids)).sorted {
            (Int64($0) ?? 0) > (Int64($1) ?? 0)
        }
    }

    fileprivate func fetchUserArtworks(
        userID: String,
        ids: [String],
        isFirstPage: Bool
    ) async throws -> [Artwork] {
        guard !ids.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.pixiv.net"
        components.path = "/ajax/user/\(userID)/profile/illusts"
        components.queryItems = [
            URLQueryItem(name: "work_category", value: "illustManga"),
            URLQueryItem(name: "is_first_page", value: isFirstPage ? "1" : "0"),
            URLQueryItem(name: "lang", value: "ja")
        ] + ids.map { URLQueryItem(name: "ids[]", value: $0) }
        guard let url = components.url else { throw PixivAPIError.invalidURL }

        let data = try await loadData(for: makeRequest(url: url, method: "GET"))
        let envelope = try JSONDecoder().decode(PixivUserWorksResponse.self, from: data)
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "ユーザーの作品を取得できませんでした" : envelope.message)
        }
        return ids.compactMap { envelope.body.works[$0]?.makeArtwork() }
    }

    fileprivate func fetchBookmarks(
        userID: String,
        offset: Int,
        limit: Int
    ) async throws -> PixivBookmarkPage {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.pixiv.net"
        components.path = "/ajax/user/\(userID)/illusts/bookmarks"
        components.queryItems = [
            URLQueryItem(name: "tag", value: ""),
            URLQueryItem(name: "offset", value: String(max(offset, 0))),
            URLQueryItem(name: "limit", value: String(max(limit, 1))),
            URLQueryItem(name: "rest", value: "show"),
            URLQueryItem(name: "order", value: "desc")
        ]
        guard let url = components.url else { throw PixivAPIError.invalidURL }

        let data = try await loadData(for: makeRequest(url: url, method: "GET"))
        let envelope: PixivBookmarksResponse
        do {
            envelope = try JSONDecoder().decode(PixivBookmarksResponse.self, from: data)
        } catch {
            logDecodingError(error, endpoint: "bookmarks")
            throw error
        }
        guard !envelope.error else {
            throw PixivAPIError.server(envelope.message.isEmpty ? "ブックマークを取得できませんでした" : envelope.message)
        }
        let itemCount = envelope.body.works.count
        return PixivBookmarkPage(
            artworks: envelope.body.works.compactMap { $0.makeArtwork() },
            total: envelope.body.total,
            itemCount: itemCount,
            nextOffset: max(offset, 0) + itemCount
        )
    }

    fileprivate func addBookmark(illustID: String) async throws -> String {
        guard let url = URL(string: "https://www.pixiv.net/ajax/illusts/bookmarks/add") else {
            throw PixivAPIError.invalidURL
        }

        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(PixivBookmarkAddRequest(illustID: illustID))
        let data = try await loadData(for: request)
        let response = try JSONDecoder().decode(PixivBookmarkAddResponse.self, from: data)
        guard !response.error else {
            throw PixivAPIError.server(response.message.isEmpty ? "作品を保存できませんでした" : response.message)
        }
        return response.body.lastBookmarkID
    }

    fileprivate func likeArtwork(illustID: String) async throws {
        guard let url = URL(string: "https://www.pixiv.net/ajax/illusts/like") else {
            throw PixivAPIError.invalidURL
        }

        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(PixivLikeRequest(illustID: illustID))
        let data = try await loadData(for: request)
        let response = try JSONDecoder().decode(PixivMutationResponse.self, from: data)
        guard !response.error else {
            throw PixivAPIError.server(response.message.isEmpty ? "作品にいいねできませんでした" : response.message)
        }
    }

    fileprivate func deleteBookmark(bookmarkID: String) async throws {
        guard let url = URL(string: "https://www.pixiv.net/ajax/illusts/bookmarks/delete") else {
            throw PixivAPIError.invalidURL
        }

        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "content-type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "bookmark_id", value: bookmarkID)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let data = try await loadData(for: request)
        let response = try JSONDecoder().decode(PixivMutationResponse.self, from: data)
        guard !response.error else {
            throw PixivAPIError.server(response.message.isEmpty ? "作品の保存を取り消せませんでした" : response.message)
        }
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue(credentials.cookieHeader, forHTTPHeaderField: "cookie")
        request.setValue(credentials.userAgent, forHTTPHeaderField: "user-agent")
        request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "referer")
        request.setValue("https://www.pixiv.net", forHTTPHeaderField: "origin")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        return request
    }

    private func loadData(for request: URLRequest) async throws -> Data {
        try await loadResponse(for: request).0
    }

    private func loadResponse(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        logRequestHeaders(request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PixivAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let summary = String(data: data, encoding: .utf8).map { String($0.prefix(240)) }
            throw PixivAPIError.httpStatus(httpResponse.statusCode, summary)
        }
        return (data, httpResponse)
    }

    private func logRequestHeaders(_ request: URLRequest) {
        #if DEBUG
        let lines = (request.allHTTPHeaderFields ?? [:])
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { field, value in
                if ["cookie", "x-csrf-token"].contains(field.lowercased()) {
                    return "\(field)=<redacted length=\(value.count)>"
                }
                return "\(field)=\(value)"
            }
            .joined(separator: " | ")
        pixivAPILogger.debug("street request headers: \(lines, privacy: .public)")
        print("[PixivAPI] street request headers: \(lines)")
        #endif
    }

    private func logDecodingError(_ error: Error, endpoint: String) {
        #if DEBUG
        let detail: String
        switch error {
        case let DecodingError.keyNotFound(key, context):
            detail = "missing key=\(key.stringValue) path=\(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let DecodingError.typeMismatch(type, context):
            detail = "type mismatch expected=\(type) path=\(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let DecodingError.valueNotFound(type, context):
            detail = "null value expected=\(type) path=\(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let DecodingError.dataCorrupted(context):
            detail = "corrupted path=\(context.codingPath.map(\.stringValue).joined(separator: ".")) reason=\(context.debugDescription)"
        default:
            detail = error.localizedDescription
        }
        pixivAPILogger.error("\(endpoint, privacy: .public) decode failed: \(detail, privacy: .public)")
        print("[PixivAPI] \(endpoint) decode failed: \(detail)")
        #endif
    }
}

enum PixivAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case server(String)
    case emptyFeed
    case missingUserID

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Pixiv APIのURLが不正です。"
        case .invalidResponse:
            return "Pixiv APIのレスポンスを確認できませんでした。"
        case .httpStatus(let status, let summary):
            if let summary, !summary.isEmpty {
                return "Pixiv APIがHTTP \(status)を返しました。\n\(summary)"
            }
            return "Pixiv APIがHTTP \(status)を返しました。"
        case .server(let message):
            return message
        case .emptyFeed:
            return "表示できる作品がありませんでした。"
        case .missingUserID:
            return "PixivのレスポンスからユーザーIDを取得できませんでした。"
        }
    }
}

private struct StreetRequest: Encodable {
    let params: StreetRequestParams
    let k = "separator"
    let vhi = "147336983,104272381,108895082,147199183,132769371,147114502,147194785"
    let vhm: String? = nil
    let vhn = "28606861,28637806,27174067"
    let vhc = "62169695897156731269"

    init(page: Int) {
        params = StreetRequestParams(
            page: page,
            contentIndexPrev: 11
        )
    }
}

private struct StreetRequestParams: Encodable {
    let page: Int
    let contentIndexPrev: Int

    enum CodingKeys: String, CodingKey {
        case page
        case contentIndexPrev = "content_index_prev"
    }
}

private struct StreetResponse: Decodable {
    let error: Bool
    let message: String
    let body: StreetBody
}

private struct IllustDetailResponse: Decodable {
    let error: Bool
    let message: String
    let body: IllustDetailBody
}

private struct IllustDetailBody: Decodable {
    let id: String
    let title: String
    let description: String?
    let urls: [String: String]
    let tags: IllustTags?
    let userId: String
    let userName: String
    let userAccount: String?
    let pageCount: Int
    let likeCount: Int
    let bookmarkCount: Int
    let commentCount: Int
    let width: Int
    let height: Int

    var preferredURL: URL? {
        ["original", "regular", "small"]
            .compactMap { urls[$0] }
            .compactMap(URL.init(string:))
            .first
    }
}

private struct IllustTags: Decodable {
    let tags: [IllustTag]
}

private struct IllustTag: Decodable {
    let tag: String
}

private struct IllustPagesResponse: Decodable {
    let error: Bool
    let message: String
    let body: [IllustPage]
}

private struct PixivTagSuggestionResponse: Decodable {
    let candidates: [PixivTagSuggestion]
}

private struct PixivCurrentUserContext {
    let userID: String
    let extra: PixivUserExtra
}

private struct PixivUserExtraResponse: Decodable {
    let error: Bool
    let message: String
    let body: PixivUserExtra
}

private struct PixivUserExtra: Decodable {
    let following: Int
    let followers: Int
    let mypixivCount: Int
}

private struct PixivUserProfileResponse: Decodable {
    let error: Bool
    let message: String
    let body: PixivUserProfile
}

private struct PixivUserProfile: Decodable {
    let userId: String
    let name: String
    let image: String?
    let imageBig: String?
    let premium: Bool
    let isFollowed: Bool
    let following: Int
    let comment: String?
    let region: PixivProfileField?
    let age: PixivProfileField?
    let birthDay: PixivProfileField?
    let gender: PixivProfileField?

    var preferredImageURL: URL? {
        [imageBig, image]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}

private struct PixivProfileField: Decodable {
    let name: String?
    let privacyLevel: String?
}

private struct PixivUserWorksIndexResponse: Decodable {
    let error: Bool
    let message: String
    let body: PixivUserWorksIndexBody
}

private struct PixivUserWorksIndexBody: Decodable {
    let illusts: PixivWorkIDIndex
    let manga: PixivWorkIDIndex
}

private struct PixivWorkIDIndex: Decodable {
    let ids: [String]

    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var decodedIDs: [String] = []
            while !container.isAtEnd {
                if let id = try? container.decode(String.self) {
                    decodedIDs.append(id)
                } else {
                    _ = try? container.decode(PixivDiscardedValue.self)
                }
            }
            ids = decodedIDs
            return
        }

        let container = try decoder.container(keyedBy: PixivDynamicCodingKey.self)
        ids = container.allKeys.map(\.stringValue)
    }
}

private struct PixivDiscardedValue: Decodable {}

private struct PixivDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = Int(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct PixivUserWorksResponse: Decodable {
    let error: Bool
    let message: String
    let body: PixivUserWorksBody
}

private struct PixivUserWorksBody: Decodable {
    let works: [String: PixivBookmarkWork]
}

private struct PixivTagSuggestion: Decodable, Identifiable {
    let tagName: String
    let accessCount: String
    let type: String

    var id: String { "\(tagName)|\(type)" }
    var accessCountValue: Int? { Int(accessCount) }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case accessCount = "access_count"
        case type
    }
}

private struct PixivBookmarkAddRequest: Encodable {
    let illustID: String
    let restrict = 0
    let comment = ""
    let tags: [String] = []

    enum CodingKeys: String, CodingKey {
        case illustID = "illust_id"
        case restrict
        case comment
        case tags
    }
}

private struct PixivLikeRequest: Encodable {
    let illustID: String

    enum CodingKeys: String, CodingKey {
        case illustID = "illust_id"
    }
}

private struct PixivBookmarkAddResponse: Decodable {
    let error: Bool
    let message: String
    let body: PixivBookmarkAddBody
}

private struct PixivBookmarkAddBody: Decodable {
    let lastBookmarkID: String

    enum CodingKeys: String, CodingKey {
        case lastBookmarkID = "last_bookmark_id"
    }
}

private struct PixivMutationResponse: Decodable {
    let error: Bool
    let message: String
}

private struct PixivBookmarksResponse: Decodable {
    let error: Bool
    let message: String
    let body: PixivBookmarksBody
}

private struct PixivBookmarksBody: Decodable {
    let works: [PixivBookmarkWork]
    let total: Int
}

private struct PixivBookmarkWork: Decodable {
    let id: String?
    let title: String?
    let url: String?
    let tags: [String]?
    let userId: String?
    let userName: String?
    let pageCount: Int?
    let isBookmarkable: Bool?
    let bookmarkData: PixivSearchBookmarkData?
    let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case tags
        case userId
        case userName
        case pageCount
        case isBookmarkable
        case bookmarkData
        case profileImageUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleStringIfPresent(forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        userId = try container.decodeFlexibleStringIfPresent(forKey: .userId)
        userName = try container.decodeIfPresent(String.self, forKey: .userName)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        isBookmarkable = try container.decodeIfPresent(Bool.self, forKey: .isBookmarkable)
        bookmarkData = try container.decodeIfPresent(PixivSearchBookmarkData.self, forKey: .bookmarkData)
        profileImageUrl = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
    }

    func makeArtwork() -> Artwork? {
        guard let id,
              let url,
              let thumbnailURL = URL(string: url) else { return nil }

        let resolvedPageCount = max(pageCount ?? 1, 1)
        let kind = resolvedPageCount > 1 ? "manga" : "illust"
        return Artwork(
            id: id,
            kind: kind,
            pageCount: resolvedPageCount,
            title: title ?? "無題の作品",
            creator: userName ?? "pixivユーザー",
            handle: userId.map { "@\($0)" } ?? "@pixiv",
            tags: tags ?? [],
            likes: 0,
            bookmarks: 0,
            comments: 0,
            symbol: resolvedPageCount > 1 ? "book.pages.fill" : "photo.artframe",
            palette: PixivPalette.colors(for: kind),
            imageURL: master1200URL(from: thumbnailURL) ?? thumbnailURL,
            isBookmarkable: isBookmarkable ?? true,
            bookmarkID: bookmarkData?.id,
            profileImageURL: profileImageUrl.flatMap(URL.init(string:))
        )
    }
}

fileprivate struct PixivBookmarkPage {
    let artworks: [Artwork]
    let total: Int
    let itemCount: Int
    let nextOffset: Int
}

private struct PixivArtworkSearchResponse: Decodable {
    let error: Bool
    let body: PixivArtworkSearchBody
}

private struct PixivArtworkSearchBody: Decodable {
    let illust: PixivArtworkSearchSection?
    let manga: PixivArtworkSearchSection?

    func section(for kind: ArtworkSearchKind) -> PixivArtworkSearchSection? {
        switch kind {
        case .illustrations: illust
        case .manga: manga
        }
    }
}

private struct PixivArtworkSearchSection: Decodable {
    let data: [PixivBookmarkWork]
    let total: Int?
    let lastPage: Int?
}

fileprivate struct PixivArtworkSearchPage {
    let artworks: [Artwork]
    let page: Int
    let lastPage: Int
}

private struct PixivSearchBookmarkData: Decodable {
    let id: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case isPrivate = "private"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try container.decodeFlexibleStringIfPresent(forKey: .id) else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath + [CodingKeys.id],
                    debugDescription: "Bookmark ID is missing"
                )
            )
        }
        self.id = id
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected a string or integer"
            )
        )
    }
}

private func master1200URL(from thumbnailURL: URL) -> URL? {
    guard thumbnailURL.host == "i.pximg.net",
          var components = URLComponents(url: thumbnailURL, resolvingAgainstBaseURL: false) else {
        return nil
    }

    var path = components.path
    if let customThumbRange = path.range(of: "/custom-thumb/img/") {
        let imagePath = path[customThumbRange.upperBound...]
        path = "/img-master/img/\(imagePath)"
    } else if let imageMasterRange = path.range(of: "/img-master/img/") {
        path = String(path[imageMasterRange.lowerBound...])
    } else {
        return nil
    }

    path = path
        .replacingOccurrences(of: "_square1200.", with: "_master1200.")
        .replacingOccurrences(of: "_custom1200.", with: "_master1200.")

    components.path = path
    components.query = nil
    components.fragment = nil
    return components.url
}

private struct IllustPage: Decodable {
    let urls: [String: String]
    let width: Int
    let height: Int

    var preferredURL: URL? {
        ["original", "regular", "small"]
            .compactMap { urls[$0] }
            .compactMap(URL.init(string:))
            .first
    }
}

private struct StreetBody: Decodable {
    let contents: [StreetContent]
    let nextParams: StreetNextParams?
}

private struct StreetNextParams: Decodable {
    let page: Int?

    enum CodingKeys: String, CodingKey {
        case page
    }

    var cursor: PixivFeedCursor? {
        guard let page else { return nil }
        return PixivFeedCursor(page: page + 1)
    }
}

private struct StreetContent: Decodable {
    let kind: String
    let thumbnails: [StreetThumbnail]?

    func makeArtwork() -> Artwork? {
        guard ["illust", "manga"].contains(kind),
              let thumbnail = thumbnails?.first,
              let id = thumbnail.id,
              let imageURL = thumbnail.preferredImageURL else { return nil }

        let tags = thumbnail.tags?.map(\.name) ?? []
        let symbol = kind == "manga" ? "book.pages.fill" : "photo.artframe"

        return Artwork(
            id: id,
            kind: kind,
            pageCount: thumbnail.pageCount ?? thumbnail.pages?.count ?? 1,
            title: thumbnail.title ?? "無題の作品",
            creator: thumbnail.userName ?? "pixivユーザー",
            handle: thumbnail.userId.map { "@\($0)" } ?? "@pixiv",
            tags: Array(tags.prefix(6)),
            likes: 0,
            bookmarks: 0,
            comments: 0,
            symbol: symbol,
            palette: PixivPalette.colors(for: kind),
            imageURL: imageURL,
            isBookmarkable: true,
            bookmarkID: nil,
            profileImageURL: thumbnail.profileImageUrl.flatMap(URL.init(string:))
        )
    }
}

private struct StreetThumbnail: Decodable {
    let url: String?
    let id: String?
    let title: String?
    let userId: String?
    let userName: String?
    let tags: [StreetTag]?
    let pageCount: Int?
    let pages: [StreetPage]?
    let profileImageUrl: String?

    var preferredImageURL: URL? {
        let pageURLs = pages?.first?.urls ?? [:]
        let candidates = [
            pageURLs["1200x1200_standard"],
            pageURLs["540x540"],
            pageURLs["360x360"],
            url
        ]
        return candidates
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}

private struct StreetPage: Decodable {
    let urls: [String: String]
}

private struct StreetTag: Decodable {
    let name: String
}

private enum PixivPalette {
    static func colors(for kind: String) -> [Color] {
        switch kind {
        case "manga":
            return [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.44, green: 0.35, blue: 0.28)]
        case "novel":
            return [Color(red: 0.12, green: 0.22, blue: 0.27), Color(red: 0.28, green: 0.47, blue: 0.48)]
        case "collection":
            return [Color(red: 0.24, green: 0.16, blue: 0.32), Color(red: 0.55, green: 0.28, blue: 0.40)]
        default:
            return [Color(red: 0.12, green: 0.16, blue: 0.34), Color(red: 0.40, green: 0.26, blue: 0.55)]
        }
    }
}

// MARK: - Theme and demo data

private enum ZoneTheme {
    static let accent = Color(red: 0.66, green: 0.69, blue: 1.0)
    static let background = Color(red: 0.055, green: 0.055, blue: 0.075)
}

private enum DemoData {
    static let artworks: [Artwork] = [
        Artwork(
            id: "118392001",
            kind: "illust",
            pageCount: 1,
            title: "月明かりのアトリエ",
            creator: "雨音",
            handle: "@amaoto_draws",
            tags: ["創作", "夜景", "original"],
            likes: 12400,
            bookmarks: 8700,
            comments: 184,
            symbol: "moon.stars.fill",
            palette: [Color(red: 0.10, green: 0.12, blue: 0.34), Color(red: 0.42, green: 0.28, blue: 0.60)],
            imageURL: nil,
            isBookmarkable: true,
            bookmarkID: nil
        ),
        Artwork(
            id: "118391442",
            kind: "illust",
            pageCount: 1,
            title: "静かな熱",
            creator: "nagi",
            handle: "@nagi_works",
            tags: ["portrait", "blue", "original"],
            likes: 9800,
            bookmarks: 6300,
            comments: 92,
            symbol: "flame.fill",
            palette: [Color(red: 0.10, green: 0.28, blue: 0.38), Color(red: 0.74, green: 0.34, blue: 0.28)],
            imageURL: nil,
            isBookmarkable: true,
            bookmarkID: nil
        ),
        Artwork(
            id: "118390875",
            kind: "illust",
            pageCount: 1,
            title: "風の向きを忘れて",
            creator: "kiri",
            handle: "@kiri_sketch",
            tags: ["concept", "green", "風景"],
            likes: 21500,
            bookmarks: 15200,
            comments: 318,
            symbol: "wind",
            palette: [Color(red: 0.08, green: 0.30, blue: 0.24), Color(red: 0.64, green: 0.64, blue: 0.32)],
            imageURL: nil,
            isBookmarkable: true,
            bookmarkID: nil
        ),
        Artwork(
            id: "118389204",
            kind: "illust",
            pageCount: 1,
            title: "ネオンの余白",
            creator: "YUKI",
            handle: "@yuki_visual",
            tags: ["neon", "city", "illustration"],
            likes: 7600,
            bookmarks: 4100,
            comments: 57,
            symbol: "sparkles",
            palette: [Color(red: 0.22, green: 0.08, blue: 0.34), Color(red: 0.66, green: 0.12, blue: 0.43)],
            imageURL: nil,
            isBookmarkable: true,
            bookmarkID: nil
        )
    ]
}

private func compactNumber(_ number: Int) -> String {
    switch number {
    case 10_000...:
        return "\(number / 10_000)万"
    case 1_000...:
        return "\(number / 1_000)k"
    default:
        return "\(number)"
    }
}

#Preview {
    ContentView()
}

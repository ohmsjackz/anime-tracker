import SwiftUI

// MARK: - Models

enum AnimeStatus: String, CaseIterable, Codable, Identifiable {
    case watching = "Watching"
    case plan = "Plan to Watch"
    case completed = "Completed"
    case hold = "On Hold"
    case dropped = "Dropped"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .watching: return "play.circle.fill"
        case .plan: return "bookmark.fill"
        case .completed: return "checkmark.circle.fill"
        case .hold: return "pause.circle.fill"
        case .dropped: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .watching: return .blue
        case .plan: return .orange
        case .completed: return .green
        case .hold: return .yellow
        case .dropped: return .red
        }
    }
}

struct AnimeEntry: Identifiable, Codable, Equatable {
    var id: Int
    var title: String
    var coverURL: String?
    var episodes: Int?
    var status: AnimeStatus
    var progress: Int
    var score: Double?
    var notes: String
    var updatedAt: Date
    
    init(id: Int, title: String, coverURL: String? = nil, episodes: Int? = nil,
         status: AnimeStatus = .plan, progress: Int = 0, score: Double? = nil, notes: String = "") {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.episodes = episodes
        self.status = status
        self.progress = progress
        self.score = score
        self.notes = notes
        self.updatedAt = Date()
    }
}

struct AniListMedia: Identifiable, Decodable {
    let id: Int
    let title: Title
    let coverImage: Cover?
    let episodes: Int?
    let averageScore: Int?
    let genres: [String]?
    
    struct Title: Decodable {
        let romaji: String?
        let english: String?
        var display: String { english ?? romaji ?? "Unknown" }
    }
    
    struct Cover: Decodable {
        let large: String?
        let medium: String?
    }
}

// MARK: - Store

@Observable
@MainActor
final class LibraryStore {
    var entries: [AnimeEntry] = []
    
    private let key = "animay.library.v1"
    
    init() { load() }
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AnimeEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func upsert(_ entry: AnimeEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        entries.sort { $0.updatedAt > $1.updatedAt }
        save()
    }
    
    func remove(id: Int) {
        entries.removeAll { $0.id == id }
        save()
    }
    
    func entry(for id: Int) -> AnimeEntry? {
        entries.first { $0.id == id }
    }
    
    func filtered(status: AnimeStatus?) -> [AnimeEntry] {
        guard let status else { return entries }
        return entries.filter { $0.status == status }
    }
    
    var stats: [(AnimeStatus, Int)] {
        AnimeStatus.allCases.map { status in
            (status, entries.filter { $0.status == status }.count)
        }
    }
}

// MARK: - AniList

class AniListService {
    static let shared = AniListService()
    private let endpoint = URL(string: "https://graphql.anilist.co")!
    
    func search(query: String) async throws -> [AniListMedia] {
        let gql = """
        query ($search: String) {
          Page(page: 1, perPage: 30) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              title { romaji english }
              coverImage { large medium }
              episodes
              averageScore
              genres
            }
          }
        }
        """
        return try await post(["query": gql, "variables": ["search": query]])
    }
    
    func trending() async throws -> [AniListMedia] {
        let gql = """
        query {
          Page(page: 1, perPage: 30) {
            media(type: ANIME, sort: TRENDING_DESC) {
              id
              title { romaji english }
              coverImage { large medium }
              episodes
              averageScore
              genres
            }
          }
        }
        """
        return try await post(["query": gql])
    }
    
    private func post(_ body: [String: Any]) async throws -> [AniListMedia] {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        struct Root: Decodable {
            struct DataBox: Decodable {
                struct Page: Decodable { let media: [AniListMedia] }
                let Page: Page
            }
            let data: DataBox
        }
        return try JSONDecoder().decode(Root.self, from: data).data.Page.media
    }
}

// MARK: - Root

struct ContentView: View {
    @State private var store = LibraryStore()
    
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "square.grid.2x2.fill")
                }
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            
            ProfileView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle.fill")
                }
        }
        .environment(store)
    }
}

// MARK: - Library

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var filter: AnimeStatus? = nil
    @State private var selected: AnimeEntry?
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            FilterPill(title: "All", isSelected: filter == nil) {
                                filter = nil
                            }
                            ForEach(AnimeStatus.allCases) { status in
                                FilterPill(title: status.rawValue, isSelected: filter == status) {
                                    filter = status
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    let items = store.filtered(status: filter)
                    
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label("No Anime", systemImage: "tv")
                        } description: {
                            Text("Search for shows and add them to your library.")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(items) { entry in
                                Button {
                                    selected = entry
                                } label: {
                                    LibraryCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selected) { entry in
                DetailView(entry: entry)
            }
        }
    }
}

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LibraryCard: View {
    let entry: AnimeEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                CoverImage(urlString: entry.coverURL)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                
                if let total = entry.episodes, total > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.black.opacity(0.35))
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(entry.progress) / CGFloat(max(total, 1)))
                            }
                            .frame(height: 3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 4) {
                    Image(systemName: entry.status.icon)
                        .font(.caption2)
                    Text(entry.status.rawValue)
                        .font(.caption)
                }
                .foregroundStyle(entry.status.color)
                
                if let score = entry.score {
                    Text(String(format: "%.1f", score))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @State private var results: [AniListMedia] = []
    @State private var trending: [AniListMedia] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMedia: AniListMedia?
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Something went wrong", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(results.isEmpty ? trending : results) { media in
                                Button {
                                    selectedMedia = media
                                } label: {
                                    SearchCard(media: media, inLibrary: store.entry(for: media.id) != nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Anime")
            .onSubmit(of: .search) {
                Task { await doSearch() }
            }
            .onChange(of: query) { newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results = []
                }
            }
            .task { await loadTrending() }
            .sheet(item: $selectedMedia) { media in
                if let existing = store.entry(for: media.id) {
                    DetailView(entry: existing)
                } else {
                    AddAnimeView(media: media)
                }
            }
        }
    }
    
    private func doSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await AniListService.shared.search(query: q)
        } catch {
            errorMessage = "Could not load results. Check your connection."
        }
    }
    
    private func loadTrending() async {
        do {
            trending = try await AniListService.shared.trending()
        } catch { }
    }
}

struct SearchCard: View {
    let media: AniListMedia
    let inLibrary: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                CoverImage(urlString: media.coverImage?.large ?? media.coverImage?.medium)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                
                if inLibrary {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.title3)
                        .padding(10)
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(media.title.display)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let score = media.averageScore {
                    Text("\(score)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shared Cover

struct CoverImage: View {
    let urlString: String?
    
    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        placeholder
                            .overlay { ProgressView() }
                    }
                }
            } else {
                placeholder
            }
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: "tv")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Detail

struct DetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var entry: AnimeEntry
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        CoverImage(urlString: entry.coverURL)
                            .frame(width: 110, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title)
                                .font(.title3.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if let eps = entry.episodes {
                                Text("\(eps) Episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Label(entry.status.rawValue, systemImage: entry.status.icon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(entry.status.color)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }
                
                Section {
                    Picker("Status", selection: $entry.status) {
                        ForEach(AnimeStatus.allCases) { status in
                            Label(status.rawValue, systemImage: status.icon)
                                .tag(status)
                        }
                    }
                    .onChange(of: entry.status) { _ in persist() }
                    
                    Stepper(value: $entry.progress, in: 0...(entry.episodes ?? 9999)) {
                        HStack {
                            Text("Episode")
                            Spacer()
                            Text("\(entry.progress)" + (entry.episodes.map { " / \($0)" } ?? ""))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .onChange(of: entry.progress) { _ in persist() }
                } header: {
                    Text("Progress")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Score")
                            Spacer()
                            Text(entry.score.map { String(format: "%.1f", $0) } ?? "-")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { entry.score ?? 0 },
                                set: { entry.score = $0 == 0 ? nil : $0 }
                            ),
                            in: 0...10,
                            step: 0.5
                        )
                        .tint(.blue)
                    }
                    .onChange(of: entry.score) { _ in persist() }
                } header: {
                    Text("Rating")
                }
                
                Section {
                    TextField("Add a note...", text: $entry.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: entry.notes) { _ in persist() }
                } header: {
                    Text("Notes")
                }
                
                Section {
                    Button(role: .destructive) {
                        store.remove(id: entry.id)
                        dismiss()
                    } label: {
                        Text("Remove from Library")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func persist() {
        entry.updatedAt = Date()
        store.upsert(entry)
    }
}

// MARK: - Add

struct AddAnimeView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let media: AniListMedia
    @State private var status: AnimeStatus = .plan
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        CoverImage(urlString: media.coverImage?.large ?? media.coverImage?.medium)
                            .frame(width: 90, height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(media.title.display)
                                .font(.headline)
                            
                            if let eps = media.episodes {
                                Text("\(eps) Episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let genres = media.genres, !genres.isEmpty {
                                Text(genres.prefix(3).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear)
                }
                
                Section {
                    Picker("Add to", selection: $status) {
                        ForEach(AnimeStatus.allCases) { s in
                            Label(s.rawValue, systemImage: s.icon)
                                .tag(s)
                        }
                    }
                }
                
                Section {
                    Button {
                        let entry = AnimeEntry(
                            id: media.id,
                            title: media.title.display,
                            coverURL: media.coverImage?.large ?? media.coverImage?.medium,
                            episodes: media.episodes,
                            status: status
                        )
                        store.upsert(entry)
                        dismiss()
                    } label: {
                        Text("Add to Library")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Anime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Profile

struct ProfileView: View {
    @Environment(LibraryStore.self) private var store
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("My Library")
                                .font(.title2.weight(.bold))
                            Text("\(store.entries.count) Titles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Library") {
                    ForEach(store.stats, id: \.0) { status, count in
                        HStack {
                            Label(status.rawValue, systemImage: status.icon)
                                .foregroundStyle(status.color)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                
                Section {
                    LabeledContent("Total Anime") {
                        Text("\(store.entries.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section {
                    Text("AniMay keeps your list on this device only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

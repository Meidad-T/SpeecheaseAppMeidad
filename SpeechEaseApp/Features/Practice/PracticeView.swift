import SwiftUI

struct PracticeView: View {
    @State private var sessions: [PracticeSession] = []
    @State private var showingCreateSheet = false
    @State private var editingSession: PracticeSession? = nil
    @State private var selectedSessionIdent: SessionIdent? = nil
    
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    
    @Environment(\.sizeCategory) var sizeCategory
    @Environment(\.horizontalSizeClass) var sizeClass
    
    struct SessionIdent: Identifiable {
        let id: UUID
    }
    
    var columns: [GridItem] {
        if sizeClass == .regular {
            return [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
        } else {
            return [GridItem(.flexible(), spacing: 20)]
        }
    }
    
    var filteredSessions: [PracticeSession] {
        var result = sessions
        
        if selectedFilter != "All" {
            result = result.filter { session in
                if selectedFilter == "Strict" {
                   return session.enforceTimeLimit
                } else {
                    return session.foci.contains { $0.title.contains(selectedFilter) }
                }
            }
        }
        
        if !searchText.isEmpty {
            result = result.filter { session in
                session.name.localizedCaseInsensitiveContains(searchText) ||
                session.foci.contains { $0.title.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        return result
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Practice")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button(action: { showingCreateSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .fontWeight(.bold)
                                Text("New")
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search sessions...", text: $searchText)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let filters = ["All", "Vocal Control", "Body Language", "Interview Prep", "Strict"]
                            ForEach(filters, id: \.self) { filter in
                                Text(filter)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedFilter == filter ? Color.accentColor : Color.accentColor.opacity(0.1))
                                    .foregroundStyle(selectedFilter == filter ? .white : Color.accentColor)
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        withAnimation {
                                            selectedFilter = filter
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                .background(Color(UIColor.systemGroupedBackground))
                .zIndex(1)
                
                if sessions.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor.opacity(0.6))
                        Text("No Practice Sessions")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Create a custom session to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredSessions) { session in
                                let isLocked = false
                                
                                Button {
                                    if isLocked {
                                    } else {
                                        selectedSessionIdent = SessionIdent(id: session.id)
                                    }
                                } label: {
                                    SessionCard(session: session)
                                        .overlay(
                                            ZStack {
                                                if isLocked {
                                                    Color.black.opacity(0.4)
                                                        .cornerRadius(24)
                                                    
                                                    VStack(spacing: 8) {
                                                        Image(systemName: "lock.fill")
                                                            .font(.largeTitle)
                                                            .foregroundStyle(.white)
                                                        
                                                        Text("Coming Soon")
                                                            .font(.caption)
                                                            .fontWeight(.bold)
                                                            .foregroundStyle(.white)
                                                            .padding(.horizontal, 12)
                                                            .padding(.vertical, 6)
                                                            .background(.ultraThinMaterial, in: Capsule())
                                                    }
                                                }
                                            }
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(isLocked)
                                .contextMenu {
                                    Button {
                                        editSession(session)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        deleteSession(session)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedSessionIdent) { ident in
            if let index = sessions.firstIndex(where: { $0.id == ident.id }) {
                PracticeSessionView(session: $sessions[index]) { updatedSession in
                    saveSessions()
                }
            } else {
                 Text("Error: Session not found")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePracticeSessionView { newSession in
                sessions.append(newSession)
                saveSessions()
            }
        }
        .sheet(item: $editingSession) { session in
            CreatePracticeSessionView(sessionToEdit: session) { updatedSession in
                if let index = sessions.firstIndex(where: { $0.id == updatedSession.id }) {
                    sessions[index] = updatedSession
                    saveSessions()
                }
            }
        }
        .onAppear(perform: loadSessions)
    }
    
    private func editSession(_ session: PracticeSession) {
        editingSession = session
    }
    
    private func deleteSession(_ session: PracticeSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if !session.history.isEmpty {
                var historyToArchive = session.history
                for i in 0..<historyToArchive.count {
                    historyToArchive[i].sessionName = session.name
                }
                
                var archived: [PracticeAttempt] = []
                if let data = UserDefaults.standard.data(forKey: "archivedPracticeHistory"),
                   let decoded = try? JSONDecoder().decode([PracticeAttempt].self, from: data) {
                    archived = decoded
                }
                
                archived.append(contentsOf: historyToArchive)
                if let encoded = try? JSONEncoder().encode(archived) {
                    UserDefaults.standard.set(encoded, forKey: "archivedPracticeHistory")
                }
            }
            
            withAnimation {
                sessions.remove(at: index)
                saveSessions()
            }
        }
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: "savedPracticeSessions")
        }
    }
    
    private func loadSessions() {
        guard sessions.isEmpty else { return }
        
        if let data = UserDefaults.standard.data(forKey: "savedPracticeSessions"),
           let decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
            sessions = decoded
        }
    }
}

// MARK: - Session Display Card
struct SessionCard: View {
    let session: PracticeSession
    @Environment(\.horizontalSizeClass) var sizeClass

    var body: some View {
        let isIPad = sizeClass == .regular
        let primaryFocus = session.foci.first ?? .vocal
        let displayIcon = session.customIcon ?? (session.foci.count > 1 ? "square.grid.2x2.fill" : primaryFocus.icon)

        ZStack {
            GeometryReader { proxy in
                Image(systemName: displayIcon)
                    .font(.system(size: proxy.size.height * 0.8))
                    .foregroundColor(.white.opacity(0.1))
                    .rotationEffect(.degrees(-15))
                    .offset(x: proxy.size.width * 0.6, y: proxy.size.height * 0.2)
            }
            .clipped()

            HStack(spacing: 20) {
                Image(systemName: displayIcon)
                    .font(.system(size: isIPad ? 48 : 32))
                    .foregroundColor(.white)
                    .padding(.leading, 10)
                    .frame(width: isIPad ? 80 : 50)

                VStack(alignment: .leading, spacing: isIPad ? 12 : 6) {
                    Text(session.name)
                        .font(isIPad ? .title : .title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Focus indicator row
                    HStack(spacing: 8) {
                        if session.foci.count > 1 {
                            // Show tiny icons for each focus
                            HStack(spacing: 4) {
                                ForEach(session.foci.prefix(5)) { focus in
                                    Image(systemName: focus.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                if session.foci.count > 5 {
                                    Text("+\(session.foci.count - 5)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption2)
                                Text(primaryFocus.title)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }

                        if let limit = session.timeLimitMinutes {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.caption2)
                                Text("\(limit) min")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    if let date = session.createdDate {
                        Text("Created " + date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    if session.enforceTimeLimit {
                        Text("Strict Mode")
                            .font(.caption2)
                            .italic()
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.trailing)
            }
            .padding()
        }
        .frame(height: isIPad ? 200 : 100)
        .background(
            ZStack {
                session.displayColor
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(24)
        .shadow(color: session.displayColor.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

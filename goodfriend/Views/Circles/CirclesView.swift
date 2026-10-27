import SwiftUI

struct CirclesView: View {
    @StateObject private var repo = CirclesRepository.shared
    @EnvironmentObject private var authService: AuthService

    @State private var showCreateCircle = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(repo.circles) { circle in
                        NavigationLink(value: circle) {
                            CircleCardView(circle: circle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Circles")
            .navigationDestination(for: Circle.self) { circle in
                CircleDetailView(circle: circle)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("New Circle", systemImage: "plus") {
                        showCreateCircle = true
                    }
                }
            }
            .overlay {
                if repo.circles.isEmpty {
                    ContentUnavailableView(
                        "No Circles yet",
                        systemImage: "circle.hexagongrid",
                        description: Text("Create a Circle to group your contacts — Family, Coworkers, Gym Friends…")
                    )
                }
            }
            .refreshable { try? await repo.fetchAll() }
        }
        .sheet(isPresented: $showCreateCircle) {
            CreateCircleSheet()
        }
        .task { try? await repo.fetchAll() }
    }
}

// MARK: – Card

struct CircleCardView: View {
    let circle: Circle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(circle.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(circle.color)
                    .frame(width: 12, height: 12)
            }

            // Member avatar stack (up to 5)
            HStack(spacing: -8) {
                ForEach(circle.members.prefix(5)) { member in
                    ContactAvatarView(contact: member, size: 32)
                        .overlay(SwiftUI.Circle().stroke(Color.systemBackground, lineWidth: 2))
                }
                if circle.members.count > 5 {
                    Text("+\(circle.members.count - 5)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            }

            Text("\(circle.members.count) members")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(circle.viewMode == .tree ? "Tree" : "List", systemImage: circle.viewMode == .tree ? "point.3.connected.trianglepath.dotted" : "list.bullet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .cardStyle()
    }
}

// MARK: – Create Circle sheet

struct CreateCircleSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService

    @State private var name = ""
    @State private var colorHex = "#4F8EF7"
    @State private var viewMode: Circle.ViewMode = .list

    private let palette = ["#4F8EF7","#FF6B6B","#51CF66","#FAB005","#CC5DE8","#339AF0","#FF922B","#20C997"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Circle name", text: $name)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(palette, id: \.self) { hex in
                            SwiftUI.Circle()
                                .fill(Color(hex: hex) ?? .blue)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("View") {
                    Picker("View mode", selection: $viewMode) {
                        Text("List").tag(Circle.ViewMode.list)
                        Text("Tree").tag(Circle.ViewMode.tree)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Circle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createCircle() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createCircle() {
        guard let userId = authService.currentUserId else { return }
        let circle = Circle(userId: userId, name: name.trimmingCharacters(in: .whitespaces), colorHex: colorHex, viewMode: viewMode)
        Task {
            try? await CirclesRepository.shared.upsert(circle)
            await CirclesRepository.shared.autoAssign(
                circle: circle,
                contacts: ContactsRepository.shared.contacts
            )
            dismiss()
        }
    }
}

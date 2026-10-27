import SwiftUI

struct CircleDetailView: View {
    @State private var circle: Circle
    @State private var members: [Contact] = []
    @State private var showAddMember = false
    @EnvironmentObject private var authService: AuthService

    init(circle: Circle) {
        _circle = State(initialValue: circle)
    }

    var body: some View {
        Group {
            if circle.viewMode == .tree {
                treeView
            } else {
                listView
            }
        }
        .navigationTitle(circle.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Add member", systemImage: "person.badge.plus") {
                    showAddMember = true
                }
            }
        }
        .sheet(isPresented: $showAddMember) {
            AddMemberSheet(circle: circle, existingMemberIds: Set(members.map(\.id))) { contact in
                members.append(contact)
            }
        }
        .task { await loadMembers() }
    }

    // ─────────────────────────────────────────
    // List view
    // ─────────────────────────────────────────

    private var listView: some View {
        List {
            ForEach(members) { contact in
                NavigationLink(value: contact) {
                    ContactRowView(contact: contact)
                }
            }
            .onDelete { indexSet in
                Task {
                    for i in indexSet {
                        try? await CirclesRepository.shared.removeMember(
                            contactId: members[i].id,
                            fromCircle: circle.id
                        )
                    }
                    members.remove(atOffsets: indexSet)
                }
            }
        }
        .navigationDestination(for: Contact.self) { ContactDetailView(contact: $0) }
        .overlay {
            if members.isEmpty {
                ContentUnavailableView("No members yet", systemImage: "person.3", description: Text("Tap + to add someone."))
            }
        }
    }

    // ─────────────────────────────────────────
    // Tree (node graph) view — simplified canvas rendering
    // ─────────────────────────────────────────

    private var treeView: some View {
        ScrollView([.horizontal, .vertical]) {
            Canvas { ctx, size in
                // Simple radial layout: root at center, members around it
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius: CGFloat = min(size.width, size.height) * 0.35
                let count = members.count

                for (i, _) in members.enumerated() {
                    let angle = (2 * Double.pi / Double(max(count, 1))) * Double(i) - .pi / 2
                    let end = CGPoint(
                        x: center.x + radius * CGFloat(cos(angle)),
                        y: center.y + radius * CGFloat(sin(angle))
                    )
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: end)
                    ctx.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
                }
            }
            .overlay {
                GeometryReader { geo in
                    let size = geo.size
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius: CGFloat = min(size.width, size.height) * 0.35
                    let count = members.count

                    // Center node (circle name)
                    CircleNodeView(label: circle.name, color: circle.color, isRoot: true)
                        .position(center)

                    ForEach(Array(members.enumerated()), id: \.element.id) { i, member in
                        let angle = (2 * Double.pi / Double(max(count, 1))) * Double(i) - .pi / 2
                        let pos = CGPoint(
                            x: center.x + radius * CGFloat(cos(angle)),
                            y: center.y + radius * CGFloat(sin(angle))
                        )
                        CircleNodeView(label: member.name, color: circle.color, isRoot: false)
                            .position(pos)
                    }
                }
            }
            .frame(width: 500, height: 500)
        }
    }

    private func loadMembers() async {
        members = (try? await CirclesRepository.shared.fetchMembers(forCircle: circle.id)) ?? []
    }
}

// MARK: – Node

struct CircleNodeView: View {
    let label: String
    let color: Color
    let isRoot: Bool

    var body: some View {
        VStack(spacing: 4) {
            SwiftUI.Circle()
                .fill(isRoot ? color : color.opacity(0.2))
                .frame(width: isRoot ? 56 : 40, height: isRoot ? 56 : 40)
                .overlay {
                    Text(initials)
                        .font(.system(size: isRoot ? 18 : 14, weight: .semibold))
                        .foregroundStyle(isRoot ? .white : color)
                }
            Text(label)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private var initials: String {
        label.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined().uppercased()
    }
}

// MARK: – Add member picker

struct AddMemberSheet: View {
    let circle: Circle
    let existingMemberIds: Set<UUID>
    let onAdd: (Contact) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService
    @StateObject private var contactsRepo = ContactsRepository.shared
    @State private var searchText = ""

    var eligible: [Contact] {
        let base = contactsRepo.contacts.filter { !existingMemberIds.contains($0.id) }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(eligible) { contact in
                Button {
                    Task {
                        guard let userId = authService.currentUserId else { return }
                        try? await CirclesRepository.shared.addMember(
                            contactId: contact.id,
                            toCircle: circle.id,
                            userId: userId
                        )
                        onAdd(contact)
                        dismiss()
                    }
                } label: {
                    ContactRowView(contact: contact)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Add to \(circle.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

import Contacts
import SwiftUI

struct ContactImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService

    @State private var cnContacts: [CNContact] = []
    @State private var selected: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var permissionDenied = false

    var filtered: [CNContact] {
        guard !searchText.isEmpty else { return cnContacts }
        return cnContacts.filter {
            ($0.givenName + " " + $0.familyName)
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if permissionDenied {
                    ContentUnavailableView(
                        "Contacts Access Denied",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text("Enable access in Settings > Privacy > Contacts.")
                    )
                } else if isLoading {
                    ProgressView("Loading contacts…")
                } else {
                    List(filtered, id: \.identifier) { contact in
                        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                        HStack {
                            Text(fullName.isEmpty ? "(No name)" : fullName)
                            Spacer()
                            if selected.contains(contact.identifier) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.accent)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(contact.identifier) {
                                selected.remove(contact.identifier)
                            } else {
                                selected.insert(contact.identifier)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search iPhone contacts")
                }
            }
            .navigationTitle("Import Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(selected.count))") { importSelected() }
                        .disabled(selected.isEmpty || isImporting)
                }
            }
        }
        .task { await fetchCNContacts() }
    }

    // ─────────────────────────────────────────
    // CNContactStore
    // ─────────────────────────────────────────

    private func fetchCNContacts() async {
        let store = CNContactStore()
        do {
            try await store.requestAccess(for: .contacts)
        } catch {
            permissionDenied = true
            isLoading = false
            return
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        var results: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                results.append(contact)
            }
            cnContacts = results
        } catch {
            print("CNContact fetch error:", error)
        }
        isLoading = false
    }

    private func importSelected() {
        guard let userId = authService.currentUserId else { return }
        isImporting = true

        let toImport = cnContacts.filter { selected.contains($0.identifier) }
        Task {
            for cn in toImport {
                let fullName = "\(cn.givenName) \(cn.familyName)".trimmingCharacters(in: .whitespaces)
                guard !fullName.isEmpty else { continue }

                var contact = Contact(userId: userId, name: fullName)
                contact.phone = cn.phoneNumbers.first?.value.stringValue
                contact.email = cn.emailAddresses.first?.value as String?

                // Upload thumbnail if available
                // (For brevity, photo upload to Supabase Storage is wired separately)

                try? await ContactsRepository.shared.upsert(contact)
            }
            isImporting = false
            dismiss()
        }
    }
}

import SwiftUI
#if os(iOS)
import MessageUI
#endif

struct ReminderDetailView: View {
    let reminder: Reminder
    @Environment(\.dismiss) var dismiss

    @State private var draftMessage: String
    @State private var showMessageComposer = false
    @State private var copiedToClipboard = false

    init(reminder: Reminder) {
        self.reminder = reminder
        _draftMessage = State(initialValue: reminder.draftMessage ?? "Hey! Just thinking of you 👋")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header card
                    VStack(alignment: .leading, spacing: 8) {
                        if let contact = reminder.contact {
                            Label(contact.name, systemImage: "person.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color.accent)
                        }

                        Text(reminder.title)
                            .font(.title2.bold())

                        Label(reminder.dueDate.shortFormatted, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    // Draft message editor
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Message draft")
                            .font(.headline)

                        TextEditor(text: $draftMessage)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding()

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = draftMessage
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(draftMessage, forType: .string)
                            #endif
                            copiedToClipboard = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToClipboard = false }
                        } label: {
                            Label(copiedToClipboard ? "Copied!" : "Copy message", systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.accent)

                        #if os(iOS)
                        if MFMessageComposeViewController.canSendText(),
                           let phone = reminder.contact?.phone {
                            Button {
                                openMessages(phone: phone)
                            } label: {
                                Label("Open in Messages", systemImage: "message.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        #endif
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    #if os(iOS)
    private func openMessages(phone: String) {
        // Deep-link to Messages with the contact's phone pre-filled.
        // Note: sms:// only pre-fills the recipient; the body must be pasted by the user.
        let encoded = draftMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let smsURL = "sms:\(phone)&body=\(encoded)"
        if let url = URL(string: smsURL), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    #endif
}

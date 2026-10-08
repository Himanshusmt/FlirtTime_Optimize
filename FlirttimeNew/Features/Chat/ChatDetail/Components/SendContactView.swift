//
//  SendContactView.swift
//  FlirttimeNew
//
//  Device contact picker used to share a contact card in chat.
//

import SwiftUI
import Contacts

struct SendContactView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contactFetcher = ContactFetcher()
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedContactForNumberChoice: ContactData?
    @State private var showNumberChooser = false
    @State private var permissionDenied = false

    let onContactSelected: (ContactData) -> Void

    private var filteredContacts: [ContactData] {
        guard !searchText.isEmpty else { return contactFetcher.contacts }
        let lower = searchText.lowercased()
        return contactFetcher.contacts.filter { contact in
            contact.name.lowercased().contains(lower)
                || contact.phoneNumbers.contains { $0.lowercased().contains(lower) }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar

                if isLoading {
                    loadingView
                } else if permissionDenied {
                    permissionDeniedView
                } else if contactFetcher.contacts.isEmpty {
                    emptyView
                } else {
                    contactsList
                }
            }
            .background(Color.chatBackground)
            .navigationTitle(ChatStrings.chat_shareContact.localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        SwiftUI.Image(ChatAssets.back)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .onAppear(perform: loadContacts)
            .confirmationDialog(
                ChatStrings.chat_selectNumber.localizedString(),
                isPresented: $showNumberChooser,
                titleVisibility: .visible,
                presenting: selectedContactForNumberChoice
            ) { contact in
                ForEach(contact.phoneEntries) { entry in
                    Button("\(entry.label): \(entry.number)") {
                        onContactSelected(ContactData(name: contact.name, phoneEntries: [entry]))
                        dismiss()
                    }
                }
                Button(ChatStrings.chat_cancel.localizedString(), role: .cancel) {}
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            SwiftUI.Image(systemName: "magnifyingglass")
                .foregroundColor(.chatTextTertiary)

            TextField(ChatStrings.chat_searchContacts.localizedString(), text: $searchText)
                .font(.chat(.regular, size: 16))
                .foregroundColor(.chatTextPrimary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    SwiftUI.Image(ChatAssets.close)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.chatTextSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.chatSurface))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.chatPrimary)

            Text(ChatStrings.chat_loadingContacts.localizedString())
                .font(.chat(.regular, size: 16))
                .foregroundColor(.chatTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            SwiftUI.Image(ChatAssets.contact)
                .renderingMode(.template)
                .resizable()
                .frame(width: 56, height: 56)
                .foregroundColor(.chatPrimary.opacity(0.6))

            Text(ChatStrings.chat_noContactsFound.localizedString())
                .font(.chat(.semibold, size: 18))
                .foregroundColor(.chatTextPrimary)

            Text(ChatStrings.chat_allowContactAccessMessage.localizedString())
                .font(.chat(.regular, size: 14))
                .foregroundColor(.chatTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            SwiftUI.Image(ChatAssets.contact)
                .renderingMode(.template)
                .resizable()
                .frame(width: 56, height: 56)
                .foregroundColor(.chatPrimary)

            Text(ChatStrings.chat_allowContactAccessMessage.localizedString())
                .font(.chat(.semibold, size: 18))
                .foregroundColor(.chatTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text(ChatStrings.chat_openSettings.localizedString())
                    .font(.chat(.semibold, size: 16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.chatPrimary))
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contactsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredContacts) { contact in
                    ContactRow(contact: contact) {
                        if contact.phoneEntries.count <= 1 {
                            onContactSelected(contact)
                            dismiss()
                        } else {
                            selectedContactForNumberChoice = contact
                            showNumberChooser = true
                        }
                    }

                    Divider()
                        .padding(.leading, 82)
                }
            }
            .padding(.top, 4)
        }
    }

    private func loadContacts() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted {
            permissionDenied = true
            isLoading = false
            return
        }
        contactFetcher.fetchContacts { granted in
            isLoading = false
            permissionDenied = !granted
        }
    }
}

struct ContactRow: View {
    let contact: ContactData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.chatPrimarySoft)
                        .frame(width: 50, height: 50)

                    Text(String(contact.name.prefix(1)).uppercased())
                        .font(.chat(.semibold, size: 20))
                        .foregroundColor(.chatPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.chat(.semibold, size: 16))
                        .foregroundColor(.chatTextPrimary)

                    if let first = contact.phoneEntries.first {
                        Text(first.number)
                            .font(.chat(.regular, size: 14))
                            .foregroundColor(.chatTextSecondary)
                    }

                    if contact.phoneEntries.count > 1 {
                        Text("+\(contact.phoneEntries.count - 1) \(ChatStrings.chat_moreNumbers.localizedString())")
                            .font(.chat(.regular, size: 12))
                            .foregroundColor(.chatPrimary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContactData: Identifiable {
    struct PhoneEntry: Identifiable, Equatable {
        let id = UUID().uuidString
        let label: String
        let number: String
    }

    let id = UUID().uuidString
    let name: String
    let phoneEntries: [PhoneEntry]
    var phoneNumbers: [String] { phoneEntries.map(\.number) }

    init(name: String, phoneEntries: [PhoneEntry]) {
        self.name = name.isEmpty ? "Unknown" : name
        self.phoneEntries = phoneEntries
    }
}

final class ContactFetcher: ObservableObject {
    @Published var contacts: [ContactData] = []

    private let contactStore = CNContactStore()

    /// Calls `completion` on the main queue with whether access was granted.
    func fetchContacts(completion: @escaping (Bool) -> Void) {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            loadContacts(completion: completion)
        case .notDetermined:
            contactStore.requestAccess(for: .contacts) { [weak self] granted, _ in
                if granted {
                    self?.loadContacts(completion: completion)
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { completion(false) }
        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    private func loadContacts(completion: @escaping (Bool) -> Void) {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var allContacts: [ContactData] = []
            var seenIdentifiers = Set<String>()
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
                try self.contactStore.enumerateContacts(with: request) { contact, _ in
                    guard seenIdentifiers.insert(contact.identifier).inserted else { return }

                    // Built from fetched keys only; CNContactFormatter would need extra keys.
                    let name = [contact.givenName, contact.middleName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    let phoneEntries: [ContactData.PhoneEntry] = contact.phoneNumbers.compactMap { labeled in
                        let number = labeled.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !number.isEmpty else { return nil }
                        let label = CNLabeledValue<NSString>.localizedString(forLabel: labeled.label ?? CNLabelPhoneNumberMobile)
                        return ContactData.PhoneEntry(label: label, number: number)
                    }

                    guard !phoneEntries.isEmpty else { return }
                    allContacts.append(ContactData(name: name, phoneEntries: phoneEntries))
                }

                allContacts.sort { $0.name.lowercased() < $1.name.lowercased() }
                DispatchQueue.main.async {
                    self.contacts = allContacts
                    completion(true)
                }
            } catch {
                AppLogger.debug("Error fetching contacts: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}

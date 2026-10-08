//
//  LiveTranslationLanguages.swift
//  FlirttimeNew
//
//  Preferred-language ids used by chat message translate
//  (matches Android `LiveTranslationLanguages` / web LIVE_TRANSLATION_LANGUAGES).
//

import Foundation

enum LiveTranslationLanguages {

    struct Entry: Equatable {
        let id: String
        let code: String
        let label: String
    }

    static let all: [Entry] = [
        Entry(id: "English", code: "en", label: "English"),
        Entry(id: "Russian", code: "ru", label: "Русский"),
        Entry(id: "Ukrainian", code: "uk", label: "Україна"),
        Entry(id: "Polish", code: "pl", label: "Polski"),
        Entry(id: "Chinese", code: "zh", label: "中国"),
        Entry(id: "Japanese", code: "ja", label: "日本"),
        Entry(id: "Turkish", code: "tr", label: "Türkçe"),
        Entry(id: "Spanish", code: "es", label: "Español"),
        Entry(id: "German", code: "de", label: "Deutsch"),
        Entry(id: "Korean", code: "ko", label: "한국어"),
        Entry(id: "Portuguese", code: "pt", label: "Portugal"),
        Entry(id: "Italian", code: "it", label: "Italiano"),
        Entry(id: "French", code: "fr", label: "Français"),
        Entry(id: "Arabic", code: "ar", label: "العربية"),
        Entry(id: "Uzbek", code: "uz", label: "Oʻzbekiston"),
        Entry(id: "Kazakh", code: "kk", label: "Қазақстан"),
        Entry(id: "Hindi", code: "hi", label: "हिन्दी"),
    ]

    private static let aliases: [String: String] = [
        "ukraine": "Ukrainian",
        "japan": "Japanese",
        "portugal": "Portuguese",
        "portuguese": "Portuguese",
        "україна": "Ukrainian",
        "日本": "Japanese",
    ]

    static func filtered(query: String) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        let needle = trimmed.lowercased()
        return all.filter {
            $0.id.lowercased().contains(needle)
                || $0.code.lowercased().contains(needle)
                || $0.label.lowercased().contains(needle)
        }
    }

    static func label(for idOrCode: String?) -> String {
        resolve(idOrCode)?.label ?? (idOrCode ?? "")
    }

    static func code(from idOrCode: String?, fallback: String = "en") -> String {
        resolve(idOrCode)?.code ?? fallback
    }

    static func resolve(_ raw: String?) -> Entry? {
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return nil }

        if let byId = all.first(where: { $0.id.compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return byId
        }
        if let byCode = all.first(where: { $0.code.compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return byCode
        }
        if let byLabel = all.first(where: { $0.label.compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return byLabel
        }
        if let aliasId = aliases[key.lowercased()] {
            return all.first(where: { $0.id == aliasId })
        }
        return nil
    }
}

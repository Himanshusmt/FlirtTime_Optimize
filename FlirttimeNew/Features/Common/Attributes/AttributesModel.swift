//
//  AttributesModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 25/11/24.
//

import Foundation

// MARK: - AttributesModel
struct AttributesModel: Codable {
    let status: Bool?
    let message: String?
    let data: [AttributesData]?
}

// MARK: - AttributesData
struct AttributesData: Codable {
    let id: Int?
    let alias: String?
    let title: String?
    let photo: String?
    let question: String?
    let isCompleted: Int?
    let selection_type: String?
    var aOptions: [attOptions]?

    enum CodingKeys: String, CodingKey {
        case id, alias, title, photo, question, isCompleted, selection_type, aOptions = "options"

    }
}

struct attOptions: Codable {
    let id: Int?
    let attribute_id: String?
    let title: String?
    var isSelected: Bool?
    let photo: String?
    
    enum CodingKeys: String, CodingKey {
        case id, attribute_id, title, isSelected,photo
    }
    
}

struct FilteredResult {
    let dataId: Int?
    let dataAlias: String?
    let selection_type: String?
    let selectedOptions: [attOptions]
}

//
//  CountryListModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 27/04/24.
//

import Foundation

struct CountryListModel:Decodable {
    let name : String?
    let dial_code: String?
    let code: String?
    let digit: String?
    var isSelected: Bool?
}

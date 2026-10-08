//
//  AttributesViewModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 25/11/24.
//

import UIKit

class AttributesViewModel: NSObject {
    
    @Published var statusFalse:String?
    @Published var errorMessage:String?
    @Published var aAttributesModel:AttributesModel?
    
    
    
    func loadJSON() {
        guard let fileURL = Bundle.main.url(forResource: "Attributes", withExtension: "json") else {
            print("JSON file not found")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let attributes = try decoder.decode(AttributesModel.self, from: data)
            
            if attributes.status ?? false {
                self.aAttributesModel = attributes
            } else {
                self.statusFalse = attributes.message
            }
            
        } catch {
            print("Error decoding JSON: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }


}

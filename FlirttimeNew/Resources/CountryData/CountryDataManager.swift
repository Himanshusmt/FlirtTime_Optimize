//
//  CountryManager.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 27/04/24.
//

import Foundation

class CountryDataManager {
    static let shared = CountryDataManager()
    var regionCode:String?
    var countries: [CountryListModel] = []
    var filterCountryData:CountryListModel?

    private init() {
        self.regionCode = self.getUserCountryRegion()
        self.loadCountries()
    }

    private func getUserCountryRegion() -> String? {
        guard let currentLocale = Locale.current.regionCode else {
            return nil
        }
        return currentLocale
    }

    private func loadCountries() {
        if let path = Bundle.main.path(forResource: "countryCodes", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let decoder = JSONDecoder()
                self.countries = try decoder.decode([CountryListModel].self, from: data)
                self.filterUserRegion()
                print(countries)
            } catch {
                print("Error decoding JSON: \(error)")
            }
        }
    }

    func filterUserRegion(){
        self.filterCountryData = self.countries.first(where: {$0.code == self.regionCode})
    }
}

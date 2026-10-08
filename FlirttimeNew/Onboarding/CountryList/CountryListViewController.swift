//
//  CountryListViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 27/04/24.
//

import UIKit

class CountryListViewController: UIViewController,Instantiable {

    @IBOutlet weak var searchTextField: UITextField!
    @IBOutlet weak var countryListTableView: UITableView!
    static var storyboardName: StringConvertible {
        return StoryboardName.login
    }
    var filteredListData: [CountryListModel]?
    var countries:[CountryListModel] = []
    var regionCode:String?
    var selectionCallBack:((CountryListModel)->())?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
    }

    func setUI(){
        searchTextField.placeholder = "Search or select your country."
        searchTextField.setPlaceholderColor(AppColor.MineShaft)
        self.setupTableView()
        self.filterSelectedRegion()
    }

    func filterSelectedRegion(){
        self.countries = CountryDataManager.shared.countries.map({ data in
            var object = data
            object.isSelected = object.code == self.regionCode ? true : false
            return object
        })
        self.filteredListData = self.countries
        self.countryListTableView.reloadData()

    }

    //MARK: - Private func tableViewSetup
    private func setupTableView(){
        self.countryListTableView.register(UINib(nibName: "CountryListTVC", bundle: nil), forCellReuseIdentifier: "CountryListTVC")
        self.countryListTableView.delegate = self
        self.countryListTableView.dataSource = self
    }

    @IBAction func searchCountryTF(_ sender: UITextField) {
        self.filteredListData?.removeAll()
        if self.searchTextField.text?.count != 0 {
            self.countries.forEach({ data in
                let range = data.name?.lowercased().range(of: searchTextField.text ?? "", options: NSString.CompareOptions.caseInsensitive, range: nil, locale: nil)
                if range != nil {
                    filteredListData?.append(data)
                }
            })
        } else {
            self.filteredListData = self.countries
        }
        DispatchQueue.main.async {
            self.countryListTableView.reloadData()
        }
    }

    @IBAction func continueButtonAction(_ sender: UIButton) {
        if let selectedCountryData = self.filteredListData?.first(where: {$0.isSelected == true}) {
            self.dismiss(animated: true) {
                guard let action = self.selectionCallBack else { return }
                action(selectedCountryData)
            }
        }
    }
    
}

extension CountryListViewController: UITableViewDelegate, UITableViewDataSource{

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filteredListData?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CountryListTVC", for: indexPath)as? CountryListTVC{
            let count = (self.filteredListData?.count ?? 0) - 1
            if count >= indexPath.row {
                cell.updateUI(data: self.filteredListData?[indexPath.row])
            }
            return cell
        }

        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath)as? CountryListTVC{
            self.filteredListData = self.filteredListData?.enumerated().map({ (index,data) in
                var object = data
                object.isSelected = index == indexPath.row ? true : false
                return object
            })
            DispatchQueue.main.async {
                self.countryListTableView.reloadData()
            }
        }
    }
}


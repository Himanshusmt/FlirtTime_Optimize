//
//  CountryListTVC.swift
//  Bank 316
//
//  Created by Dhairya on 25/08/23.
//

import UIKit



class CountryListTVC: UITableViewCell {
    
    @IBOutlet weak var countryFlagImage: UIImageView!
    @IBOutlet weak var countryNameLabel: UILabel!
    @IBOutlet weak var countrySelectionImage: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.selectionStyle = .none
    }
    
    //MARK: - Internal function for update UI
    internal func updateUI(data:CountryListModel?){
        self.countryFlagImage.image = UIImage(named:data?.code ?? "", in: Bundle.main, with: nil)
        self.countryNameLabel.text = data?.name ?? ""
        if data?.isSelected ?? false {
            self.countrySelectionImage.image = UIImage(named: "country_Selected")
        }else{
            self.countrySelectionImage.image = UIImage(named: "country_UnSelected")
        }
    }
}

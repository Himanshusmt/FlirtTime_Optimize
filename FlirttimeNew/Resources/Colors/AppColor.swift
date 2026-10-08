//
//  ViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit

// Colors names form: https://chir.ag/projects/name-that-color

enum AppColor {
    static let AppWhite = UIColor(named: "#FFFFFF") ?? #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
    static let AppBlack = UIColor(named: "#000000") ?? #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
    static let MineShaft = UIColor(named: "#252525") ?? #colorLiteral(red: 0.1450980392, green: 0.1450980392, blue: 0.1450980392, alpha: 1)
    static let Punch = UIColor(named: "#D92B2B") ?? #colorLiteral(red: 0.8509803922, green: 0.168627451, blue: 0.168627451, alpha: 1)
    static let MexicanRed = UIColor(named: "#AA2222") ?? #colorLiteral(red: 0.6666666667, green: 0.1333333333, blue: 0.1333333333, alpha: 1)
    static let Cherrywood = UIColor(named: "#6D1616") ?? #colorLiteral(red: 0.4274509804, green: 0.0862745098, blue: 0.0862745098, alpha: 1)
    static let Bombay = UIColor(named: "#B4B6B8") ?? #colorLiteral(red: 0.7058823529, green: 0.7137254902, blue: 0.7215686275, alpha: 1)
    static let Iron = UIColor(named: "#E3E5E5") ?? #colorLiteral(red: 0.8901960784, green: 0.8980392157, blue: 0.8980392157, alpha: 1)
    static let Carnation = UIColor(named: "#FA4D5E") ?? #colorLiteral(red: 0.9803921569, green: 0.3019607843, blue: 0.368627451, alpha: 1)
    static let BlueRibbon = UIColor(named: "#0F67FE") ?? #colorLiteral(red: 0.05882352941, green: 0.4039215686, blue: 0.9960784314, alpha: 1)
    static let ElectricViolet = UIColor(named: "#8A3FFC") ?? #colorLiteral(red: 0.5411764706, green: 0.2470588235, blue: 0.9882352941, alpha: 1)
    static let Amaranth = UIColor(named: "#E94057") ?? #colorLiteral(red: 0.9137254902, green: 0.2509803922, blue: 0.3411764706, alpha: 1)
    static let DoveGray = UIColor(named: "#646464") ?? #colorLiteral(red: 0.3921568627, green: 0.3921568627, blue: 0.3921568627, alpha: 1)
    static let Gallery = UIColor(named: "#EAEAEA") ?? #colorLiteral(red: 0.9176470588, green: 0.9176470588, blue: 0.9176470588, alpha: 1)
    static let SilverChalice = UIColor(named: "#9E9E9E") ?? #colorLiteral(red: 0.6196078431, green: 0.6196078431, blue: 0.6196078431, alpha: 1)
    static let Serenade = UIColor(named: "#FFF4E9") ?? #colorLiteral(red: 1, green: 0.9568627451, blue: 0.9137254902, alpha: 1)
    static let OceanGreen = UIColor(named: "#3BA575") ?? #colorLiteral(red: 0.231372549, green: 0.6470588235, blue: 0.4588235294, alpha: 1)
    static let CongressBlue = UIColor(named: "#004B8F") ?? #colorLiteral(red: 0, green: 0.2941176471, blue: 0.5607843137, alpha: 1)
    static let Boulder = UIColor(named: "#757575") ?? #colorLiteral(red: 0.4588235294, green: 0.4588235294, blue: 0.4588235294, alpha: 1)
    static let Lavenderblush = UIColor(named: "#FFECEF") ?? #colorLiteral(red: 1, green: 0.9254901961, blue: 0.937254902, alpha: 1)
    static let WildSand = UIColor(named: "#F5F5F5") ?? #colorLiteral(red: 0.9607843137, green: 0.9607843137, blue: 0.9607843137, alpha: 1)
    static let Silver = UIColor(named: "#C6C6C6") ?? #colorLiteral(red: 0.7764705882, green: 0.7764705882, blue: 0.7764705882, alpha: 1)
    static let CatskillWhite = UIColor(named: "#E2E8F0") ?? #colorLiteral(red: 0.8862745098, green: 0.9098039216, blue: 0.9411764706, alpha: 1)
    static let AthensGray = UIColor(named: "#F2F3F5") ?? #colorLiteral(red: 0.9490196078, green: 0.9529411765, blue: 0.9607843137, alpha: 1)
    static let BrightSun = UIColor(named: "#FFC746") ?? #colorLiteral(red: 1, green: 0.7803921569, blue: 0.2745098039, alpha: 1)
    static let SeaPink = UIColor(named: "#EDA0A8") ?? #colorLiteral(red: 0.9294117647, green: 0.6274509804, blue: 0.6588235294, alpha: 1)
    static let Portage = UIColor(named: "#98A1F1") ?? #colorLiteral(red: 0.5960784314, green: 0.631372549, blue: 0.9450980392, alpha: 1)
    static let Cherokee = UIColor(named: "#FBDC94") ?? #colorLiteral(red: 0.9843137255, green: 0.862745098, blue: 0.5803921569, alpha: 1)
    static let SeaPinkish = UIColor(named: "#EC9595") ?? #colorLiteral(red: 0.9254901961, green: 0.5843137255, blue: 0.5843137255, alpha: 1)
    static let DodgerBlue = UIColor(named: "#4278FC") ?? #colorLiteral(red: 0.2588235294, green: 0.4705882353, blue: 0.9882352941, alpha: 1)
    static let BorderTopWhite = UIColor(named: "#F3F3F3") ?? #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
    static let userViewBackground = UIColor(named: "#959595") ?? #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
    static let AlertBottomSuccess = UIColor(named: "#00CC64") ?? #colorLiteral(red: 0.521568656, green: 0.1098039225, blue: 0.05098039284, alpha: 1)
    static let AlertBottomFailure = UIColor(named: "#F04349") ?? #colorLiteral(red: 0.231372549, green: 0.6470588235, blue: 0.4588235294, alpha: 1)
    static let LabelBackgroundView = UIColor(named: "#D0D5DD") ?? #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
    static let LabelTextColor = UIColor(named: "#8C8C8C") ?? #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
    static let BackBlack10 = UIColor(named: "#000010") ?? #colorLiteral(red: 0.4588235294, green: 0.4588235294, blue: 0.4588235294, alpha: 1)
    static let ChatDateHeader = UIColor(named: "#44474E") ?? #colorLiteral(red: 0.4588235294, green: 0.4588235294, blue: 0.4588235294, alpha: 1)
    static let verifyPink = UIColor(named: "#FFDEDE") ?? #colorLiteral(red: 0.9294117647, green: 0.6274509804, blue: 0.6588235294, alpha: 1)
    static let RedBGMix = UIColor(named: "#FE4444") ?? #colorLiteral(red: 0.521568656, green: 0.1098039225, blue: 0.05098039284, alpha: 1)

}


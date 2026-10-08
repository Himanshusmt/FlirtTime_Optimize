//
//  Font.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 22/04/24.
//

import UIKit

extension UIFont {
    
    public enum Fredoka: String {
        case bold = "-SemiBold"
        case regular = "-Regular"
        case medium = "-Medium"
    }

    static func fredoka(_ type: Fredoka = .regular,
                            size: CGFloat = UIFont.systemFontSize) -> UIFont {
        return UIFont(name: "Fredoka\(type.rawValue)", size: size)!
    }
}


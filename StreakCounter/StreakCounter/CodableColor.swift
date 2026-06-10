//
//  CodableColor.swift
//  StreakCounter
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
        #else
        self.red = 1
        self.green = 1
        self.blue = 1
        self.alpha = 1
        #endif
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    // Pick black or white text so labels stay readable on any card color.
    var contrastingTextColor: Color {
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.6 ? .black : .white
    }

    static let white = CodableColor(red: 1, green: 1, blue: 1)
    static let appBackground = CodableColor(red: 250/255, green: 236/255, blue: 220/255)
}

//
//  View+NavTransition.swift
//  Luce
//
//  Created by samara on 30.01.2025.
//

import SwiftUI

extension View {
    @ViewBuilder
    func compatNavigationTransition(id: String, ns: Namespace.ID) -> some View {
        // In Swift 5.10/Xcode 15, we only return self since iOS 18 APIs aren't available
        self
    }
    
    @ViewBuilder
    func compatMatchedTransitionSource(id: String, ns: Namespace.ID) -> some View {
        // In Swift 5.10/Xcode 15, we only return self since iOS 18 APIs aren't available
        self
    }
}

//
//  NewsCardContainerView.swift
//  feather
//
//  Created by samara on 4.02.2025.
//

import SwiftUI

struct NewsCardContainerView: View {
    @Binding var isSheetPresented: Bool
    var news: NewsData
    @Namespace private var namespace
    
    let uuid = UUID().uuidString
    
    var body: some View {
        Button(action: {
            isSheetPresented = true
        }) {
            NewsCardView(news: news)
            .fullScreenCover(isPresented: $isSheetPresented) {
                CardContextMenuView(news: news)
                // Using simpler version for Swift 5.10 compatibility
            }
            // Removed compatMatchedTransitionSource for Swift 5.10 compatibility
            .compactContentMenuPreview(news: news)
        }
    }
}

extension View {
    func compactContentMenuPreview(news: NewsData) -> some View {
        if #available(iOS 16.0, *) {
            return self.contextMenu {
                if let url = news.url {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        Label("Open URL", systemImage: "arrow.up.right")
                    }
                }
            }
        } else {
            return self
        }
    }
}

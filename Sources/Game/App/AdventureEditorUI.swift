import AppKit
import Foundation
import SwiftUI

struct AdventureEditorRootView: View {
    @ObservedObject var store: AdventureEditorStore

    let palette = AdventureEditorPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                VStack(spacing: 12) {
                    header

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            sourcePanel
                                .frame(width: 220)

                            VStack(spacing: 12) {
                                metadataPanel
                                contentTabBar
                                contentPanel
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sourcePanel
                            metadataPanel
                            contentTabBar
                            contentPanel
                        }
                    }

                    footer
                }
                .padding(18)
            }
        }
    }

}

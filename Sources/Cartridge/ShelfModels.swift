import Foundation

/// The CC-BY models the shelf and its cases were modelled on. Nothing of theirs ships: the bookcase, cases and
/// discs are drawn in code (ShelfArt, CaseNode). The credit stays because the look came from them, and is shown
/// in Settings → Credits and the About panel.
enum ShelfModels {
    struct Credit {
        let title: String
        let author: String
        let license: String
        let url: URL
    }

    static let credits = [
        Credit(title: "PSX Style Wooden Bookshelf (Low Poly)", author: "My Name Is This", license: "CC BY 4.0",
               url: URL(string: "https://sketchfab.com/3d-models/psx-style-wooden-bookshelf-low-poly-bf8be00f3d344ebdafd701fb90d65497")!),
        Credit(title: "Playstation 5 Case with Disc", author: "keltoncrane91", license: "CC BY 4.0",
               url: URL(string: "https://sketchfab.com/3d-models/playstation-5-case-with-disc-1342a3134c3f4ed7aed3a3e230355ee3")!),
    ]
}

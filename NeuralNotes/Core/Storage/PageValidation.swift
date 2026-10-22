import Foundation

public enum PageValidation {
    public static func validate(_ page: PageSnapshot) throws {
        guard (0...1_000_000_000).contains(page.revision), page.width.isFinite, page.height.isFinite,
              (0...20000).contains(page.width), (0...20000).contains(page.height), page.width > 0, page.height > 0,
              page.appearance?.isValid != false, page.tapes?.allSatisfy(\.isValid) != false,
              (page.pdfMarkups ?? []).allSatisfy(\.isValid) else { throw LibraryFailure.corruptDocument }
        if let time = page.lastEditedAt, !time.isFinite || time < 0 { throw LibraryFailure.corruptDocument }
        if let index = page.pdfIndex, index < 0 || index == Int.max { throw LibraryFailure.corruptDocument }
        for text in page.texts {
            guard [text.x, text.y, text.width, text.fontSize].allSatisfy(\.isFinite), text.width > 0, (1...1000).contains(text.fontSize),
                  text.background?.isValid != false, (text.rtf?.count ?? 0) <= 2 * 1024 * 1024,
                  text.rotation?.isFinite != false, text.lensNote?.isValid != false else { throw LibraryFailure.corruptDocument }
        }
        for image in page.images {
            guard [image.x, image.y, image.width, image.height].allSatisfy(\.isFinite), image.width > 0, image.height > 0,
                  image.rotation?.isFinite != false else { throw LibraryFailure.corruptDocument }
            if let crop = image.crop {
                guard [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite), crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
                      crop.x + crop.width <= 1.000001, crop.y + crop.height <= 1.000001 else { throw LibraryFailure.corruptDocument }
            }
        }
        for shape in page.shapes ?? [] {
            guard [shape.x, shape.y, shape.width, shape.height, shape.red, shape.green, shape.blue, shape.lineWidth].allSatisfy(\.isFinite),
                  shape.width > 0, shape.height > 0, (0...1).contains(shape.red), (0...1).contains(shape.green), (0...1).contains(shape.blue),
                  shape.lineWidth > 0, shape.lineWidth <= 200, shape.start?.isValid != false, shape.end?.isValid != false,
                  shape.rotation?.isFinite != false else { throw LibraryFailure.corruptDocument }
        }
        let ids = Set(page.objectIDs)
        guard ids.count == page.objectIDs.count else { throw LibraryFailure.corruptDocument }
        for list in [page.objectOrder, page.lockedObjects, page.aboveInkObjects].compactMap({ $0 }) {
            guard Set(list).count == list.count, Set(list).isSubset(of: ids) else { throw LibraryFailure.corruptDocument }
        }
    }
}

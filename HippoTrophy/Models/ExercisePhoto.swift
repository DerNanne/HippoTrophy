import Foundation
import SwiftData

/// The picture a user gave an exercise of their own, as `PhotoFile`
/// prepared it. A model of its own so that listing exercises does not load
/// their pictures; the bytes lie beside the store once they are big enough.
@Model
final class ExercisePhoto {
    /// New with every picture, so a replaced one is never shown from a cache.
    var id: UUID
    @Attribute(.externalStorage) var data: Data
    var definition: ExerciseDefinition?
    /// Which part a tile shows — see `PhotoFraming`. Added in `SchemaV18`,
    /// centred for every photo before: what a tile showed of it until then.
    var framingX: Double = 0.5
    var framingY: Double = 0.5
    var framingZoom: Double = 1

    init(data: Data, framing: PhotoFraming = .centered) {
        self.id = UUID()
        self.data = data
        self.framing = framing
    }

    var framing: PhotoFraming {
        get { PhotoFraming(x: framingX, y: framingY, zoom: framingZoom) }
        set {
            framingX = newValue.x
            framingY = newValue.y
            framingZoom = newValue.zoom
        }
    }
}

extension ExerciseDefinition {
    /// The photo to show and to back up. A catalog exercise has the catalog's
    /// picture: an own exercise the catalog adopts keeps its photo in the
    /// store, unseen, for the day it is released again.
    var ownPhoto: ExercisePhoto? {
        isCatalog ? nil : photo
    }

    /// Replaces the photo, or only its framing when the picture is the same.
    /// The old one is deleted by hand: the cascade only
    /// fires when the whole exercise goes.
    func setPhoto(_ data: Data?, framing: PhotoFraming = .centered, in context: ModelContext) {
        // The same picture framed anew keeps its photo.
        if let photo, let data, photo.data == data {
            photo.framing = framing
            return
        }
        if let photo {
            self.photo = nil
            context.delete(photo)
        }
        if let data {
            let photo = ExercisePhoto(data: data, framing: framing)
            context.insert(photo)
            self.photo = photo
        }
    }

    /// Takes what an editor holds: a new picture, a new framing, or none.
    func setPhoto(_ draft: PhotoDraft?, in context: ModelContext) {
        setPhoto(draft?.data, framing: draft?.framing ?? .centered, in: context)
    }
}

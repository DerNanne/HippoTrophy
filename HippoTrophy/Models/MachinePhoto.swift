import Foundation
import SwiftData

/// The picture a user gave a machine, as `PhotoFile` prepared it. Like
/// `ExercisePhoto`, a model of its own so that listing machines does not load
/// their pictures. Added in `SchemaV17`.
@Model
final class MachinePhoto {
    /// New with every picture, so a replaced one is never shown from a cache.
    var id: UUID
    @Attribute(.externalStorage) var data: Data
    var machine: Machine?
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

extension Machine {
    /// Replaces the photo, or only its framing when the picture is the same.
    /// The old one is deleted by hand: the cascade only
    /// fires when the whole machine goes.
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
            let photo = MachinePhoto(data: data, framing: framing)
            context.insert(photo)
            self.photo = photo
        }
    }

    /// Takes what an editor holds: a new picture, a new framing, or none.
    func setPhoto(_ draft: PhotoDraft?, in context: ModelContext) {
        setPhoto(draft?.data, framing: draft?.framing ?? .centered, in: context)
    }
}

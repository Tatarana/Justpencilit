import CoreGraphics
import PencilKit

/// Suavização leve dos traços de uma página — reduz a "tremedeira" de cada
/// traço com uma média móvel simples sobre os pontos que já foram
/// desenhados. De propósito, é bem conservador:
///
/// - Não tenta entender letras, palavras, nem onde uma termina e outra
///   começa — só arredonda a geometria de cada traço, individualmente.
/// - Não mexe em espaçamento nem alinhamento sobre uma linha de base.
/// - Mantém as pontas de cada traço fixas, pra não encurtar o traço nem
///   desalinhar onde ele encosta em outro (ex: o cruzamento de um "t").
///
/// Isso é bem mais simples (e mais limitado) do que o Smart Script da
/// Apple — é só um primeiro passo pra avaliar se vale a pena investir
/// mais nisso.
enum HandwritingSmoothing {
    /// Três níveis prontos, do mais discreto ao mais perceptível — cada um
    /// é só um raio de janela diferente pra média móvel. Fácil de ajustar
    /// os números depois, ou de adicionar mais níveis.
    enum Level: Int, CaseIterable, Identifiable {
        case light = 1
        case medium = 3
        case strong = 6

        var id: Int { rawValue }
        var windowRadius: Int { rawValue }

        var label: String {
            switch self {
            case .light: return "Leve"
            case .medium: return "Média"
            case .strong: return "Forte"
            }
        }
    }

    static func smoothed(_ drawing: PKDrawing, level: Level) -> PKDrawing {
        smoothed(drawing, windowRadius: level.windowRadius)
    }

    static func smoothed(_ drawing: PKDrawing, windowRadius: Int) -> PKDrawing {
        let newStrokes = drawing.strokes.map { smoothedStroke($0, windowRadius: windowRadius) }
        return PKDrawing(strokes: newStrokes)
    }

    private static func smoothedStroke(_ stroke: PKStroke, windowRadius: Int) -> PKStroke {
        guard windowRadius > 0 else { return stroke }
        let points = Array(stroke.path)
        guard points.count > windowRadius * 2 + 1 else { return stroke }

        var smoothedPoints: [PKStrokePoint] = []
        smoothedPoints.reserveCapacity(points.count)

        for i in points.indices {
            // Mantém os pontos bem nas pontas do traço fixos.
            if i < windowRadius || i >= points.count - windowRadius {
                smoothedPoints.append(points[i])
                continue
            }
            let window = points[(i - windowRadius)...(i + windowRadius)]
            let count = CGFloat(window.count)
            let avgX = window.reduce(0) { $0 + $1.location.x } / count
            let avgY = window.reduce(0) { $0 + $1.location.y } / count

            let original = points[i]
            let smoothedPoint = PKStrokePoint(
                location: CGPoint(x: avgX, y: avgY),
                timeOffset: original.timeOffset,
                size: original.size,
                opacity: original.opacity,
                force: original.force,
                azimuth: original.azimuth,
                altitude: original.altitude
            )
            smoothedPoints.append(smoothedPoint)
        }

        let newPath = PKStrokePath(controlPoints: smoothedPoints, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: newPath, transform: stroke.transform, mask: stroke.mask)
    }
}

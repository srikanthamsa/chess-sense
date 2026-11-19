import Foundation

/// A built-in template book for lichess's board.
///
/// Lichess draws with Colin M.L. Burnett's set — the same artwork this app ships — on
/// cream and green. Because the art is known, the book can be generated ahead of time
/// instead of asked for: there is no reason a player should calibrate a board the app can
/// already draw. The entries below were produced by calibrating a synthetic lichess board
/// rendered from the bundled pieces, which verified at worst-distance 1.
///
/// TakeTakeTake keeps using a learned book: its pieces are its own artwork, and nothing
/// short of seeing them can describe them.
public enum LichessBook {
    static let squareSize: Double = 150
    static let maxShapeDistance = 14
    /// Generous enough for a last-move tint, tight enough to reject a different piece.
    static let maxColorDistance = 0.16

    static var entries: [TemplateBook.Entry] {
        raw.map { piece, words, bright, ink in
            TemplateBook.Entry(
                piece: piece,
                signature: SquareSignature(words: words, brightFraction: bright,
                                           ink: ink, backgroundLuma: 0.5),
                support: 1
            )
        }
    }

    static let raw: [(Piece, [UInt64], Double, Double)] = [

        (.empty, [0, 0, 0, 0], 0.0, 0.0),
        (.piece(.bishop, .white), [270217901812744192, 1148435428713433056, 1148426632485146608, 140729971902432], 0.45359776252224765, 0.3500355998576006),
        (.piece(.bishop, .white), [270217901812744192, 1148435428713433056, 1148426632485146608, 140729971902432], 0.33664142073648473, 0.34077963688145246),
        (.piece(.king, .white), [108088040349499392, 9222949816873255872, 1150704873059024894, 17523734482936], 0.5721247563352827, 0.45656817372730507),
        (.piece(.knight, .white), [571959282989268992, 4611193420574887928, 9208875655716814846, 140670915346400], 0.6205923836389281, 0.5048059807760769),
        (.piece(.pawn, .white), [270217901787578368, 567462211767763904, 1150687228391852000, 35150548705272], 0.6195187165775401, 0.33285866856532575),
        (.piece(.queen, .white), [17119129666533720064, 4611193396109135283, 2303626377665724412, 35150548967416], 0.2630913687251715, 0.4928800284798861),
        (.piece(.rook, .white), [2303619624903639040, 1148435428713439224, 1150687228527120368, 70352637796344], 0.5049226441631505, 0.4429512281950872),
        (.piece(.bishop, .black), [270217901812744192, 1148435428713433056, 571965880181723120, 140729971902432], 0.03704612365063788, 0.3627625489498042),
        (.piece(.king, .black), [108088040349499392, 9222949816873255872, 2303626377665871870, 17523734482936], 0.12162723121627231, 0.4288002847988608),
        (.piece(.knight, .black), [571959282989268992, 4611193420574887928, 9208875655716814846, 140670915346400], 0.0951319849160096, 0.5192239231043075),
        (.piece(.pawn, .black), [270217901787578368, 567462211767763904, 1150687228391852000, 35150548705272], 0.0, 0.33517265930936274),
        (.piece(.queen, .black), [16830899290382008320, 4611193396109135251, 2303626360485855228, 270251128190935032], 0.1613067027758971, 0.525809896760413),
        (.piece(.rook, .black), [2303624022950150144, 1148435428713439224, 1150687228527120368, 70352637796344], 0.009838810969227549, 0.4251512993948024),
        (.piece(.rook, .black), [2303619624903639040, 1148435428713439224, 1150687228527120368, 70352637796344], 0.12199135980250977, 0.43262726949092206),
    ]
}

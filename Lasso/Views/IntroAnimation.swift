import SwiftUI

/// The Welcome animation: a pile of files bursts into a tumbling ring, a lasso is thrown
/// around it, cinches, and the files are pulled back into one stack before the wordmark appears.
/// Drawn in a 1200 × 700 scene that is scaled to fit.
struct IntroAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 1200, geo.size.height / 700)
            let ox = (geo.size.width - 1200 * s) / 2
            let oy = (geo.size.height - 700 * s) / 2
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { timeline in
                let t = reduceMotion ? 99 : timeline.date.timeIntervalSince(start)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        var c = ctx
                        c.translateBy(x: ox, y: oy)
                        c.scaleBy(x: s, y: s)
                        IntroScene.shared.draw(c, t: t)
                    }
                    wordmark(t: t)
                        .frame(width: 1200 * s)
                        .offset(x: ox, y: oy + 384 * s)
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 6_300_000_000)
            finished = true
        }
        .accessibilityElement()
        .accessibilityLabel("A pile of photo, video, audio and document files bursts into a tumbling ring, a thrown lasso settles around it, and the files are pulled back into one stack before the word Lasso appears.")
    }

    private func wordmark(t: Double) -> some View {
        let appear = IntroScene.gatherEnd + 0.15
        let k1 = IntroScene.outC(IntroScene.clamp((t - appear) / 0.9))
        let k2 = IntroScene.outC(IntroScene.clamp((t - appear - 0.5) / 0.8))
        return VStack(spacing: 4) {
            // En spaces on both sides give Sacramento's curling L room inside the text,
            // so it isn't clipped, while keeping the word centred.
            Text("\u{2002}Lasso\u{2002}")
                .font(.wordmark(106))
                .fixedSize()
                .opacity(k1)
                .scaleEffect(0.96 + 0.04 * k1)
                .offset(y: 14 * (1 - k1))
            Text("Wrangle everything. Find anything.")
                .font(.fraunces(21)).italic()
                .opacity(k2)
                .offset(y: 14 * (1 - k2))
        }
        .foregroundStyle(Theme.denim)
    }
}

struct IntroScene {
    static let shared = IntroScene()

    static let burstAt = 0.4, burstDur = 0.5, orbitDur = 1.3, gatherDur = 1.7
    static let gatherStart = burstAt + burstDur + orbitDur
    static let gatherEnd = gatherStart + gatherDur

    static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
    static func outC(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inOutC(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }

    struct Particle {
        var hx = 0.0, hy = 0.0, hr = 0.0, th = 0.0, rr = 0.0, hgt = 0.0
        var w = 0.0, flip = 0.0, ph = 0.0, yn = 0.0
        var kind = 0
        var color = Color.black
    }
    let particles: [Particle]

    // Rope colours, matched to the logo's browns.
    static let outline = Color(hex: "6B4220")
    static let bodyFront = Color(hex: "D9A563")
    static let bodyBack = Color(hex: "C48D4E")
    static let band = Color(hex: "8A5626")

    init() {
        var seed: UInt32 = 11
        func rnd() -> Double {   // mulberry32, so the pile looks the same every time
            seed = seed &+ 0x6D2B79F5
            var t = (seed ^ (seed >> 15)) &* (1 | seed)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
        let colors = ["1E3A5F", "88074D", "3D6E9E", "5B7A57", "ED643F", "3D6E9E", "88074D"].map { Color(hex: $0) }
        var list: [Particle] = []
        for i in 0..<32 {
            var p = Particle()
            p.hx = (rnd() - 0.5) * 110
            p.hy = (rnd() - 0.5) * 70
            p.hr = (rnd() - 0.5) * 18
            p.th = atan2(p.hy, p.hx == 0 ? 0.001 : p.hx) + (rnd() - 0.5) * 1.6
            p.rr = 0.7 + 0.6 * rnd()
            p.hgt = rnd() - 0.5
            p.w = 90 + 270 * rnd()
            p.flip = 120 + 240 * rnd()
            p.ph = rnd() * Double.pi * 2
            p.yn = (p.hy + 35) / 70
            p.kind = i % 6
            p.color = colors[(i * 3) % colors.count]
            list.append(p)
        }
        particles = list
    }

    // MARK: Drawing

    func draw(_ ctx: GraphicsContext, t: Double) {
        typealias S = IntroScene
        let CX = 600.0, CY = 300.0, R = 288.0, TILT = 0.3, HGT = 100.0
        let om = 40 * Double.pi / 180
        let gAll = S.inOutC(S.clamp((t - S.gatherStart) / S.gatherDur))
        let burstK0 = S.outC(S.clamp((t - S.burstAt) / S.burstDur))

        // Shadow under the ring
        let srx = S.lerp(70, R * 1.1, (1 - gAll) * burstK0), sry = S.lerp(14, R * 0.22, (1 - gAll) * burstK0)
        ctx.fill(Path(ellipseIn: CGRect(x: 600 - srx, y: 352 - sry, width: srx * 2, height: sry * 2)),
                 with: .color(Theme.denim.opacity(0.08)))

        // Rope geometry
        let ropeK = 1 - gAll
        let throwK = S.outC(S.clamp((t - (S.burstAt + 0.2)) / 1.0))
        let lx = S.lerp(1010, CX, throwK), ly = S.lerp(70, CY + 8, throwK)
        let rx = (R * 1.36) * S.lerp(0.2, 1, throwK) * S.lerp(0.1, 1, ropeK)
        let ry = rx * TILT + 24 * ropeK * throwK
        let cinch = S.clamp((t - S.gatherStart) / 0.35)
        let slack = (0.2 * (1 - throwK) + 0.05) * (1 - cinch)
        let vib = t > S.gatherStart ? 0.02 * sin((t - S.gatherStart) * 42) * exp(-(t - S.gatherStart) * 5) : 0
        let spinTilt = 0.22 * (1 - throwK) * sin(t * 5)
        func ptAt(_ th: Double) -> CGPoint {
            let r = 1 + slack * (0.6 * sin(3 * th + t * 6) + 0.4 * sin(5 * th - t * 4.3)) + vib * sin(7 * th)
            let x = cos(th) * rx * r, y = sin(th) * ry * r
            let cs = cos(spinTilt), sn = sin(spinTilt)
            return CGPoint(x: lx + x * cs - y * sn * 0.4, y: ly + x * sn * 0.4 + y * cs)
        }
        let seg = 56
        let backPts = (0...seg).map { ptAt(Double.pi + Double.pi * Double($0) / Double(seg)) }
        let frontPts = (0...seg).map { ptAt(Double.pi * Double($0) / Double(seg)) }
        let honda = ptAt(62 * Double.pi / 180)
        let endX = 1080.0, endY = 572.0
        let tailSlack = (1 - cinch) * (0.35 + 0.65 * (1 - throwK))
        let swing = sin(t * 4.2), swing2 = sin(t * 4.2 + 1.4)
        let c1 = CGPoint(x: S.lerp(honda.x + (endX - honda.x) * 0.33, honda.x + 70, tailSlack),
                         y: S.lerp(honda.y + (endY - honda.y) * 0.33, honda.y + 90 + 70 * swing, tailSlack))
        let c2 = CGPoint(x: S.lerp(honda.x + (endX - honda.x) * 0.66, endX - 170, tailSlack),
                         y: S.lerp(honda.y + (endY - honda.y) * 0.66, endY + 30 + 60 * swing2, tailSlack))
        let tailPts = Self.bezier(honda, c1, c2, CGPoint(x: endX, y: endY), 56)
        func spiral(_ from: Double, _ to: Double) -> [CGPoint] {
            (0...48).map { i in
                let s = from + (to - from) * Double(i) / 48, th = -Double.pi / 2 + s * Double.pi * 2
                return CGPoint(x: endX - 22 * s + 62 * cos(th), y: endY + 24 + 26 * s + 24 * sin(th))
            }
        }
        let tailAll = tailPts + spiral(0, 1).dropFirst()
        let coil = spiral(1, 1.85)
        let thin = S.lerp(1, 0.82, cinch)
        let creep = t * 40 * (1 - cinch)
        let WF = 16 * thin, WB = 13 * thin
        let ropeO = throwK * (t > S.gatherEnd - 0.1 ? 1 - S.clamp((t - (S.gatherEnd - 0.1)) / 0.3) : 1)

        // Back of the loop, behind the files
        if ropeO > 0.001 {
            var c = ctx
            c.opacity = ropeO
            c.drawLayer { l in
                Self.rope(l, backPts, width: WB, body: S.bodyBack, shift: creep)
            }
        }

        // Files, sorted back to front
        struct Tile { var z: Double; var x: Double; var y: Double; var rot: Double; var sx: Double; var sy: Double; var o: Double; var p: Particle }
        var tiles: [Tile] = []
        for q in particles {
            let home = CGPoint(x: CX + q.hx, y: CY + q.hy)
            if t < S.burstAt {
                tiles.append(Tile(z: 0, x: home.x, y: home.y, rot: q.hr, sx: 1, sy: 1, o: 1, p: q))
                continue
            }
            let tb = t - S.burstAt
            let burstK = S.outC(S.clamp(tb / S.burstDur))
            let th = q.th + om * tb
            let bob = sin(tb * 2.7 + q.ph) * 8
            let X = cos(th) * R * q.rr, Z = sin(th) * R * q.rr
            let Y = q.hgt * HGT + bob
            let ringX = CX + X, ringY = CY + Y + Z * TILT
            let depth = 1 + (Z / R) * 0.22
            var x = S.lerp(home.x, ringX, burstK), y = S.lerp(home.y, ringY, burstK)
            var s = S.lerp(1, depth, burstK)
            var rot = q.hr + q.w * 0.75 * tb
            var fx = cos((q.flip * 0.75 * tb) * Double.pi / 180)
            let k = S.inOutC(S.clamp((t - S.gatherStart - 0.3 * (1 - q.yn)) / (S.gatherDur - 0.3)))
            x = S.lerp(x, home.x, k); y = S.lerp(y, home.y, k)
            s = S.lerp(s, 1, k); rot = S.lerp(rot, q.hr, k); fx = S.lerp(fx, 1, k)
            var o = S.lerp(0.55 + 0.45 * ((Z / R) + 1) / 2, 1, max(k, 1 - burstK))
            if t > S.gatherEnd - 0.15 { o *= 1 - S.clamp((t - (S.gatherEnd - 0.15)) / 0.35) }
            if abs(fx) < 0.12 { fx = fx < 0 ? -0.12 : 0.12 }
            tiles.append(Tile(z: S.lerp(Z, 0, k), x: x, y: y, rot: rot, sx: s * fx, sy: s, o: o, p: q))
        }
        for tile in tiles.sorted(by: { $0.z < $1.z }) where tile.o > 0.001 {
            var c = ctx
            c.opacity = tile.o
            c.translateBy(x: tile.x, y: tile.y)
            c.rotate(by: .degrees(tile.rot))
            c.scaleBy(x: tile.sx, y: tile.sy)
            Self.drawFile(c, kind: tile.p.kind, color: tile.p.color)
        }

        // Front of the loop, the tail with its coil, and the knot
        if ropeO > 0.001 {
            var c = ctx
            c.opacity = ropeO
            c.drawLayer { l in
                Self.rope(l, tailAll, width: WF, body: S.bodyFront, shift: creep * 0.5)
                Self.rope(l, coil, width: WF, body: S.bodyFront, shift: 0)
                Self.rope(l, frontPts, width: WF, body: S.bodyFront, shift: creep)
                let a = ptAt(62 * Double.pi / 180 + 0.03), b = ptAt(62 * Double.pi / 180 - 0.03)
                var k = l
                k.translateBy(x: honda.x, y: honda.y)
                k.rotate(by: .radians(atan2(a.y - b.y, a.x - b.x)))
                k.scaleBy(x: thin, y: thin)
                Self.drawKnot(k)
            }
        }

        // Flash and the gathered stack
        let flashK = S.clamp((t - (S.gatherEnd - 0.05)) / 0.6)
        if flashK > 0 && flashK < 1 {
            let r = 60 + 90 * flashK
            ctx.stroke(Path(ellipseIn: CGRect(x: 600 - r, y: 300 - r, width: r * 2, height: r * 2)),
                       with: .color(Theme.gold.opacity(0.6 * (1 - flashK))), lineWidth: 3)
        }
        let settle = S.clamp((t - (S.gatherEnd - 0.1)) / 0.45)
        if settle > 0 {
            let pop = settle < 0.6 ? S.lerp(0.4, 1.08, settle / 0.6) : S.lerp(1.08, 1, (settle - 0.6) / 0.4)
            var c = ctx
            c.opacity = settle
            c.translateBy(x: 600, y: 300)
            c.scaleBy(x: pop, y: pop)
            let card = Path(roundedRect: CGRect(x: -52, y: -36, width: 104, height: 72), cornerRadius: 10)
            for (angle, hex) in [(-9.0, "88074D"), (6.0, "3D6E9E"), (0.0, "1E3A5F")] {
                var r = c
                r.rotate(by: .degrees(angle))
                r.fill(card, with: .color(Color(hex: hex)))
            }
            var play = Path()
            play.move(to: CGPoint(x: -8, y: -14)); play.addLine(to: CGPoint(x: -8, y: 14)); play.addLine(to: CGPoint(x: 14, y: 0)); play.closeSubpath()
            c.fill(play, with: .color(Theme.gold))
        }
    }

    // MARK: Rope

    static func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ n: Int) -> [CGPoint] {
        (0...n).map { i in
            let u = Double(i) / Double(n), v = 1 - u
            return CGPoint(x: v * v * v * p0.x + 3 * v * v * u * p1.x + 3 * v * u * u * p2.x + u * u * u * p3.x,
                           y: v * v * v * p0.y + 3 * v * v * u * p1.y + 3 * v * u * u * p2.y + u * u * u * p3.y)
        }
    }

    /// A smooth curve through the points (Catmull-Rom).
    static func smooth(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            p.addCurve(to: p2,
                       control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                       control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return p
    }

    /// The slanted bands across the rope.
    static func bands(_ pts: [CGPoint], width W: Double, shift: Double) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        var acc: [Double] = [0]
        for i in 1..<pts.count { acc.append(acc[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let L = acc[acc.count - 1], sp = W * 1.3
        guard sp > 0.5 else { return path }
        var j = 1
        var d = sp / 2 + shift.truncatingRemainder(dividingBy: sp)
        while d < L - 2 {
            while j < acc.count - 1 && acc[j] < d { j += 1 }
            let a = pts[j - 1], b = pts[j]
            let segLen = max(acc[j] - acc[j - 1], 0.0001), u = (d - acc[j - 1]) / segLen
            let px = a.x + (b.x - a.x) * u, py = a.y + (b.y - a.y) * u
            let tx = (b.x - a.x) / segLen, ty = (b.y - a.y) / segLen, nx = -ty, ny = tx
            let hw = W * 0.5, k = W * 0.32
            path.move(to: CGPoint(x: px + nx * hw - tx * k, y: py + ny * hw - ty * k))
            path.addQuadCurve(to: CGPoint(x: px - nx * hw + tx * k, y: py - ny * hw + ty * k),
                              control: CGPoint(x: px + tx * k * 0.35, y: py + ty * k * 0.35))
            d += sp
        }
        return path
    }

    static func rope(_ ctx: GraphicsContext, _ pts: [CGPoint], width W: Double, body: Color, shift: Double) {
        let path = smooth(pts)
        let round = { (w: Double) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        ctx.stroke(path, with: .color(outline), style: round(W + 4.5))
        ctx.stroke(path, with: .color(body), style: round(W))
        ctx.stroke(bands(pts, width: W, shift: shift), with: .color(band), style: round(W * 0.15))
    }

    static func drawKnot(_ c: GraphicsContext) {
        var stub = Path()
        stub.move(to: CGPoint(x: 10, y: 2))
        stub.addCurve(to: CGPoint(x: 24, y: 30), control1: CGPoint(x: 18, y: 10), control2: CGPoint(x: 22, y: 18))
        c.stroke(stub, with: .color(outline), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        c.stroke(stub, with: .color(bodyFront), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        var stubBands = Path()
        stubBands.move(to: CGPoint(x: 17, y: 12)); stubBands.addLine(to: CGPoint(x: 23, y: 9))
        stubBands.move(to: CGPoint(x: 21, y: 20)); stubBands.addLine(to: CGPoint(x: 27, y: 18))
        c.stroke(stubBands, with: .color(band), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        var fray = Path()
        fray.move(to: CGPoint(x: 23, y: 33)); fray.addLine(to: CGPoint(x: 21, y: 42))
        fray.move(to: CGPoint(x: 26, y: 33)); fray.addLine(to: CGPoint(x: 31, y: 40))
        fray.move(to: CGPoint(x: 20, y: 32)); fray.addLine(to: CGPoint(x: 14, y: 38))
        c.stroke(fray, with: .color(outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        let knot = Path(roundedRect: CGRect(x: -17, y: -14, width: 34, height: 28), cornerRadius: 12)
        c.fill(knot, with: .color(bodyFront))
        c.stroke(knot, with: .color(outline), lineWidth: 3)
        var wraps = Path()
        for x in [-8.0, 0.0, 8.0] {
            wraps.move(to: CGPoint(x: x, y: -13))
            wraps.addQuadCurve(to: CGPoint(x: x, y: 13), control: CGPoint(x: x + 4, y: 0))
        }
        c.stroke(wraps, with: .color(band), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    // MARK: Files

    static func drawFile(_ c: GraphicsContext, kind: Int, color: Color) {
        let cream = Theme.cream
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double = 0) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        func poly(_ pts: [(Double, Double)]) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
            p.closeSubpath()
            return p
        }
        switch kind {
        case 0: // video
            c.fill(rect(-30, -22, 60, 44, 8), with: .color(color))
            c.fill(Path(ellipseIn: CGRect(x: -11, y: -11, width: 22, height: 22)), with: .color(cream.opacity(0.95)))
            c.fill(poly([(-3.5, -6), (-3.5, 6), (6, 0)]), with: .color(color))
        case 1: // photo print
            c.fill(rect(-25, -29, 50, 58, 3), with: .color(Theme.surface))
            c.stroke(rect(-25, -29, 50, 58, 3), with: .color(Color(hex: "D9CDB3")), lineWidth: 1.5)
            c.fill(rect(-20, -24, 40, 36), with: .color(color))
            c.fill(poly([(-20, 12), (-8, -2), (0, 6), (8, -2), (20, 12)]), with: .color(cream.opacity(0.85)))
            c.fill(Path(ellipseIn: CGRect(x: 5.5, y: -19.5, width: 9, height: 9)), with: .color(Theme.gold))
        case 2: // film strip
            c.fill(rect(-33, -21, 66, 42, 4), with: .color(Theme.denim))
            for x in stride(from: -29.0, through: 21.0, by: 10.0) {
                c.fill(rect(x, -18, 5, 4, 1), with: .color(cream))
                c.fill(rect(x, 14, 5, 4, 1), with: .color(cream))
            }
            c.fill(rect(-26, -11, 24, 22, 2), with: .color(color))
            c.fill(rect(2, -11, 24, 22, 2), with: .color(color.opacity(0.75)))
        case 3: // document
            let page = poly([(-21, -27), (9, -27), (22, -14), (22, 27), (-21, 27)])
            c.fill(page, with: .color(Theme.surface))
            c.stroke(page, with: .color(Color(hex: "CBBFA6")), lineWidth: 1.5)
            var fold = Path()
            fold.move(to: CGPoint(x: 9, y: -27)); fold.addLine(to: CGPoint(x: 9, y: -14)); fold.addLine(to: CGPoint(x: 22, y: -14))
            c.fill(fold, with: .color(Color(hex: "EDE5D3")))
            c.stroke(fold, with: .color(Color(hex: "CBBFA6")), lineWidth: 1.5)
            c.fill(rect(-14, -8, 28, 4, 2), with: .color(color))
            c.fill(rect(-14, 1, 22, 4, 2), with: .color(color.opacity(0.7)))
            c.fill(rect(-14, 10, 28, 4, 2), with: .color(color.opacity(0.7)))
            c.fill(rect(-14, 19, 16, 4, 2), with: .color(color.opacity(0.7)))
        case 4: // audio
            c.fill(rect(-31, -18, 62, 36, 18), with: .color(color))
            for (x, h) in [(-19.0, 6.0), (-12.0, 18.0), (-5.0, 12.0), (2.0, 22.0), (9.0, 10.0), (16.0, 16.0)] {
                c.fill(rect(x, -h / 2, 3.5, h, 1.75), with: .color(cream))
            }
        default: // scenery
            c.fill(rect(-30, -22, 60, 44, 8), with: .color(Theme.powder))
            c.fill(Path(ellipseIn: CGRect(x: 10, y: -15, width: 12, height: 12)), with: .color(Color(hex: "F7EBB0")))
            var hills = Path()
            hills.move(to: CGPoint(x: -30, y: 10))
            hills.addCurve(to: CGPoint(x: 6, y: 6), control1: CGPoint(x: -16, y: -4), control2: CGPoint(x: -4, y: 0))
            hills.addCurve(to: CGPoint(x: 30, y: 2), control1: CGPoint(x: 16, y: 12), control2: CGPoint(x: 24, y: 4))
            hills.addLine(to: CGPoint(x: 30, y: 14))
            hills.addQuadCurve(to: CGPoint(x: 22, y: 22), control: CGPoint(x: 30, y: 22))
            hills.addLine(to: CGPoint(x: -22, y: 22))
            hills.addQuadCurve(to: CGPoint(x: -30, y: 14), control: CGPoint(x: -30, y: 22))
            hills.closeSubpath()
            c.fill(hills, with: .color(color))
        }
    }
}

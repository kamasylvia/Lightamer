import Foundation

func solve(_ A: [[Double]], _ b: [Double]) -> [Double] {
    var m = A; var y = b
    for col in 0..<3 {
        var piv = col
        for r in (col+1)..<3 where abs(m[r][col]) > abs(m[piv][col]) { piv = r }
        m.swapAt(col, piv); y.swapAt(col, piv)
        for r in 0..<3 where r != col {
            let f = m[r][col]/m[col][col]
            for c in 0..<3 { m[r][c] -= f*m[col][c] }
            y[r] -= f*y[col]
        }
    }
    return (0..<3).map { y[$0]/m[$0][$0] }
}

func rgbToXYZ(r: (Double, Double), g: (Double, Double), b: (Double, Double), w: (Double, Double)) -> [[Double]] {
    let Xr = r.0/r.1, Zr = (1-r.0-r.1)/r.1
    let Xg = g.0/g.1, Zg = (1-g.0-g.1)/g.1
    let Xb = b.0/b.1, Zb = (1-b.0-b.1)/b.1
    let A = [[Xr, Xg, Xb],[1.0, 1.0, 1.0],[Zr, Zg, Zb]]
    let W = [w.0/w.1, 1.0, (1-w.0-w.1)/w.1]
    let s = solve(A, W)
    return [[Xr*s[0], Xg*s[1], Xb*s[2]],[s[0], s[1], s[2]],[Zr*s[0], Zg*s[1], Zb*s[2]]]
}

func mul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    var C = [[0.0,0,0],[0,0,0],[0,0,0]]
    for i in 0..<3 { for j in 0..<3 { var s = 0.0; for k in 0..<3 { s += A[i][k]*B[k][j] }; C[i][j] = s } }
    return C
}
func inverse(_ M: [[Double]]) -> [[Double]] {
    let a = M[0][0], b = M[0][1], c = M[0][2]
    let d = M[1][0], e = M[1][1], f = M[1][2]
    let g = M[2][0], h = M[2][1], i = M[2][2]
    let A1 = e*i - f*h
    let B1 = -(d*i - f*g)
    let C1 = d*h - e*g
    let det = a*A1 + b*B1 + c*C1
    return [[A1/det, -(b*i - c*h)/det, (b*f - c*e)/det],
            [B1/det, (a*i - c*g)/det, -(a*f - c*d)/det],
            [C1/det, -(a*h - b*g)/det, (a*e - b*d)/det]]
}

let rec2020 = (r:(0.708, 0.291), g:(0.170, 0.797), b:(0.131, 0.046))
let srgb    = (r:(0.640, 0.330), g:(0.300, 0.600), b:(0.150, 0.060))
let p3      = (r:(0.680, 0.320), g:(0.265, 0.690), b:(0.150, 0.060))
let d65 = (x: 0.3127, y: 0.3290)

let rec2020XYZ = rgbToXYZ(r: rec2020.r, g: rec2020.g, b: rec2020.b, w: d65)
let srgbXYZ = rgbToXYZ(r: srgb.r, g: srgb.g, b: srgb.b, w: d65)
let p3XYZ = rgbToXYZ(r: p3.r, g: p3.g, b: p3.b, w: d65)

let rec2020ToSRGB = mul(inverse(srgbXYZ), rec2020XYZ)
let rec2020ToP3 = mul(inverse(p3XYZ), rec2020XYZ)

func fmt(_ M: [[Double]], _ name: String) {
    print("// \(name) (row-major: out_i = sum_j M[i][j]*in_j)")
    for row in M { print("//   " + row.map { String(format: "% .9f", $0) }.joined(separator: ", ")) }
    for j in 0..<3 {
        let col = (0..<3).map { i in M[i][j] }
        print("//   col\(j) = float3(" + col.map { String(format: "%.9f", $0) }.joined(separator: ", ") + ")")
    }
    func apply(_ v: [Double]) -> [Double] { (0..<3).map { i in M[i][0]*v[0]+M[i][1]*v[1]+M[i][2]*v[2] } }
    for v in [[1.0,0,0],[0,1.0,0],[0,0,1.0],[0.5,0.5,0.5]] {
        print("//   (\(v.map{String(format:"%.2f",$0)}.joined(separator:","))) → " + apply(v).map{String(format:"%.6f",$0)}.joined(separator:", "))
    }
}
fmt(rec2020ToP3, "Rec2020 → Display P3 (linear)")
print()
fmt(rec2020ToSRGB, "Rec2020 → sRGB (linear)")
print()
// sRGB TRC reference points for gamma tests + fixture values
func srgbEncode(_ c: Double) -> Double { c <= 0.04045 ? c/12.92 : 1.055*pow(c, 1/2.4) - 0.055 }
for l in [0.0, 0.04045, 0.5, 0.75, 0.18, 0.09, 1.0] {
    print("// sRGB(\(l)) = \(String(format: "%.6f", srgbEncode(l)))  8bit=\(Int((srgbEncode(l)*255).rounded()))  16bit=\(Int((srgbEncode(l)*65535).rounded()))")
}

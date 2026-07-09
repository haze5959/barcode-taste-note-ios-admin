import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// 바코드 표시 형식
enum BarcodeFormat: String {
    case ean13 = "EAN-13"
    case upcA = "UPC-A"
    case ean8 = "EAN-8"
    case code128 = "CODE128"
}

/// 바코드 인코딩 결과: 모듈(bar) 배열 기반 (EAN 계열) 또는 CoreImage 이미지 (Code128)
enum EncodedBarcode {
    case modules([Bool], format: BarcodeFormat)   // true = 검은 모듈
    case image(CGImage, format: BarcodeFormat)

    var format: BarcodeFormat {
        switch self {
        case .modules(_, let format): return format
        case .image(_, let format): return format
        }
    }
}

/// EAN-13 / UPC-A / EAN-8 인코더 + Code128 폴백 (어드민 웹의 jsbarcode 동작 미러링)
enum BarcodeEncoder {
    // EAN L-코드 (좌측 홀수 패리티). R = L의 보수, G = R의 역순 — 규격상의 관계식으로 유도한다.
    private static let lCodes: [String] = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011",
    ]

    private static func lCode(_ digit: Int) -> [Bool] { lCodes[digit].map { $0 == "1" } }
    private static func rCode(_ digit: Int) -> [Bool] { lCode(digit).map { !$0 } }
    private static func gCode(_ digit: Int) -> [Bool] { rCode(digit).reversed() }

    // EAN-13 첫 자리 숫자에 따른 좌측 6자리 패리티 패턴 (true = G코드 사용)
    private static let parityPatterns: [[Bool]] = [
        [false, false, false, false, false, false], // 0: LLLLLL
        [false, false, true, false, true, true],    // 1: LLGLGG
        [false, false, true, true, false, true],    // 2: LLGGLG
        [false, false, true, true, true, false],    // 3: LLGGGL
        [false, true, false, false, true, true],    // 4: LGLLGG
        [false, true, true, false, false, true],    // 5: LGGLLG
        [false, true, true, true, false, false],    // 6: LGGGLL
        [false, true, false, true, false, true],    // 7: LGLGLG
        [false, true, false, true, true, false],    // 8: LGLGGL
        [false, true, true, false, true, false],    // 9: LGGLGL
    ]

    private static let guardPattern: [Bool] = [true, false, true]           // 101
    private static let centerPattern: [Bool] = [false, true, false, true, false] // 01010

    /// EAN-13 체크섬 검증 (13자리 전체 기준, 마지막 자리가 체크 디지트)
    static func isValidEAN13(_ digits: [Int]) -> Bool {
        guard digits.count == 13 else { return false }
        let sum = digits.prefix(12).enumerated().reduce(0) { acc, pair in
            acc + pair.element * (pair.offset % 2 == 0 ? 1 : 3)
        }
        return (10 - sum % 10) % 10 == digits[12]
    }

    /// EAN-8 체크섬 검증
    static func isValidEAN8(_ digits: [Int]) -> Bool {
        guard digits.count == 8 else { return false }
        let sum = digits.prefix(7).enumerated().reduce(0) { acc, pair in
            acc + pair.element * (pair.offset % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == digits[7]
    }

    /// EAN-13 모듈 인코딩 (95모듈). 입력은 체크섬이 유효한 13자리.
    private static func encodeEAN13(_ digits: [Int]) -> [Bool] {
        var modules: [Bool] = []
        modules += guardPattern
        let parity = parityPatterns[digits[0]]
        for (index, digit) in digits[1...6].enumerated() {
            modules += parity[index] ? gCode(digit) : lCode(digit)
        }
        modules += centerPattern
        for digit in digits[7...12] {
            modules += rCode(digit)
        }
        modules += guardPattern
        return modules
    }

    /// EAN-8 모듈 인코딩 (67모듈)
    private static func encodeEAN8(_ digits: [Int]) -> [Bool] {
        var modules: [Bool] = []
        modules += guardPattern
        for digit in digits[0...3] {
            modules += lCode(digit)
        }
        modules += centerPattern
        for digit in digits[4...7] {
            modules += rCode(digit)
        }
        modules += guardPattern
        return modules
    }

    /// 값을 적절한 형식으로 인코딩.
    /// 자릿수 기반으로 EAN-13/UPC-A/EAN-8을 시도하고, 체크섬 불일치나
    /// 그 외 형식은 임의 문자열을 지원하는 Code128로 폴백한다. (어드민 웹과 동일한 정책)
    static func encode(_ value: String) -> EncodedBarcode? {
        let digits = value.compactMap { $0.wholeNumberValue }
        let isNumeric = digits.count == value.count && !value.isEmpty

        if isNumeric {
            switch digits.count {
            case 13 where isValidEAN13(digits):
                return .modules(encodeEAN13(digits), format: .ean13)
            case 12 where isValidEAN13([0] + digits):
                // UPC-A는 앞에 0을 붙인 EAN-13과 동일한 심볼
                return .modules(encodeEAN13([0] + digits), format: .upcA)
            case 8 where isValidEAN8(digits):
                return .modules(encodeEAN8(digits), format: .ean8)
            default:
                break
            }
        }

        if let image = encodeCode128(value) {
            return .image(image, format: .code128)
        }
        return nil
    }

    /// Code128은 CoreImage 내장 제너레이터 사용
    private static func encodeCode128(_ value: String) -> CGImage? {
        guard let data = value.data(using: .ascii) else { return nil }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = data
        filter.quietSpace = 0
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

// MARK: - 바코드 표시 뷰

/// 바코드 심볼 + 형식 태그 + 숫자 표기를 함께 그리는 뷰
struct BarcodeSymbolView: View {
    let value: String

    private var encoded: EncodedBarcode? { BarcodeEncoder.encode(value) }

    var body: some View {
        VStack(spacing: 16) {
            if let encoded {
                Text(encoded.format.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)

                Group {
                    switch encoded {
                    case .modules(let modules, _):
                        // 배경이 고정 흰색이므로 막대도 고정 검정 (Color.primary는 다크 모드에서 흰색이 되어 안 보임)
                        BarcodeModulesShape(modules: modules)
                            .fill(Color.black)
                            .frame(height: 120)
                    case .image(let cgImage, _):
                        Image(decorative: cgImage, scale: 1)
                            .interpolation(.none)   // 확대 시 바가 뭉개지지 않도록
                            .resizable()
                            .frame(height: 120)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

                Text(value)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
            } else {
                ContentUnavailableView(
                    "바코드를 표시할 수 없습니다",
                    systemImage: "barcode",
                    description: Text("지원하지 않는 문자가 포함되어 있습니다.")
                )
            }
        }
    }
}

/// 모듈(bar) 배열을 실제 막대들로 그리는 Shape
struct BarcodeModulesShape: Shape {
    let modules: [Bool]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !modules.isEmpty else { return path }
        let moduleWidth = rect.width / CGFloat(modules.count)
        for (index, isBar) in modules.enumerated() where isBar {
            path.addRect(CGRect(
                x: rect.minX + CGFloat(index) * moduleWidth,
                y: rect.minY,
                width: moduleWidth,
                height: rect.height
            ))
        }
        return path
    }
}

import XCTest
@testable import ReTyper

/// Verifies KeyLayout against what macOS prints for reference layouts (constitution, principle II).
/// The strings below are verification data taken from macOS and reviewed against research.md R8;
/// they are not a mapping source for the app, which always reads the system layouts.
final class KeyLayoutReferenceTests: XCTestCase {
    /// Rows: ` 1…= / q…\ / a…' / z…/ ; ISO adds the § key (10) in front.
    static let ansiOrder: [UInt16] = [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24,
                                      12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42,
                                      0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39,
                                      6, 7, 8, 9, 11, 45, 46, 43, 47, 44]
    static let isoOrder: [UInt16] = [10] + ansiOrder

    /// Keyboard type 40 is ANSI, 41 is ISO. U+FFFD marks a key without a printable character.
    static let expectations: [(id: String, keyboardType: UInt32, unshifted: String, shifted: String)] = [
        ("com.apple.keylayout.US", 40, unshifted: "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./", shifted: "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"),
        ("com.apple.keylayout.US", 41, unshifted: "§`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./", shifted: "±~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"),
        ("com.apple.keylayout.ABC", 40, unshifted: "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./", shifted: "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"),
        ("com.apple.keylayout.ABC", 41, unshifted: "§`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./", shifted: "±~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"),
        ("com.apple.keylayout.PolishPro", 40, unshifted: "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./", shifted: "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"),
        ("com.apple.keylayout.PolishPro", 41, unshifted: "§`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./", shifted: "£~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"),
        ("com.apple.keylayout.German", 40, unshifted: "<1234567890ß´qwertzuiopü+#asdfghjklöäyxcvbnm,.-", shifted: ">!\"§$%&/()=?`QWERTZUIOPÜ*'ASDFGHJKLÖÄYXCVBNM;:_"),
        ("com.apple.keylayout.German", 41, unshifted: "^<1234567890ß´qwertzuiopü+#asdfghjklöäyxcvbnm,.-", shifted: "°>!\"§$%&/()=?`QWERTZUIOPÜ*'ASDFGHJKLÖÄYXCVBNM;:_"),
        ("com.apple.keylayout.Russian", 40, unshifted: "]1234567890-=йцукенгшщзхъёфывапролджэячсмитьбю/", shifted: "[!\"№%:,.;()_+ЙЦУКЕНГШЩЗХЪЁФЫВАПРОЛДЖЭЯЧСМИТЬБЮ?"),
        ("com.apple.keylayout.Russian", 41, unshifted: ">]1234567890-=йцукенгшщзхъёфывапролджэячсмитьбю/", shifted: "<[!\"№%:,.;()_+ЙЦУКЕНГШЩЗХЪЁФЫВАПРОЛДЖЭЯЧСМИТЬБЮ?"),
        ("com.apple.keylayout.RussianWin", 40, unshifted: "ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.", shifted: "Ë!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"),
        ("com.apple.keylayout.RussianWin", 41, unshifted: "ё]1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.", shifted: "Ё[!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"),
        ("com.apple.keylayout.Ukrainian", 40, unshifted: "'1234567890-=йцукенгшщзхїґфивапролджєячсмітьбю/", shifted: "~!\"№%:,.;()_+ЙЦУКЕНГШЩЗХЇҐФИВАПРОЛДЖЄЯЧСМІТЬБЮ?"),
        ("com.apple.keylayout.Ukrainian", 41, unshifted: ">'1234567890-=йцукенгшщзхїґфивапролджєячсмітьбю/", shifted: "<~!\"№%:,.;()_+ЙЦУКЕНГШЩЗХЇҐФИВАПРОЛДЖЄЯЧСМІТЬБЮ?"),
        ("com.apple.keylayout.Ukrainian-PC", 40, unshifted: "ґ1234567890-=йцукенгшщзхїʼфівапролджєячсмитьбю.", shifted: "Ґ!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЇ₴ФІВАПРОЛДЖЄЯЧСМИТЬБЮ,"),
        ("com.apple.keylayout.Ukrainian-PC", 41, unshifted: "\\ґ1234567890-=йцукенгшщзхїʼфівапролджєячсмитьбю.", shifted: "/Ґ!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЇ₴ФІВАПРОЛДЖЄЯЧСМИТЬБЮ,"),
        ("com.apple.keylayout.Byelorussian", 40, unshifted: "“1234567890-=йцукенгшўзх'ёфывапролджэячсмітьбю/", shifted: "„!\"№%:,.;()_+ЙЦУКЕНГШЎЗХ'ЁФЫВАПРОЛДЖЭЯЧСМІТЬБЮ?"),
        ("com.apple.keylayout.Byelorussian", 41, unshifted: "’“1234567890-=йцукенгшўзх'ёфывапролджэячсмітьбю/", shifted: "+„!\"№%:,.;()_+ЙЦУКЕНГШЎЗХ'ЁФЫВАПРОЛДЖЭЯЧСМІТЬБЮ?"),
    ]

    func testKeyOrderCoversEveryKeyOfTheKeyboard() {
        XCTAssertEqual(Set(Self.ansiOrder), Set(KeyboardKind.ansi.keyCodes))
        XCTAssertEqual(Self.ansiOrder.count, KeyboardKind.ansi.keyCodes.count)
        XCTAssertEqual(Set(Self.isoOrder), Set(KeyboardKind.iso.keyCodes))
    }

    func testReferenceLayoutsMatchMacOS() throws {
        XCTAssertEqual(Set(Self.expectations.map(\.id)).count, 9)
        for expected in Self.expectations {
            let order = expected.keyboardType == 41 ? Self.isoOrder : Self.ansiOrder
            let unshifted = Array(expected.unshifted)
            let shifted = Array(expected.shifted)
            XCTAssertEqual(unshifted.count, order.count, "\(expected.id) \(expected.keyboardType) unshifted length")
            XCTAssertEqual(shifted.count, order.count, "\(expected.id) \(expected.keyboardType) shifted length")
            guard unshifted.count == order.count, shifted.count == order.count else { continue }

            // A missing reference layout fails; it is never skipped.
            let layout = try XCTUnwrap(KeyLayout.system(id: expected.id, keyboardType: expected.keyboardType),
                                       "reference layout missing: \(expected.id)")
            for (index, code) in order.enumerated() {
                for (shift, characters) in [(false, unshifted), (true, shifted)] {
                    let want: Character? = characters[index] == "\u{FFFD}" ? nil : characters[index]
                    XCTAssertEqual(layout.keys[KeyStroke(keyCode: code, shift: shift)], want,
                                   "\(expected.id) type \(expected.keyboardType) key \(code) shift \(shift)")
                }
            }
            let printable = (unshifted + shifted).filter { $0 != "\u{FFFD}" }.count
            XCTAssertEqual(layout.keys.count, printable, "\(expected.id) \(expected.keyboardType) extra keys")
        }
    }
}

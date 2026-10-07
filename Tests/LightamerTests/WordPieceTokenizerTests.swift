import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// WordPieceTokenizerTests (Plan M2-10-02 T2, KD-3) — the BERT WordPiece
// pipeline against the REFERENCE golden fixture (transformers BertTokenizer,
// do_lower_case=True, revision-locked):
//
//   • the 12 fixture sentences (zh / en / mixed / digits / accents /
//     katakana / subword / over-100-char / whitespace) tokenize BYTE-FOR-BYTE
//     (id rows + attention masks, full 52 static shape)
//   • the fixture carries a REDUCED vocab (its own token inventory at their
//     true ids) — the CI face needs no model assets
//   • truncation keeps the head (50 pieces + CLS/SEP), [UNK] faces and the
//     >100-char word rule ride a synthetic vocabulary
//
// ZERO model dependency: the fixture JSON rides the LIB bundle
// (Project.swift resources — E2 registration).
// ─────────────────────────────────────────────────────────────────────────────

final class WordPieceTokenizerTests: XCTestCase {

    struct GoldenCase: Decodable {
        let text: String
        let tokens: [String]
        let ids: [Int64]
        let mask: [Int64]
    }

    struct GoldenFixture: Decodable {
        let revision: String
        let vocabSource: String
        let maxTokens: Int
        let doLowerCase: Bool
        let cases: [GoldenCase]

        enum CodingKeys: String, CodingKey {
            case revision
            case vocabSource = "vocab_source"
            case maxTokens = "max_tokens"
            case doLowerCase = "do_lower_case"
            case cases
        }
    }

    private func loadFixture() throws -> GoldenFixture {
        let url = Bundle(for: Self.self)
            .url(forResource: "tokenizer_golden", withExtension: "json")
        let data = try XCTUnwrap(url.map { try Data(contentsOf: $0) })
        return try JSONDecoder().decode(GoldenFixture.self, from: data)
    }

    /// The reduced vocabulary: every token the 12 cases use, at its TRUE id
    /// (same token → same id across cases is itself asserted). `[PAD]` never
    /// appears in the trimmed token rows — its id is read off the padded
    /// tail (every trailing masked-out position).
    private func reducedVocabulary(
        _ fixture: GoldenFixture
    ) throws -> (vocab: [String: Int], padID: Int64) {
        var vocab: [String: Int] = [:]
        for entry in fixture.cases {
            // `tokens` is the pad-trimmed PREFIX of the 52-length id row.
            XCTAssertLessThanOrEqual(entry.tokens.count, entry.ids.count)
            for (token, id) in zip(entry.tokens, entry.ids) {
                if let known = vocab[String(token)] {
                    XCTAssertEqual(known, Int(id), "stable id: \(token)")
                } else {
                    vocab[String(token)] = Int(id)
                }
            }
        }
        let padID = try XCTUnwrap(fixture.cases.first?.ids.last)
        for entry in fixture.cases {
            XCTAssertEqual(entry.ids.last, padID, "uniform pad id")
            XCTAssertEqual(entry.mask.last, 0, "padded tail is masked out")
        }
        vocab["[PAD]"] = Int(padID)
        return (vocab, padID)
    }

    // MARK: - The golden face (KD-3 anti-hand-copy)

    func testGoldenFixtureTokenizesByteForByte() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.cases.count, 12, "the pinned case inventory")
        XCTAssertEqual(fixture.maxTokens, 52, "the static export shape")
        XCTAssertTrue(fixture.doLowerCase)
        XCTAssertEqual(
            fixture.revision,
            ModelAssetCatalog.chineseClipViTB16Int8.revision,
            "the fixture locks the shipped vocab revision")

        let (vocab, _) = try reducedVocabulary(fixture)
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        for entry in fixture.cases {
            let encoded = tokenizer.encode(entry.text, maxTokens: fixture.maxTokens)
            // The id rows and masks match the reference EXACTLY (all 52).
            XCTAssertEqual(encoded.tokenIDs, entry.ids, "ids: \(entry.text)")
            XCTAssertEqual(
                encoded.attentionMask, entry.mask, "mask: \(entry.text)")
            // The token spelling matches up to the trimmed [PAD] tail.
            XCTAssertEqual(
                Array(encoded.tokens.prefix(entry.tokens.count)), entry.tokens,
                "tokens: \(entry.text)")
            XCTAssertEqual(
                encoded.tokens.count, fixture.maxTokens, "static shape kept")
        }
    }

    func testFixtureVocabularyIsSufficientAlone() throws {
        // The CI face: the reduced vocab + the fixture cases is the WHOLE
        // dependency set — no vocab.txt, no model, no network.
        let fixture = try loadFixture()
        let (vocab, _) = try reducedVocabulary(fixture)
        XCTAssertGreaterThanOrEqual(vocab.count, 4, "specials + case tokens")
        for required in ["[PAD]", "[UNK]", "[CLS]", "[SEP]"] {
            XCTAssertNotNil(vocab[required], "\(required) must resolve")
        }
    }

    // MARK: - Truncation (the 52 static shape)

    func testTruncationKeepsHeadAndStaticShape() throws {
        // A synthetic vocab whose pieces split a 60-character word: 60
        // pieces exceed the 50-piece budget → head-truncated to 50.
        var vocab: [String: Int] = [
            "[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3,
        ]
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for (index, letter) in letters.enumerated() {
            vocab[String(letter)] = 4 + index
            vocab["##\(letter)"] = 4 + letters.count + index
        }
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        let word = String(repeating: "a", count: 60)
        let encoded = tokenizer.encode(word, maxTokens: 52)
        XCTAssertEqual(encoded.tokenIDs.count, 52)
        XCTAssertEqual(encoded.attentionMask.count, 52)
        XCTAssertEqual(encoded.tokenIDs.first, 2, "[CLS] leads")
        XCTAssertEqual(encoded.tokenIDs.last, 3, "[SEP] trails")
        XCTAssertEqual(
            encoded.attentionMask.filter { $0 == 1 }.count, 52,
            "CLS + 50 pieces + SEP — the tail pieces dropped")
        XCTAssertEqual(encoded.tokens[1], "a")
        XCTAssertEqual(encoded.tokens[50], "##a")
    }

    // MARK: - [UNK] faces (synthetic vocabulary)

    func testUnknownWordMapsToUnk() throws {
        let vocab = ["[PAD]": 0, "[UNK]": 100, "[CLS]": 101, "[SEP]": 102,
                     "hello": 5]
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        let encoded = tokenizer.encode("hello zzz", maxTokens: 8)
        XCTAssertEqual(encoded.tokens, ["[CLS]", "hello", "[UNK]", "[SEP]",
                                        "[PAD]", "[PAD]", "[PAD]", "[PAD]"])
        XCTAssertEqual(encoded.tokenIDs, [101, 5, 100, 102, 0, 0, 0, 0])
        XCTAssertEqual(encoded.attentionMask, [1, 1, 1, 1, 0, 0, 0, 0])
    }

    func testOverHundredCharWordBecomesUnkWhole() throws {
        var vocab: [String: Int] = [
            "[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3, "x": 4, "##x": 5,
        ]
        vocab["photo"] = 6
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        // 101 chars → the WHOLE word is [UNK] (the reference rule); the
        // following word still tokenizes normally.
        let long = String(repeating: "x", count: 101)
        let encoded = tokenizer.encode("\(long) photo", maxTokens: 8)
        XCTAssertEqual(
            encoded.tokens, ["[CLS]", "[UNK]", "photo", "[SEP]",
                             "[PAD]", "[PAD]", "[PAD]", "[PAD]"])
        // Exactly 100 chars rides the normal per-character path.
        let exact = String(repeating: "x", count: 100)
        let okEncoded = tokenizer.encode(exact, maxTokens: 8)
        XCTAssertEqual(okEncoded.tokens[1], "x")
        XCTAssertEqual(okEncoded.tokens[2], "##x")
    }

    // MARK: - BasicTokenizer faces

    func testChineseSplitsPerCharacterAndAccentsStrip() throws {
        let vocab: [String: Int] = [
            "[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3,
            "海": 4, "边": 5, "cafe": 6, "naive": 7,
        ]
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        let encoded = tokenizer.encode("海边 café naïve", maxTokens: 12)
        XCTAssertEqual(
            encoded.tokens,
            ["[CLS]", "海", "边", "cafe", "naive", "[SEP]",
             "[PAD]", "[PAD]", "[PAD]", "[PAD]", "[PAD]", "[PAD]"])
    }

    func testPunctuationSplitsAndLowercases() throws {
        let vocab: [String: Int] = [
            "[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3,
            "f2": 4, ".": 5, "8": 6, "35": 7, "##mm": 8,
        ]
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        let encoded = tokenizer.encode("F2.8 35MM", maxTokens: 10)
        XCTAssertEqual(
            encoded.tokens.prefix(7),
            ["[CLS]", "f2", ".", "8", "35", "##mm", "[SEP]"])
    }

    // MARK: - Construction errors

    func testVocabTextInitParsesLineNumbers() throws {
        let text = "[PAD]\n[unused]\n[unused2]\n[UNK]\n[CLS]\n[SEP]\nhello\n"
        let tokenizer = try WordPieceTokenizer(vocabText: text)
        XCTAssertEqual(tokenizer.vocabulary["hello"], 6, "line number = id")
        XCTAssertEqual(tokenizer.vocabulary["[CLS]"], 4)
    }

    func testMissingSpecialTokensIsTyped() {
        XCTAssertThrowsError(try WordPieceTokenizer(vocabulary: [:])) { error in
            XCTAssertEqual(
                error as? WordPieceTokenizer.TokenizerError,
                .vocabularyEmpty)
        }
        XCTAssertThrowsError(
            try WordPieceTokenizer(vocabulary: ["[PAD]": 0, "hello": 1])
        ) { error in
            XCTAssertEqual(
                error as? WordPieceTokenizer.TokenizerError,
                .missingSpecialTokens(["[CLS]", "[SEP]", "[UNK]"]))
        }
    }
}

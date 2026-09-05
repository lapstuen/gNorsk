//
//  ThaiSyllableIPATests.swift
//  gThai
//
//  Unit tests for Thai syllable parsing and IPA generation
//

import XCTest
@testable import gThai

class ThaiSyllableIPATests: XCTestCase {
    
    // MARK: - Test cases for the specific reported issues
    
    func testเสือCorrectSegmentation() {
        // Given: เสือ should be parsed as single syllable
        let word = "เสือ"
        
        // When: Parse the word
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // Then: Should be one syllable "เสือ", not "เสื·อ"
        XCTAssertEqual(syllables.count, 1, "เสือ should be parsed as one syllable")
        XCTAssertEqual(syllables[0].original, "เสือ", "Original should be เสือ")
        XCTAssertEqual(syllables[0].onset, "ส", "Onset should be ส")
        XCTAssertTrue(syllables[0].nucleus.contains("เ"), "Nucleus should contain preposed เ")
        XCTAssertTrue(syllables[0].nucleus.contains("ื"), "Nucleus should contain ื")
        XCTAssertTrue(syllables[0].nucleus.contains("อ"), "Nucleus should contain อ")
    }
    
    func testเสือIPAGeneration() {
        // Given: เสือ with correct segmentation
        let word = "เสือ"
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // When: Generate IPA
        guard let syllable = syllables.first else {
            XCTFail("No syllables found")
            return
        }
        
        let ipa = ThaiIPA.ipaForVowel(nucleus: syllable.nucleus, coda: nil)
        
        // Then: Should generate correct IPA for เอือ (ɯa)
        XCTAssertEqual(ipa, "ɯa", "เสือ should generate IPA: ɯa")
    }
    
    func testภาษาCorrectSegmentation() {
        // Given: ภาษา should be parsed as two syllables
        let word = "ภาษา"
        
        // When: Parse the word
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // Then: Should be two syllables "ภา·ษา", not one "ภาษา"
        XCTAssertEqual(syllables.count, 2, "ภาษา should be parsed as two syllables")
        XCTAssertEqual(syllables[0].original, "ภา", "First syllable should be ภา")
        XCTAssertEqual(syllables[1].original, "ษา", "Second syllable should be ษา")
    }
    
    func testภาษาIPAGeneration() {
        // Given: ภาษา with correct segmentation  
        let word = "ภาษา"
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // When: Generate IPA for both syllables
        guard syllables.count == 2 else {
            XCTFail("Expected 2 syllables, got \(syllables.count)")
            return
        }
        
        let ipa1 = ThaiIPA.ipaSyllable(onset: syllables[0].onset, nucleus: syllables[0].nucleus, coda: nil)
        let ipa2 = ThaiIPA.ipaSyllable(onset: syllables[1].onset, nucleus: syllables[1].nucleus, coda: nil)
        
        // Then: Should generate correct IPA
        XCTAssertEqual(ipa1, "pʰaː", "First syllable ภา should be pʰaː")
        XCTAssertEqual(ipa2, "saː", "Second syllable ษา should be saː")  
    }
    
    // MARK: - Additional test cases for related vowel complexes
    
    func testเกาะCorrectSegmentation() {
        // Given: เกาะ should be one syllable
        let word = "เกาะ"
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // Then: Should be one syllable
        XCTAssertEqual(syllables.count, 1, "เกาะ should be one syllable")
        XCTAssertEqual(syllables[0].original, "เกาะ", "Should be เกาะ")
    }
    
    func testเกิดCorrectSegmentation() {
        // Given: เกิด should be one syllable  
        let word = "เกิด"
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // Then: Should be one syllable
        XCTAssertEqual(syllables.count, 1, "เกิด should be one syllable")
        XCTAssertEqual(syllables[0].original, "เกิด", "Should be เกิด")
        XCTAssertEqual(syllables[0].coda, "ด", "Should have coda ด")
    }
    
    func testเถอะCorrectSegmentation() {
        // Given: เถอะ should be one syllable
        let word = "เถอะ"
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // Then: Should be one syllable  
        XCTAssertEqual(syllables.count, 1, "เถอะ should be one syllable")
        XCTAssertEqual(syllables[0].original, "เถอะ", "Should be เถอะ")
    }
    
    func testเพราะCorrectSegmentation() {
        // Given: เพราะ should be one syllable
        let word = "เพราะ"
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))
        
        // Then: Should be one syllable
        XCTAssertEqual(syllables.count, 1, "เพราะ should be one syllable")
        XCTAssertEqual(syllables[0].original, "เพราะ", "Should be เพราะ")
        XCTAssertEqual(syllables[0].coda, "ะ", "Should have coda ะ")
    }
    
    // MARK: - Test IPA generation for various vowel patterns
    
    func testIパGenerationForCommonVowels() {
        // Test nucleus IPA generation for common vowel patterns
        
        // Long vowels
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "า", coda: nil), "aː", "า should be aː")
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ี", coda: nil), "iː", "ี should be iː")  
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ู", coda: nil), "uː", "ู should be uː")
        
        // Short vowels
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ะ", coda: nil), "a", "ะ should be a")
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ิ", coda: nil), "i", "ิ should be i")
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ุ", coda: nil), "u", "ุ should be u")
        
        // Diphthongs
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ไ", coda: nil), "aj", "ไ should be aj")
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "ใ", coda: nil), "aj", "ใ should be aj")
    }
    
    func testComplexVowelIPAGeneration() {
        // Test the patched เอือ generation
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "เสือ", coda: nil), "ɯa", "เสือ nucleus should generate ɯa")
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "เลือ", coda: nil), "ɯa", "เลือ nucleus should generate ɯa")
        XCTAssertEqual(ThaiIPA.ipaForVowel(nucleus: "เหื่อ", coda: nil), "ɯa", "เหื่อ nucleus should generate ɯa")
    }

    func testคนCorrectSegmentationAndIPA() {
        // Given: คน should be parsed as single syllable with correct IPA
        let word = "คน"

        // When: Parse the word
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))

        // Then: Should be one syllable "คน"
        XCTAssertEqual(syllables.count, 1, "คน should be parsed as one syllable")
        XCTAssertEqual(syllables[0].original, "คน", "Original should be คน")
        XCTAssertEqual(syllables[0].onset, "ค", "Onset should be ค")
        XCTAssertEqual(syllables[0].nucleus, "อ", "Nucleus should be อ")
        XCTAssertEqual(syllables[0].coda, "น", "Coda should be น")

        // Test IPA generation
        let ipa = ipaForSyllable(syllables[0])
        XCTAssertEqual(ipa, "kʰon", "คน should generate IPA: kʰon")
    }
}
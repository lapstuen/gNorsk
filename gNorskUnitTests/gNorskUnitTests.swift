//
//  gNorskUnitTests.swift
//  gNorskUnitTests
//
//  Created by Geir Lapstuen on 9/6/25.
//
import XCTest
import CoreData
@testable import gNorsk

final class BasicTests: XCTestCase {

    func testSimpleSyllable() {
        // 1) Segmenter
        let syls = ThaiSeg.repairPreposedVowelNucleus(
            ThaiSeg.segmentThai("เสือ")
        )
        let got = syls.map { $0.original }
        XCTAssertEqual(got, ["เสือ"])   // forventer 1 stavelse
    }

    func test_coverage_segments() {
        let ord = [
            "เป็น","เด็ก","เก็บ",   // ◌็, coda-k/t/p
            "แม่","แดง","โต","ใบ","ไป", // preposed vowels
            "น้ำ","กำลัง",          // ◌ำ
            "ปาก","ชาติ","กลับ",    // coda k/t/p
            "กราบ","กลัว","ควบ",    // klynger ร/ล/ว
            "หนู","หลวง","หวาน",    // นำห
            "อยาก","เอา","อ่อน",    // อ som bærer
            "ข้าว","เก่า"           // tonemerker
        ]
        for w in ord {
            _ = ThaiSeg.segmentThai(w)  // bare kjør for å treffe grener
        }
    }

  //  func testSimpleIPA() {
  //      // 2) Kall IPA (tilpass til ditt API-navn)
  //      // Eksempel: la ipa = ThaiIPA.toIPA("เสือ")
  //      // XCTAssertEqual(ipa, "sɯ̌ːa")
  //  }

    // MARK: - Group.youtubeVideoID

    func testYoutubeVideoID_watchURL() {
        XCTAssertEqual(Group.youtubeVideoID(from: "https://www.youtube.com/watch?v=abc123XYZ_-"), "abc123XYZ_-")
    }

    func testYoutubeVideoID_watchURL_withExtraParams() {
        XCTAssertEqual(Group.youtubeVideoID(from: "https://www.youtube.com/watch?v=abc123&list=PLxyz&t=42s"), "abc123")
    }

    func testYoutubeVideoID_youtuBe() {
        XCTAssertEqual(Group.youtubeVideoID(from: "https://youtu.be/abc123"), "abc123")
    }

    func testYoutubeVideoID_youtuBe_withShareSuffix() {
        XCTAssertEqual(Group.youtubeVideoID(from: "https://youtu.be/abc123?si=someShareToken"), "abc123")
    }

    func testYoutubeVideoID_embed() {
        XCTAssertEqual(Group.youtubeVideoID(from: "https://www.youtube.com/embed/abc123"), "abc123")
    }

    func testYoutubeVideoID_shorts() {
        XCTAssertEqual(Group.youtubeVideoID(from: "https://www.youtube.com/shorts/abc123"), "abc123")
    }

    func testYoutubeVideoID_garbage() {
        XCTAssertNil(Group.youtubeVideoID(from: "not a url"))
        XCTAssertNil(Group.youtubeVideoID(from: ""))
        XCTAssertNil(Group.youtubeVideoID(from: "https://www.youtube.com/"))
    }

    // MARK: - Group.sortedChronologically

    private func makeInMemoryContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    func testSortedChronologically_ordersByTimestamp() {
        let context = makeInMemoryContext()
        let notesInInsertOrder = ["0:34", "0:04", "0:19", "0:10"]
        for n in notesInInsertOrder {
            let w = ThaiWords(context: context)
            w.id = UUID()
            w.thaiWord = n
            w.notes = n
            w.groupId = 1
        }
        let all = (try? context.fetch(ThaiWords.fetchRequest())) ?? []
        let sorted = Group.sortedChronologically(all)
        XCTAssertEqual(sorted.map { $0.notes }, ["0:04", "0:10", "0:19", "0:34"])
    }

    func testSortedChronologically_fallsBackToStringCompareWhenUnparseable() {
        let context = makeInMemoryContext()
        for n in ["banana", "apple"] {
            let w = ThaiWords(context: context)
            w.id = UUID()
            w.thaiWord = n
            w.notes = n
            w.groupId = 1
        }
        let all = (try? context.fetch(ThaiWords.fetchRequest())) ?? []
        let sorted = Group.sortedChronologically(all)
        XCTAssertEqual(sorted.map { $0.notes }, ["apple", "banana"])
    }
}

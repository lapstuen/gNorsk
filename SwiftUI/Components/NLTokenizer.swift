//
//  NLTokenizer.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/6/25.
//


import NaturalLanguage

let text = "ช่วงนี้ประเทศไทยฝนตกหนักมาก ทั้งในภาคเหนือภาคอีสาน ภาคกลาง แล้วก็ภาคใต้"
let tok = NLTokenizer(unit: .word)
tok.setLanguage(.thai)            // viktig for thai
tok.string = text

tok.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
    let word = String(text[range])
    print(word)
    return true
}

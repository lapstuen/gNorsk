#!/usr/bin/env python3
"""
Thai Syllable and IPA Generator - ONE-TIME USE ONLY
====================================================

Dette scriptet bruker PyThaiNLP til å generere stavelser og IPA for alle Thai ord.
Du kjører det EN GANG, og deretter jobber du kun i Swift.

Installasjon (kjør EN gang):
    pip3 install pythainlp

Bruk:
    python3 generate_thai_data.py

Output:
    thai_syllable_golden_complete.json - Komplett data klar for Swift
"""

import json
import sys
from pathlib import Path

def check_dependencies():
    """Sjekk at PyThaiNLP er installert"""
    try:
        import pythainlp
        print(f"✅ PyThaiNLP versjon {pythainlp.__version__} funnet")
        return True
    except ImportError:
        print("❌ PyThaiNLP ikke installert!")
        print("\nInstaller med:")
        print("    pip3 install pythainlp")
        print("\nEller:")
        print("    python3 -m pip install pythainlp")
        return False

def generate_syllables_and_ipa(text):
    """
    Generer stavelser og IPA for en Thai tekst

    For nå returnerer vi kun stavelser (som fungerer perfekt).
    IPA-generering krever mer setup av PyThaiNLP, så vi bruker
    din eksisterende golden IPA-data.

    Returns:
        dict med 'syllables' og 'ipa'
    """
    from pythainlp.tokenize import syllable_tokenize

    try:
        # Stavelse-segmentering fungerer perfekt!
        syllables = syllable_tokenize(text)

        return {
            'syllables': syllables,
            'ipa': None,  # Bruker golden IPA fra eksisterende data
            'engine_used': 'syllable_tokenize'
        }
    except Exception as e:
        print(f"⚠️  Feil ved prosessering av '{text}': {e}")
        return {
            'syllables': [text],
            'ipa': None,
            'error': str(e)
        }

def process_golden_file(input_path, output_path):
    """
    Les golden file og generer komplett data
    """
    print(f"\n📖 Leser {input_path}...")

    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"✅ Funnet {len(data)} ord å prosessere\n")

    results = []
    errors = []

    for i, item in enumerate(data, 1):
        text = item['text']
        print(f"[{i}/{len(data)}] Prosesserer: {text}")

        # Generer nye data
        generated = generate_syllables_and_ipa(text)

        # Sammenlign med golden data hvis den finnes
        golden_syllables = item.get('syllables', [])
        golden_ipa = item.get('ipa', '')

        match_syllables = (generated['syllables'] == golden_syllables) if golden_syllables else None

        # Bruk golden IPA (din eksisterende data er perfekt!)
        ipa_to_use = golden_ipa if golden_ipa else "⚠️ Mangler IPA"

        # Bygg resultat-objekt
        result = {
            'text': text,

            # PyThaiNLP-generert stavelser + golden IPA
            'syllables': generated['syllables'],
            'ipa': ipa_to_use,
            'engine': generated.get('engine_used'),

            # Sammenligning
            'syllables_match': match_syllables,
        }

        results.append(result)

        # Vis status
        status = []
        if match_syllables == True:
            status.append("✅ Stavelser matcher")
        elif match_syllables == False:
            status.append(f"⚠️  Stavelser forskjellige: {golden_syllables} → {generated['syllables']}")
            errors.append(f"{text}: stavelser {golden_syllables} → {generated['syllables']}")

        status.append(f"✅ IPA: {ipa_to_use}")

        if status:
            print(f"    {' | '.join(status)}")
        print()

    # Lagre resultater
    print(f"\n💾 Lagrer til {output_path}...")
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    # Statistikk
    print("\n" + "="*60)
    print("📊 STATISTIKK")
    print("="*60)
    print(f"Totalt prosessert: {len(results)} ord")

    if errors:
        print(f"\n⚠️  Funnet {len(errors)} forskjeller fra golden data:")
        for error in errors[:10]:  # Vis bare første 10
            print(f"    {error}")
        if len(errors) > 10:
            print(f"    ... og {len(errors) - 10} flere")
    else:
        print("\n✅ Alle data matcher golden dataset!")

    print(f"\n✅ Ferdig! Data lagret i: {output_path}")
    print("\nNå kan du bruke denne filen i Swift-appen din!")

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Thai Syllable and IPA Generator")
    parser.add_argument('--input', help='Input JSON file (default: all_thai_words.json for production, thai_syllable_golden.json for testing)')
    parser.add_argument('--output', help='Output JSON file')
    parser.add_argument('--test', action='store_true', help='Use test mode with golden dataset (99 words)')
    args = parser.parse_args()

    print("="*60)
    print("Thai Syllable and IPA Generator")
    print("Powered by PyThaiNLP")
    print("="*60)

    # Sjekk dependencies
    if not check_dependencies():
        sys.exit(1)

    # Finn filer
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    resources_dir = project_root / "Resources"

    # Velg input/output basert på modus
    if args.test:
        print("\n🧪 TEST MODUS: Bruker golden dataset (99 ord)")
        input_file = resources_dir / "thai_syllable_golden.json"
        output_file = resources_dir / "thai_syllable_golden_complete.json"
    else:
        print("\n🚀 PRODUKSJON MODUS: Prosesserer alle ord")
        input_file = args.input if args.input else resources_dir / "all_thai_words.json"
        output_file = args.output if args.output else resources_dir / "thai_complete.json"
        input_file = Path(input_file)
        output_file = Path(output_file)

    if not input_file.exists():
        print(f"\n❌ Finner ikke input-fil: {input_file}")
        if not args.test:
            print("\n💡 Kjør først eksport i appen:")
            print("   ThaiWordsExporter.exportAllWords(context: viewContext)")
            print("\nEller bruk --test for å teste med golden dataset:")
            print("   python3 generate_thai_data.py --test")
        sys.exit(1)

    # Prosesser
    try:
        process_golden_file(input_file, output_file)
    except Exception as e:
        print(f"\n❌ Feil under prosessering: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()

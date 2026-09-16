#!/usr/bin/env python3
"""Repariert doppelt kodierte Umlaute (Ã¤ Ã¶ Ã¼ ...) in Textdateien.

Hintergrund: Wird eine bereits korrekte UTF-8-Datei ein zweites Mal durch
CP1252 -> UTF-8 geschickt, werden die beiden Bytes eines Umlauts als zwei
einzelne Zeichen gelesen und erneut kodiert. Aus "ü" wird "Ã¼".

Die Umkehrung ist UTF-8 -> CP1252. Ein schlichtes `iconv` bricht dabei aber
ab, sobald irgendwo ein Zeichen steht, das CP1252 nicht kennt — etwa ein
Pfeil oder ein Häkchen. Deshalb hier zeichenweise:

  * Zeichen, die CP1252 kennt  -> zurück zu ihrem ursprünglichen Byte
  * alle anderen               -> behalten ihre UTF-8-Bytes, bleiben also
                                  unverändert

Aufruf:
    python3 fix_mojibake.py datei [datei ...]
    python3 fix_mojibake.py --pruefen datei      (zeigt nur an, ändert nichts)
"""

import sys

VERDAECHTIG = ('Ã¤', 'Ã¶', 'Ã¼', 'Ã„', 'Ã–', 'Ãœ', 'ÃŸ', 'Ã©', 'Ã¨')


def repariere(text: str) -> str:
    teile = []
    for zeichen in text:
        try:
            teile.append(zeichen.encode('cp1252'))
        except UnicodeEncodeError:
            # Nicht in CP1252 darstellbar (Pfeile, Häkchen, Emoji):
            # unverändert durchreichen.
            teile.append(zeichen.encode('utf-8'))
    return b''.join(teile).decode('utf-8')


def main(argv: list[str]) -> int:
    nur_pruefen = '--pruefen' in argv
    dateien = [a for a in argv if not a.startswith('--')]
    if not dateien:
        print(__doc__)
        return 1

    for pfad in dateien:
        original = open(pfad, encoding='utf-8').read()

        if not any(m in original for m in VERDAECHTIG):
            print(f'  übersprungen (sieht sauber aus): {pfad}')
            continue

        try:
            neu = repariere(original)
        except UnicodeDecodeError as fehler:
            # Die Rückwandlung ergibt kein gültiges UTF-8 — dann ist die
            # Datei nicht doppelt kodiert, sondern etwas anderes stimmt
            # nicht. Lieber nichts anfassen.
            print(f'  FEHLER, nichts geändert: {pfad} ({fehler})')
            continue

        treffer = sum(original.count(m) for m in VERDAECHTIG)
        if nur_pruefen:
            print(f'  würde reparieren: {pfad} ({treffer} Stellen)')
            continue

        open(pfad, 'w', encoding='utf-8').write(neu)
        print(f'  repariert: {pfad} ({treffer} Stellen)')

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Stellt das Planungsboard auf die gemeinsame Kalenderwoche um.

`week_board_screen.dart` hatte eine eigene KW-Berechnung, die in Ortszeit
Tage zählte — über die Sommerzeit hinweg eine Woche zu früh. Deshalb zeigte
das Board am 21.09.2026 „KW 38" statt „KW 39".

Das Skript ändert die Datei gezielt an drei Stellen, statt sie komplett zu
ersetzen: Die Datei ist über 3.500 Zeilen lang, und beim Hochladen als .txt
waren Pfeile (→, ←) zu Fragezeichen geworden. Eine vollständige Ersatzdatei
hätte diese Verluste ins Repo getragen.

Aufruf im Projektverzeichnis:
    python3 tools/board_kalenderwoche.py
"""
import pathlib
import re
import sys

PFAD = pathlib.Path('lib/features/board/week_board_screen.dart')
IMPORT = "import '../../core/utils/kalenderwoche.dart';"


def main() -> int:
    if not PFAD.is_file():
        print(f'Nicht gefunden: {PFAD} — bitte im Projektverzeichnis starten.')
        return 1
    roh = PFAD.read_bytes()
    try:
        text = roh.decode('utf-8')
    except UnicodeDecodeError:
        print('Die Datei ist kein UTF-8. Erst `python3 tools/nach_utf8.py '
              '--reparieren` laufen lassen.')
        return 1
    zeilenende = '\r\n' if '\r\n' in text else '\n'
    text = text.replace('\r\n', '\n')

    if '_isoKw' not in text:
        print('Schon umgestellt — nichts zu tun.')
        return 0

    # 1 · Eigene Funktion samt Kommentar entfernen.
    muster = re.compile(
        r'/// ISO-8601-Kalenderwoche\.\nint _isoKw\(DateTime date\) \{\n'
        r'.*?\n\}\n\n',
        re.S,
    )
    text, anzahl = muster.subn('', text, count=1)
    if anzahl != 1:
        print('Die Funktion _isoKw sieht anders aus als erwartet — '
              'bitte die Datei schicken, dann passe ich das an.')
        return 1

    # 2 · Aufrufe umstellen.
    aufrufe = text.count('_isoKw(')
    text = text.replace('_isoKw(', 'isoKalenderwoche(')

    # 3 · Import ergänzen, nach dem letzten core-Import.
    if IMPORT not in text:
        zeilen = text.split('\n')
        letzte = max(i for i, z in enumerate(zeilen)
                     if z.startswith("import '../../core/"))
        zeilen.insert(letzte + 1, IMPORT)
        text = '\n'.join(zeilen)

    PFAD.write_bytes(text.replace('\n', zeilenende).encode('utf-8'))
    print(f'Umgestellt: eigene Funktion entfernt, {aufrufe} Aufruf(e) '
          f'auf isoKalenderwoche, Import ergänzt.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

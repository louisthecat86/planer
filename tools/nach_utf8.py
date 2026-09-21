#!/usr/bin/env python3
"""Bringt Textdateien auf UTF-8 ohne BOM mit LF-Zeilenenden.

Dart verlangt UTF-8. Windows-Editoren speichern aber gern als UTF-16
(mit Nullbytes — Git und gitingest halten die Datei dann für binär) oder
als Windows-1252 (Umlaute werden zu Einzelbytes). Beides sieht im Editor
normal aus und fällt erst beim Kompilieren oder im Diff auf.

Aufruf:
    python3 tools/nach_utf8.py                 # prüft lib/, test/, README.md
    python3 tools/nach_utf8.py --reparieren    # schreibt korrigierte Fassungen
    python3 tools/nach_utf8.py datei1 datei2   # nur diese Dateien
"""
import pathlib
import sys


def erkenne(roh: bytes):
    """Liefert (kodierung, text) oder (None, grund)."""
    if roh.startswith(b'\xef\xbb\xbf'):
        return 'utf-8-bom', roh[3:].decode('utf-8')
    if roh.startswith((b'\xff\xfe', b'\xfe\xff')):
        return 'utf-16', roh.decode('utf-16')
    # UTF-16 ohne BOM: viele Nullbytes an jeder zweiten Stelle
    if roh and roh.count(b'\x00') > len(roh) // 4:
        art = 'utf-16-le' if roh[1:2] == b'\x00' else 'utf-16-be'
        return art, roh.decode(art)
    try:
        return 'utf-8', roh.decode('utf-8')
    except UnicodeDecodeError:
        return 'windows-1252', roh.decode('cp1252')


def main() -> int:
    argumente = [a for a in sys.argv[1:] if not a.startswith('--')]
    reparieren = '--reparieren' in sys.argv
    if argumente:
        dateien = [pathlib.Path(a) for a in argumente]
    else:
        dateien = [*pathlib.Path('lib').rglob('*.dart'),
                   *pathlib.Path('test').rglob('*.dart'),
                   pathlib.Path('README.md')]
    probleme = 0
    for pfad in dateien:
        if not pfad.is_file():
            continue
        roh = pfad.read_bytes()
        kodierung, text = erkenne(roh)
        crlf = b'\r\n' in roh
        if kodierung == 'utf-8' and not crlf:
            continue
        probleme += 1
        was = kodierung + (' + CRLF' if crlf else '')
        if reparieren:
            sauber = text.replace('\r\n', '\n').replace('\r', '\n')
            pfad.write_bytes(sauber.encode('utf-8'))
            print(f'  repariert  {pfad}  ({was} → utf-8)')
        else:
            print(f'  auffällig  {pfad}  ({was})')
    if probleme == 0:
        print('Alle Dateien sind sauberes UTF-8 mit LF.')
    elif not reparieren:
        print(f'\n{probleme} Datei(en). Mit --reparieren korrigieren.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

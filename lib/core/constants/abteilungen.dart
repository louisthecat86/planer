import 'package:flutter/material.dart';

/// Die Abteilungen im Produktionsbetrieb.
///
/// Die Reihenfolge hier entspricht der typischen Produktions-Reihenfolge
/// und bestimmt die Zeilen-Reihenfolge im späteren Whiteboard-Dashboard.
///
/// Die [dbValue]-Strings werden in der lokalen SQLite-Datenbank und im
/// späteren Supabase-Sync gespeichert. **Diese Strings niemals ändern**,
/// ohne eine Datenmigration zu schreiben.
///
/// [kurzcode] und [farbe] dienen der schnellen visuellen Unterscheidung
/// im Whiteboard-Dashboard (Idee aus dem vorherigen Prototyp übernommen).
enum Abteilung {
  zerlegung(
    dbValue: 'zerlegung',
    anzeigeName: 'Zerlegung',
    kurzcode: 'Z',
    farbwert: 0xFFB71C1C,
  ),
  wurstkueche(
    dbValue: 'wurstkueche',
    anzeigeName: 'Wurstküche',
    kurzcode: 'WK',
    farbwert: 0xFF880E4F,
  ),
  kutterabteilung(
    dbValue: 'kutterabteilung',
    anzeigeName: 'Kutterabteilung',
    kurzcode: 'KA',
    farbwert: 0xFFE65100,
  ),
  bratstrasse(
    dbValue: 'bratstrasse',
    anzeigeName: 'Bratstraße',
    kurzcode: 'B',
    farbwert: 0xFF4E342E,
  ),
  schneideabteilung(
    dbValue: 'schneideabteilung',
    anzeigeName: 'Schneideabteilung',
    kurzcode: 'S',
    farbwert: 0xFF311B92,
  ),
  verpackung(
    dbValue: 'verpackung',
    anzeigeName: 'Verpackung',
    kurzcode: 'VP',
    farbwert: 0xFF1B5E20,
  ),
  verpackungTef1(
    dbValue: 'verpackung_tef1',
    anzeigeName: 'Verpackung Tef1',
    kurzcode: 'VT',
    farbwert: 0xFF006064,
  );

  const Abteilung({
    required this.dbValue,
    required this.anzeigeName,
    required this.kurzcode,
    required this.farbwert,
  });

  /// String, unter dem die Abteilung in der Datenbank gespeichert wird.
  final String dbValue;

  /// Voller Anzeigename für die UI.
  final String anzeigeName;

  /// Kurzcode für kompakte UI-Elemente (z.B. CircleAvatar im Whiteboard).
  final String kurzcode;

  /// Farbwert als 0xAARRGGBB. Als Field statt [Color] gespeichert, damit das
  /// Enum const-konstruierbar bleibt.
  final int farbwert;

  /// Liefert die Farbe als [Color]-Objekt für die UI.
  Color get farbe => Color(farbwert);

  /// Parst einen in der Datenbank gespeicherten String zurück zu einem Enum-Wert.
  ///
  /// Wirft einen [ArgumentError], wenn der Wert unbekannt ist — das würde
  /// auf eine inkonsistente Datenbank hindeuten und soll laut auffallen.
  static Abteilung fromDbValue(String value) {
    return Abteilung.values.firstWhere(
      (a) => a.dbValue == value,
      orElse: () => throw ArgumentError(
        'Unbekannte Abteilung in DB: "$value". '
        'Wurde das Enum geändert, ohne eine Migration zu schreiben?',
      ),
    );
  }
}

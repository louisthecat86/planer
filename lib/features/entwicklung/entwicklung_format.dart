import '../../core/utils/format.dart';

// Zahlen der Produktentwicklung: Rezepturmengen brauchen mehr
// Nachkommastellen als die Planung — ein Gewürz wiegt 0,125 kg.

/// Menge in kg mit bis zu drei Nachkommastellen, ohne Nullen am Ende:
/// „12,5", „0,125", „100".
String mengeText(double kg) {
  if (!kg.isFinite) return '—';
  final text = Format.zahl(kg, nachkomma: 3);
  return text.replaceFirst(RegExp(r',?0+$'), '');
}

/// „12,5 %" — mit [nachkomma] Stellen.
String prozentText(double wert, {int nachkomma = 1}) =>
    '${Format.zahl(wert, nachkomma: nachkomma)} %';

/// Liest eine Zahl aus einem Eingabefeld — mit Komma oder Punkt. null bei
/// leerem oder unlesbarem Feld.
double? zahlAus(String text) {
  final t = text.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll(',', '.'));
}

/// Eine Zahl für ein Eingabefeld: mit Komma, ohne Nullen am Ende, leer für
/// null.
String feldText(double? wert) {
  if (wert == null || !wert.isFinite) return '';
  final text = wert.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
  return text.replaceAll('.', ',');
}

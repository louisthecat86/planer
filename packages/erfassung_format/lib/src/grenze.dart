import 'datei.dart';
import 'werte.dart';

/// Was die Prüfung eines Werts ergibt.
enum GrenzStatus {
  /// In Ordnung — oder keine Zahl, dann wird nicht geprüft.
  ok,

  /// Ungewöhnlich — speichern geht trotzdem.
  warnung,

  /// Technisch unmöglich — so wird nichts gespeichert.
  blockiert,
}

/// Das Ergebnis einer Prüfung mit dem Satz dazu.
class GrenzPruefung {
  const GrenzPruefung(this.status, [this.meldung]);

  static const GrenzPruefung inOrdnung = GrenzPruefung(GrenzStatus.ok);

  final GrenzStatus status;
  final String? meldung;
}

/// Die Plausibilitätsgrenzen eines Parameters aus dem Planer: hart
/// (technisch unmöglich) und weich (ungewöhnlich). Jede ist freiwillig.
class Grenze {
  const Grenze({this.hartMin, this.hartMax, this.weichMin, this.weichMax});

  final double? hartMin;
  final double? hartMax;
  final double? weichMin;
  final double? weichMax;

  /// Ob keine Grenze gesetzt ist.
  bool get leer =>
      hartMin == null &&
      hartMax == null &&
      weichMin == null &&
      weichMax == null;

  static String _z(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// Prüft [wert] wie der Planer: harte Grenzen blockieren, weiche
  /// warnen; was keine Zahl ist, bleibt ungeprüft.
  GrenzPruefung pruefe(String? wert) {
    final zahl = zahlAus(wert);
    if (zahl == null) return GrenzPruefung.inOrdnung;
    if (hartMin != null && zahl < hartMin!) {
      return GrenzPruefung(
        GrenzStatus.blockiert,
        'Unter der technischen Untergrenze (${_z(hartMin!)}).',
      );
    }
    if (hartMax != null && zahl > hartMax!) {
      return GrenzPruefung(
        GrenzStatus.blockiert,
        'Über der technischen Obergrenze (${_z(hartMax!)}).',
      );
    }
    if (weichMin != null && zahl < weichMin!) {
      return GrenzPruefung(
        GrenzStatus.warnung,
        'Ungewöhnlich niedrig — üblich ist ab ${_z(weichMin!)}.',
      );
    }
    if (weichMax != null && zahl > weichMax!) {
      return GrenzPruefung(
        GrenzStatus.warnung,
        'Ungewöhnlich hoch — üblich ist bis ${_z(weichMax!)}.',
      );
    }
    return GrenzPruefung.inOrdnung;
  }

  /// „üblich 180–240 · möglich 100–260" — null ohne Grenzen.
  String? get text {
    String? bereich(double? min, double? max) {
      if (min == null && max == null) return null;
      if (min == null) return 'bis ${_z(max!)}';
      if (max == null) return 'ab ${_z(min)}';
      return '${_z(min)}–${_z(max)}';
    }

    final teile = [
      if (bereich(weichMin, weichMax) case final b?) 'üblich $b',
      if (bereich(hartMin, hartMax) case final b?) 'möglich $b',
    ];
    return teile.isEmpty ? null : teile.join(' · ');
  }

  JsonObjekt toJson() => {
        if (hartMin != null) 'hartMin': hartMin,
        if (hartMax != null) 'hartMax': hartMax,
        if (weichMin != null) 'weichMin': weichMin,
        if (weichMax != null) 'weichMax': weichMax,
      };

  /// null, wenn nichts gesetzt ist.
  static Grenze? ausJson(JsonObjekt? j) {
    if (j == null) return null;
    final g = Grenze(
      hartMin: jsonZahlOder(j, 'hartMin'),
      hartMax: jsonZahlOder(j, 'hartMax'),
      weichMin: jsonZahlOder(j, 'weichMin'),
      weichMax: jsonZahlOder(j, 'weichMax'),
    );
    return g.leer ? null : g;
  }
}

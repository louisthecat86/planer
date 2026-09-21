/// Feste Namen aus dem Parametermodell der Artikel.
///
/// Bewusst eine eigene, flutter-freie Datei: Diese Namen werden sowohl in
/// der Oberfläche gebraucht als auch in den Excel-Export-Diensten, und die
/// sollen keine Flutter-Abhängigkeit mitschleppen. Bis dahin lagen sie
/// doppelt vor — einmal in der Artikel-Detailansicht, einmal als Kopie in
/// `excel_export_service_v3.dart` mit dem Kommentar „identisch zur
/// App-Konstante". Zwei Wahrheiten für denselben String sind genau das
/// Muster, das bei den Produktgruppen bereits auseinandergelaufen ist.
///
/// **Diese Strings niemals ändern**, ohne eine Datenmigration zu schreiben:
/// Sie stehen so in der Spalte `parameter_name` beziehungsweise
/// `parameter_gruppe` der Tabelle `product_step_parameters`.
library;

/// Name der Parameterzeile, in der die Maschineneinstellungen als Freitext
/// stehen.
const String kMaschinenNotizParam = 'Maschineneinstellungen';

/// Parametergruppe der Maschinen-Steckbriefwerte.
///
/// Werte in dieser Gruppe stammen aus dem Steckbrief der zugeordneten
/// Anlage und werden im Excel-Export in einem eigenen Block ausgegeben.
const String kMaschinenNotizGruppe = 'MASCHINENEINSTELLUNGEN';

/// Markerparameter am Schritt: welches Plattenraster aktiv ist
/// (`bratstrasse` | `kombiofen` | leer).
const String kPlattenSchemaParam = 'Plattenschema';

/// Parametergruppen, in denen die Plattenwerte liegen.
///
/// Die Plattenleiste sucht ihre Werte über Name **und** Gruppe. Liegt ein
/// `Platte Oben 3` in einer anderen Gruppe, findet sie es nicht — der Wert
/// wäre dann zwar gespeichert, aber unsichtbar.
const String kPlattenGruppeBrat = 'BRATSTRASSE';
const String kPlattenGruppeKombi = 'DAMPFTUNNEL';

/// Namen der Plattenparameter.
///
/// Gültig ist `Platte Oben 1` … `Platte Unten 12`. Zusätzlich erkannt
/// werden die Schreibweisen aus einem früheren Import —
/// `Plattentemperatur Oben 1 (°C)` für die Bratstraße und
/// `Plattentemperatur 1 (°C)` für den Kombiofen —, damit solche Zeilen
/// nicht in der Parameterliste auftauchen, falls die Migration sie
/// irgendwo übersehen hat. Die Plattenleiste verwaltet sie.
final RegExp kPlattenParamMuster = RegExp(
  r'^(Platte|Plattentemperatur)\s+(Oben|Unten)?\s*\d+(\s*\(°C\))?$',
);

/// Hat die Anlage ein festes Plattenraster?
///
/// Bratstraße: 10 Platten oben + 10 unten. Kombiofen: 12 unten.
/// Alle anderen haben kein Raster.
///
/// Die Erkennung läuft über den Namen, damit auch individuell angelegte
/// Anlagen erfasst werden — eine zweite Bratstraße heißt zwangsläufig
/// „Bratstraße …". Der Kombiofen trug früher auch die Namen „Dampftunnel"
/// und „Heißluftofen"; alle drei führen zum 12er-Raster.
///
/// Liegt bewusst hier und nicht in der Oberfläche: Generator, Importer und
/// Artikelansicht müssen dieselbe Regel anwenden. Zwei Fassungen davon
/// wären genau die Doppelung, die bei den Produktgruppen schon einmal
/// auseinandergelaufen ist.
bool istPlattenMaschine(String maschineName) {
  final n = maschineName.toLowerCase();
  return n.contains('bratstra') || istDampftunnelMaschine(maschineName);
}

/// Ist die Anlage der Kombiofen (12er-Raster, nur untere Platten)?
bool istDampftunnelMaschine(String maschineName) {
  final n = maschineName.toLowerCase();
  return n.contains('kombiofen') ||
      n.contains('dampftunnel') ||
      n.contains('heißluft') ||
      n.contains('heissluft');
}

/// Die Plattenzeilen einer Anlage in fester Reihenfolge — leer, wenn sie
/// kein Raster hat.
List<String> plattenZeilenFuer(String maschineName) {
  if (istDampftunnelMaschine(maschineName)) {
    return [for (var i = 1; i <= 12; i++) 'Platte Unten $i'];
  }
  if (istPlattenMaschine(maschineName)) {
    return [
      for (var i = 1; i <= 10; i++) 'Platte Oben $i',
      for (var i = 1; i <= 10; i++) 'Platte Unten $i',
    ];
  }
  return const [];
}

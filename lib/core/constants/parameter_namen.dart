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

/// Namen der Plattenparameter: `Platte Oben 1` … `Platte Unten 12`.
final RegExp kPlattenParamMuster = RegExp(r'^Platte (Oben|Unten) \d+$');

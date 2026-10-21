/// Schlüssel und Namen der Produktentwicklung.
///
/// Ihre Einstellungen liegen in `app_settings` unter einem eigenen Präfix,
/// ihre Tabellen tragen ein eigenes Namenspräfix. So erkennen Backup und
/// „App zurücksetzen" sie und behandeln sie für sich: Im Backup stehen sie
/// verschlüsselt in einem eigenen Teil, und ein Backup ohne diesen Teil
/// lässt sie auf diesem Rechner stehen.
library;

/// Präfix aller Einstellungen der Produktentwicklung.
const String kEntwicklungPraefix = 'entwicklung.';

/// Der Passwort-Datensatz: Salz, Prüfwert und der mit dem Passwort
/// verpackte Datenschlüssel. Wandert im Backup mit.
const String kEntwicklungPasswortSchluessel = '${kEntwicklungPraefix}passwort';

/// Der Datenschlüssel dieses Rechners im Klartext. Damit verschlüsselt das
/// Auto-Backup beim Schließen, ohne nach dem Passwort zu fragen. Verlässt
/// den Rechner nie — im Backup steht er nur verpackt im Passwort-Datensatz.
const String kEntwicklungDatenschluessel = '${kEntwicklungPraefix}schluessel';

/// Der Entwicklungsteil eines eingespielten Backups, der sich mit dem
/// Datenschlüssel dieses Rechners nicht öffnen ließ. Er wird beim nächsten
/// Entsperren mit dem Passwort ausgepackt und eingespielt.
const String kEntwicklungAusstehend = '${kEntwicklungPraefix}ausstehend';

/// Der DeepL-Schlüssel für englische Spezifikationen.
const String kEntwicklungDeeplSchluessel = '${kEntwicklungPraefix}deepl';

/// Das Kürzel dessen, der an diesem Rechner Spezifikationen erstellt.
const String kEntwicklungKuerzel = '${kEntwicklungPraefix}kuerzel';

/// Einstellungen der Produktentwicklung, die nur diesem Rechner gehören:
/// Kein Backup nimmt sie mit, und ein eingespieltes Backup lässt sie
/// stehen. Nur „Zurücksetzen" der Produktentwicklung löscht sie.
const Set<String> kEntwicklungNurLokal = {
  kEntwicklungDeeplSchluessel,
  kEntwicklungKuerzel,
};

/// Ob [schluessel] eine Einstellung der Produktentwicklung ist.
bool istEntwicklungsSchluessel(String schluessel) =>
    schluessel.startsWith(kEntwicklungPraefix);

/// Präfix der Tabellen der Produktentwicklung.
const String kEntwicklungTabellenPraefix = 'entwicklung_';

/// Ob die Tabelle [sqlName] zur Produktentwicklung gehört.
bool istEntwicklungsTabelle(String sqlName) =>
    sqlName.startsWith(kEntwicklungTabellenPraefix);

// ── Zwecke beim Verschlüsseln ─────────────────────────────────────────
//
// Jedes verschlüsselte Paket trägt seinen Zweck mit. Ein Paket des einen
// lässt sich so nicht als eines des anderen unterschieben.

/// Der Datenschlüssel, verpackt mit dem Passwort.
const String kZweckSchluessel = 'produktions-planer/entwicklung/schluessel';

/// Die Tabellen der Produktentwicklung im Backup.
const String kZweckDaten = 'produktions-planer/entwicklung/daten';

/// Der Inhalt einer angehängten Datei.
const String kZweckDatei = 'produktions-planer/entwicklung/datei';

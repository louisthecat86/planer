import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/ablage.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../freigabe/freigabe_ansicht.dart' show oeffneArtikel;
import '../import/suite_import_dialog.dart';
import '../mail/mail.dart';
import '../mail/mail_ablage.dart';
import 'datei_aktionen.dart' show dateienWaehlen, groesseText;
import 'faellig.dart';
import 'gesamtprojekt_modell.dart';
import 'gesamtprojekt_screen.dart' show oeffneGesamtprojekt;
import 'projekt_checkliste.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';

/// Welche Projekte die Liste zeigt.
enum ProjektFilter {
  aktiv('Aktiv'),
  entwicklung('In Entwicklung'),
  validierung('Validierung'),
  produktion('In Produktion'),
  eingestellt('Nicht weiter verfolgt'),
  archiv('Archiv');

  const ProjektFilter(this.label);

  final String label;

  /// „Aktiv" sind alle, die nicht ruhen.
  bool passt(ProjektStatus s) => switch (this) {
        ProjektFilter.aktiv => !s.ruht,
        ProjektFilter.entwicklung => s == ProjektStatus.entwicklung,
        ProjektFilter.validierung => s == ProjektStatus.validierung,
        ProjektFilter.produktion => s == ProjektStatus.produktion,
        ProjektFilter.eingestellt => s == ProjektStatus.eingestellt,
        ProjektFilter.archiv => s == ProjektStatus.archiviert,
      };
}

/// Die Farbe eines Status.
StatusArt projektStatusArt(ProjektStatus s) => switch (s) {
      ProjektStatus.entwicklung => StatusArt.info,
      ProjektStatus.validierung => StatusArt.warnung,
      ProjektStatus.produktion => StatusArt.ok,
      ProjektStatus.eingestellt ||
      ProjektStatus.archiviert =>
        StatusArt.neutral,
    };

/// Öffnet ein Projekt auf seiner eigenen Seite.
Future<void> oeffneProjekt(BuildContext context, String id) =>
    context.pushNamed<void>(
      'entwicklungProjekt',
      pathParameters: {'id': id},
    );

/// Was das Fenster „Neues Projekt" angelegt hat: ein Projekt oder ein
/// Gesamtprojekt — dorthin geht es danach. [hinweis] sagt, was beim
/// Ablegen einer Mail herauskam.
typedef NeuAngelegt = ({String id, bool gesamtprojekt, String? hinweis});

/// Öffnet, was das Fenster „Neues Projekt" angelegt hat.
Future<void> oeffneAngelegt(BuildContext context, NeuAngelegt neu) {
  if (neu.hinweis case final h? when h.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
  }
  return neu.gesamtprojekt
      ? oeffneGesamtprojekt(context, neu.id)
      : oeffneProjekt(context, neu.id);
}

/// Die zugeklappten Gesamtprojekte der Liste — gilt, bis die App schließt.
final zugeklappteGesamtprojekteProvider =
    StateProvider<Set<String>>((ref) => const {});

/// Die Projekte: Liste mit Suche und Filter nach Status. Gesamtprojekte
/// stehen mit ihren Mustern darin — aufgeklappt, zum Zuklappen.
class ProjekteAnsicht extends ConsumerStatefulWidget {
  const ProjekteAnsicht({super.key});

  @override
  ConsumerState<ProjekteAnsicht> createState() => _ProjekteAnsichtState();
}

class _ProjekteAnsichtState extends ConsumerState<ProjekteAnsicht> {
  final _suche = TextEditingController();
  String _text = '';
  ProjektFilter _filter = ProjektFilter.aktiv;

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  List<Gesamtprojekt> get _gesamtprojekte =>
      ref.read(gesamtprojekteProvider).valueOrNull ?? const [];

  Future<void> _neu() async {
    final neu = await showDialog<NeuAngelegt>(
      context: context,
      builder: (_) => NeuesProjektDialog(gesamtprojekte: _gesamtprojekte),
    );
    if (neu == null || !mounted) return;
    await oeffneAngelegt(context, neu);
  }

  /// Ein neues Projekt aus der ersten Mail unter [dateien] — gezogen oder
  /// gewählt.
  Future<void> _ausMail(List<AbgelegteDatei> dateien) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final mails = [
      for (final d in dateien)
        if (alsMail(d.name, d.inhalt) case final m?) (mail: m, datei: d),
    ];
    if (mails.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Hier entsteht aus einer Mail (.msg oder .eml) ein neues '
            'Projekt oder Gesamtprojekt. Andere Dateien ziehst du in ein '
            'Projekt hinein.',
          ),
        ),
      );
      return;
    }
    if (mails.length > 1) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${mails.length} Mails — es geht mit der ersten weiter; die '
            'übrigen ziehst du danach in das Projekt.',
          ),
        ),
      );
    }
    // Das Fenster läuft für sich — das Ablegen ist damit fertig.
    unawaited(_neuAusMail(mails.first));
  }

  Future<void> _neuAusMail(({Mail mail, AbgelegteDatei datei}) aus) async {
    final neu = await showDialog<NeuAngelegt>(
      context: context,
      builder: (_) => NeuesProjektDialog(
        ausMail: aus,
        gesamtprojekte: _gesamtprojekte,
      ),
    );
    if (neu == null || !mounted) return;
    await oeffneAngelegt(context, neu);
  }

  Future<void> _mailWaehlen() async {
    final gewaehlt = await dateienWaehlen(
      context,
      titel: 'Mail wählen',
      endungen: const ['msg', 'eml'],
      mehrere: false,
    );
    if (gewaehlt.isEmpty || !mounted) return;
    await _ausMail(gewaehlt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projekte = ref.watch(projekteProvider);
    final gesamtprojekte = ref.watch(gesamtprojekteProvider).valueOrNull ??
        const <Gesamtprojekt>[];
    final zu = ref.watch(zugeklappteGesamtprojekteProvider);
    final checklisten = ref.watch(projektChecklistenProvider);
    final eintraege = ref.watch(alleEintraegeProvider).valueOrNull;
    final offen = eintraege == null
        ? const <String, OffeneEintraege>{}
        : offeneJeProjekt(eintraege, heute: DateTime.now());
    return projekte.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Die Projekte ließen sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (alle) {
        final punkte = projektListe(
          projekte: alle,
          gesamtprojekte: gesamtprojekte,
          passt: _filter.passt,
          leerPasst: _filter == ProjektFilter.aktiv,
          suche: _text,
        );
        final gezeigt = punkte.fold<int>(
          0,
          (n, p) => n + (p is GesamtGruppe ? p.sichtbar.length : 1),
        );
        // Die Zeilen: je Gesamtprojekt seine Zeile und — aufgeklappt —
        // die Muster darunter.
        void klappen(String id) =>
            ref.read(zugeklappteGesamtprojekteProvider.notifier).state =
                zu.contains(id) ? ({...zu}..remove(id)) : {...zu, id};
        final reihe = <Widget Function(bool breit)>[];
        for (final p in punkte) {
          switch (p) {
            case EinzelProjekt(:final projekt):
              reihe.add(
                (breit) => _Zeile(
                  projekt: projekt,
                  checkliste: checklisten?[projekt.id],
                  offen: offen[projekt.id],
                  breit: breit,
                ),
              );
            case GesamtGruppe(:final gesamtprojekt, :final sichtbar):
              final id = gesamtprojekt.id;
              reihe.add(
                (breit) => _GesamtZeile(
                  gruppe: p,
                  zugeklappt: zu.contains(id),
                  breit: breit,
                  onKlappen: () => klappen(id),
                ),
              );
              if (!zu.contains(id)) {
                for (final m in sichtbar) {
                  reihe.add(
                    (breit) => _Zeile(
                      projekt: m,
                      checkliste: checklisten?[m.id],
                      offen: offen[m.id],
                      breit: breit,
                      muster: true,
                    ),
                  );
                }
              }
          }
        }
        return AblageZone(
          hinweis: 'Mail loslassen — daraus wird ein neues Projekt oder '
              'Gesamtprojekt',
          onAbgelegt: _ausMail,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: TextField(
                          controller: _suche,
                          decoration: InputDecoration(
                            hintText: 'Suche nach Projekt, Kunde oder '
                                'Artikelnummer …',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    tooltip: 'Suche leeren',
                                    onPressed: () {
                                      _suche.clear();
                                      setState(() => _text = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _text = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$gezeigt von ${alle.length} Projekten',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Schmal nur das Symbol.
                    if (MediaQuery.sizeOf(context).width < 760)
                      IconButton.outlined(
                        tooltip: 'Neues Projekt aus Mail',
                        onPressed: _mailWaehlen,
                        icon: const Icon(Icons.mail_outline, size: 18),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _mailWaehlen,
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: const Text('Aus Mail…'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _neu,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Neues Projekt'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in ProjektFilter.values)
                      ChoiceChip(
                        label: Text(
                          '${f.label} '
                          '(${alle.where((p) => f.passt(ProjektStatus.aus(p.status))).length})',
                        ),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Material(
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppMasse.ecken,
                      side: BorderSide(color: theme.colorScheme.outline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final breit = c.maxWidth >= 860;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Kopf(breit: breit),
                            Expanded(
                              child: reihe.isEmpty
                                  ? Center(
                                      child: LeerHinweis(
                                        alle.isEmpty
                                            ? 'Noch keine Projekte. Lege das '
                                                'erste an — oder übernimm die '
                                                'Projekte der alten Suite.'
                                            : 'Keine Treffer.',
                                        icon: alle.isEmpty
                                            ? Icons.folder_open_outlined
                                            : Icons.search_off,
                                        aktion: alle.isEmpty
                                            ? TextButton.icon(
                                                onPressed: () =>
                                                    suiteImportStarten(context),
                                                icon: const Icon(
                                                  Icons.move_to_inbox_outlined,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Aus der Suite übernehmen',
                                                ),
                                              )
                                            : null,
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: reihe.length,
                                      itemBuilder: (_, i) => reihe[i](breit),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

abstract final class _Spalten {
  static const double kunde = 170;

  /// Die Artikelnummer steht vorn — schmal etwas enger.
  static const double nummer = 104;
  static const double nummerSchmal = 88;
  static const double status = 130;
  static const double checkliste = 80;
  static const double datum = 90;
  static const double luecke = 12;
}

class _Kopf extends StatelessWidget {
  const _Kopf({required this.breit});

  final bool breit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget spalte(String text, double breite, {bool rechts = false}) =>
        SizedBox(
          width: breite,
          child: Text(
            text,
            maxLines: 1,
            textAlign: rechts ? TextAlign.right : TextAlign.left,
            style: stil,
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          spalte(
            'Art.-Nr.',
            breit ? _Spalten.nummer : _Spalten.nummerSchmal,
          ),
          const SizedBox(width: _Spalten.luecke),
          Expanded(child: Text('Projekt', style: stil)),
          const SizedBox(width: _Spalten.luecke),
          if (breit) ...[
            spalte('Kunde', _Spalten.kunde),
            const SizedBox(width: _Spalten.luecke),
          ],
          spalte('Status', _Spalten.status),
          if (breit) ...[
            spalte('Checkliste', _Spalten.checkliste, rechts: true),
            spalte('Geändert', _Spalten.datum, rechts: true),
          ],
        ],
      ),
    );
  }
}

/// Die Zeile eines Gesamtprojekts: Name, wie seine Muster stehen, der
/// Kunde und wann sich zuletzt etwas getan hat. Vorn zum Auf- und
/// Zuklappen der Muster; antippen öffnet das Gesamtprojekt.
class _GesamtZeile extends StatelessWidget {
  const _GesamtZeile({
    required this.gruppe,
    required this.zugeklappt,
    required this.breit,
    required this.onKlappen,
  });

  final GesamtGruppe gruppe;
  final bool zugeklappt;
  final bool breit;
  final VoidCallback onKlappen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stil = theme.textTheme.bodyMedium;
    final g = gruppe.gesamtprojekt;
    final kunde = g.kunde?.trim() ?? '';
    final zusammen = musterZusammenfassung([
      for (final m in gruppe.muster) ProjektStatus.aus(m.status),
    ]);
    final verborgen = gruppe.muster.length - gruppe.sichtbar.length;
    final unter = [
      if (!breit && kunde.isNotEmpty) kunde,
      zusammen,
      if (verborgen > 0 && gruppe.sichtbar.isNotEmpty)
        '$verborgen hier nicht gezeigt',
    ].join(' · ');
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        key: ValueKey('gesamtprojekt-${g.id}'),
        onTap: () => oeffneGesamtprojekt(context, g.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: (breit ? _Spalten.nummer : _Spalten.nummerSchmal) + 8,
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('klappen-${g.id}'),
                      visualDensity: VisualDensity.compact,
                      tooltip:
                          zugeklappt ? 'Muster zeigen' : 'Muster verbergen',
                      icon: Icon(
                        zugeklappt ? Icons.chevron_right : Icons.expand_more,
                        size: 20,
                      ),
                      onPressed: onKlappen,
                    ),
                    Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _Spalten.luecke),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      unter,
                      key: ValueKey('gesamtprojekt-unterzeile-${g.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _Spalten.luecke),
              if (breit) ...[
                SizedBox(
                  width: _Spalten.kunde,
                  child: Text(
                    kunde.isEmpty ? '—' : kunde,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(color: kunde.isEmpty ? grau : null),
                  ),
                ),
                const SizedBox(width: _Spalten.luecke),
              ],
              const SizedBox(
                width: _Spalten.status,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: StatusMarke(
                    'Gesamtprojekt',
                    icon: Icons.folder_outlined,
                  ),
                ),
              ),
              if (breit) ...[
                const SizedBox(width: _Spalten.checkliste),
                SizedBox(
                  width: _Spalten.datum,
                  child: Text(
                    Format.datum(gruppe.zuletzt),
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine Zeile der Projektliste. Unter dem Namen steht, was als Nächstes
/// zu tun ist und was im Verlauf offen ist — ruht das Projekt oder ist
/// nichts mehr zu tun, die Produktidee. Ein Muster steht eingerückt unter
/// seinem Gesamtprojekt, ohne Kunden — der steht dort.
class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.projekt,
    required this.checkliste,
    required this.breit,
    this.offen,
    this.muster = false,
  });

  final EntwicklungsProjekt projekt;

  /// Wie die Checkliste steht — null, solange sie noch rechnet.
  final ProjektCheckStand? checkliste;

  /// Die offenen Einträge im Verlauf — null: keine.
  final OffeneEintraege? offen;
  final bool breit;

  /// Ein Muster unter seinem Gesamtprojekt.
  final bool muster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farben = AppFarben.von(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final stil = theme.textTheme.bodyMedium;
    final p = projekt;
    final status = ProjektStatus.aus(p.status);
    final ruht = status.ruht;
    final naechster = ruht ? null : checkliste?.naechster;
    final o = ruht ? null : offen;
    final kunde = p.kunde?.trim() ?? '';
    final idee = p.produktidee?.trim() ?? '';
    // Die Teile der zweiten Zeile — mit Farbe, wo etwas offen ist.
    final teile = <(String, TextStyle?)>[
      if (!breit && !muster && kunde.isNotEmpty) (kunde, null),
      if (naechster != null) ('Als Nächstes: ${checkAufgabe(naechster)}', null),
      if (o != null && o.offen > 0)
        (
          offeneEintraegeText(o),
          TextStyle(
            color: o.ueberfaellig > 0 ? farben.fehler : farben.warnung,
            fontWeight: o.ueberfaellig > 0 ? FontWeight.w600 : null,
          ),
        ),
      if (naechster == null && (o == null || o.offen == 0) && idee.isNotEmpty)
        (idee, null),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => oeffneProjekt(context, p.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: breit ? _Spalten.nummer : _Spalten.nummerSchmal,
                child: _Nummer(projekt: p),
              ),
              const SizedBox(width: _Spalten.luecke),
              // Ein Muster: eingerückt, mit einer Linie zum Gesamtprojekt.
              if (muster) ...[
                Container(
                  width: 2,
                  height: 30,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stil?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (teile.isNotEmpty)
                      Text.rich(
                        TextSpan(
                          children: [
                            for (final (i, (text, farbe)) in teile.indexed) ...[
                              if (i > 0) const TextSpan(text: ' · '),
                              TextSpan(text: text, style: farbe),
                            ],
                          ],
                        ),
                        key: ValueKey('projekt-unterzeile-${p.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: _Spalten.luecke),
              if (breit) ...[
                SizedBox(
                  width: _Spalten.kunde,
                  child: muster
                      ? null
                      : Text(
                          p.kunde ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: stil?.copyWith(
                            color: p.kunde == null ? grau : null,
                          ),
                        ),
                ),
                const SizedBox(width: _Spalten.luecke),
              ],
              SizedBox(
                width: _Spalten.status,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: StatusMarke(
                    status.label,
                    art: projektStatusArt(status),
                  ),
                ),
              ),
              if (breit) ...[
                SizedBox(
                  width: _Spalten.checkliste,
                  child: Text(
                    checkliste?.text ?? '…',
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
                SizedBox(
                  width: _Spalten.datum,
                  child: Text(
                    Format.datum(p.updatedAt),
                    textAlign: TextAlign.right,
                    style: stil?.copyWith(color: grau),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Artikelnummer eines Projekts — ist es als Artikel freigegeben, ein
/// Verweis auf ihn in der Planung.
class _Nummer extends StatelessWidget {
  const _Nummer({required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stil = theme.textTheme.bodyMedium;
    final nummer = projekt.artikelnummer?.trim() ?? '';
    final artikelId = projekt.artikelId;
    if (artikelId == null) {
      return Text(
        nummer.isEmpty ? '—' : nummer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: stil?.copyWith(
          color: nummer.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
        ),
      );
    }
    final farbe = theme.colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      child: Tooltip(
        message: 'Artikel in der Planung öffnen',
        child: InkWell(
          key: ValueKey('projekt-artikel-${projekt.id}'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => oeffneArtikel(context, artikelId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    nummer.isEmpty ? 'Artikel' : nummer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stil?.copyWith(
                      color: farbe,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 14, color: farbe),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Was das Fenster „Neues Projekt" anlegt.
enum NeuArt {
  /// Ein Projekt für ein Produkt.
  produkt,

  /// Ein Gesamtprojekt mit mehreren Mustern.
  gesamtprojekt,

  /// Nichts Neues — die Mail kommt in ein bestehendes Gesamtprojekt.
  ablegen,
}

/// Ein neues Projekt — für ein Produkt (Name, Kunde, Artikelnummer, Idee)
/// oder als Gesamtprojekt mit mehreren Mustern (Name, Kunde, Anfrage, die
/// Namen der Muster). Aus einer Mail lässt sie sich auch in ein
/// bestehendes Gesamtprojekt legen. Gibt zurück, was angelegt ist.
class NeuesProjektDialog extends ConsumerStatefulWidget {
  const NeuesProjektDialog({
    super.key,
    this.ausMail,
    this.gesamtprojekte = const [],
  });

  /// Die Mail, aus der das Projekt entsteht — sie füllt Name, Kunde und
  /// Idee vor und steht danach mit ihren Anhängen im Verlauf.
  final ({Mail mail, AbgelegteDatei datei})? ausMail;

  /// Die Gesamtprojekte, in die sich eine Mail legen lässt.
  final List<Gesamtprojekt> gesamtprojekte;

  @override
  ConsumerState<NeuesProjektDialog> createState() =>
      _NeuesProjektDialogState();
}

class _NeuesProjektDialogState extends ConsumerState<NeuesProjektDialog> {
  final _name = TextEditingController();
  final _kunde = TextEditingController();
  final _nummer = TextEditingController();
  final _idee = TextEditingController();
  final List<TextEditingController> _muster = [
    TextEditingController(),
    TextEditingController(),
  ];
  NeuArt _art = NeuArt.produkt;
  String? _ziel;
  bool _speichert = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    final m = widget.ausMail?.mail;
    if (m != null) {
      final v = projektVorschlag(m);
      _name.text = v.name;
      _kunde.text = v.kunde;
      _idee.text = v.idee;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _kunde.dispose();
    _nummer.dispose();
    _idee.dispose();
    for (final c in _muster) {
      c.dispose();
    }
    super.dispose();
  }

  String? _oderNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Das Gesamtprojekt, in das die Mail kommt — vorgeschlagen eines
  /// desselben Kunden, sonst das zuletzt bewegte.
  String? get _zielId {
    final alle = widget.gesamtprojekte;
    if (alle.isEmpty) return null;
    if (_ziel case final z? when alle.any((g) => g.id == z)) return z;
    final kunde = _kunde.text.trim().toLowerCase();
    return (kunde.isEmpty
                ? null
                : alle
                    .where((g) => (g.kunde ?? '').trim().toLowerCase() == kunde)
                    .firstOrNull)
            ?.id ??
        alle.first.id;
  }

  Future<void> _anlegen() async {
    final name = _name.text.trim();
    if (_art != NeuArt.ablegen && name.isEmpty) {
      setState(() => _fehler = 'Bitte einen Namen eingeben.');
      return;
    }
    final aus = widget.ausMail;
    final ziel = _zielId;
    if (_art == NeuArt.ablegen && (aus == null || ziel == null)) {
      setState(() => _fehler = 'Bitte ein Gesamtprojekt wählen.');
      return;
    }
    setState(() {
      _speichert = true;
      _fehler = null;
    });
    try {
      final ablage = ref.read(mailAblageProvider);
      final repo = ref.read(projektRepositoryProvider);
      final NeuAngelegt neu;
      switch (_art) {
        case NeuArt.produkt:
          final id = aus == null
              ? await repo.projektAnlegen(
                  name: name,
                  kunde: _oderNull(_kunde),
                  artikelnummer: _oderNull(_nummer),
                  produktidee: _oderNull(_idee),
                )
              : await ablage.projektAusMail(
                  mail: aus.mail,
                  datei: aus.datei,
                  name: name,
                  kunde: _oderNull(_kunde),
                  artikelnummer: _oderNull(_nummer),
                  produktidee: _oderNull(_idee),
                );
          neu = (id: id, gesamtprojekt: false, hinweis: null);
        case NeuArt.gesamtprojekt:
          final muster = [for (final c in _muster) c.text];
          final id = aus == null
              ? await repo.gesamtprojektAnlegen(
                  name: name,
                  kunde: _oderNull(_kunde),
                  anfrage: _oderNull(_idee),
                  muster: muster,
                )
              : await ablage.gesamtprojektAusMail(
                  mail: aus.mail,
                  datei: aus.datei,
                  name: name,
                  kunde: _oderNull(_kunde),
                  anfrage: _oderNull(_idee),
                  muster: muster,
                );
          neu = (id: id, gesamtprojekt: true, hinweis: null);
        case NeuArt.ablegen:
          final bericht = await ablage.ablegen(ziel!, [aus!.datei]);
          neu = (id: ziel, gesamtprojekt: true, hinweis: bericht.text);
      }
      ref
          .read(autoBackupTriggerProvider)
          .fireDebounced(reason: 'Projekt angelegt');
      if (mounted) Navigator.of(context).pop(neu);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speichert = false;
        _fehler = 'Anlegen fehlgeschlagen: ${fehlerText(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final fehler = _fehler;
    // Kunden aus anderen Projekten zum Antippen — passend zur Eingabe.
    final eingabe = _kunde.text.trim().toLowerCase();
    final vorschlaege = ({
      for (final p in ref.watch(projekteProvider).valueOrNull ??
          const <EntwicklungsProjekt>[])
        if ((p.kunde ?? '').trim().isNotEmpty) p.kunde!.trim(),
      for (final g in widget.gesamtprojekte)
        if ((g.kunde ?? '').trim().isNotEmpty) g.kunde!.trim(),
    }.where(
      (k) => k.toLowerCase().contains(eingabe) && k.toLowerCase() != eingabe,
    ).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        .take(6)
        .toList();
    final aus = widget.ausMail;
    final ablegbar = aus != null && widget.gesamtprojekte.isNotEmpty;
    final gesamt = _art == NeuArt.gesamtprojekt;
    final ablegen = _art == NeuArt.ablegen;
    final titel = switch (_art) {
      NeuArt.produkt =>
        aus == null ? 'Neues Projekt' : 'Neues Projekt aus Mail',
      NeuArt.gesamtprojekt =>
        aus == null ? 'Neues Gesamtprojekt' : 'Neues Gesamtprojekt aus Mail',
      NeuArt.ablegen => 'Mail in ein Gesamtprojekt legen',
    };
    return AlertDialog(
      title: Text(titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<NeuArt>(
                key: const ValueKey('neu-art'),
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                    value: NeuArt.produkt,
                    icon: Icon(Icons.inventory_2_outlined),
                    label: Text('Ein Produkt'),
                    tooltip: 'Ein Projekt für ein Produkt',
                  ),
                  const ButtonSegment(
                    value: NeuArt.gesamtprojekt,
                    icon: Icon(Icons.folder_outlined),
                    label: Text('Mehrere Muster'),
                    tooltip: 'Ein Gesamtprojekt: eine Anfrage, aus der '
                        'mehrere Muster entstehen',
                  ),
                  if (ablegbar)
                    const ButtonSegment(
                      value: NeuArt.ablegen,
                      icon: Icon(Icons.drive_file_move_outline),
                      label: Text('Ablegen'),
                      tooltip: 'In ein bestehendes Gesamtprojekt',
                    ),
                ],
                selected: {_art},
                onSelectionChanged: (w) => setState(() {
                  _art = w.first;
                  _fehler = null;
                }),
              ),
              const SizedBox(height: 12),
              if (aus != null) ...[
                _MailZeile(mail: aus.mail, art: _art),
                const SizedBox(height: 12),
              ],
              if (ablegen)
                DropdownButtonFormField<String>(
                  key: const ValueKey('neu-ablegen-ziel'),
                  initialValue: _zielId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Gesamtprojekt',
                  ),
                  items: [
                    for (final g in widget.gesamtprojekte)
                      DropdownMenuItem(
                        value: g.id,
                        child: Text(
                          (g.kunde ?? '').trim().isEmpty
                              ? g.name
                              : '${g.name} · ${g.kunde!.trim()}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (z) => setState(() => _ziel = z),
                )
              else ...[
                TextField(
                  key: const ValueKey('neu-name'),
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        gesamt ? 'Name des Gesamtprojekts' : 'Projektname',
                    helperText:
                        gesamt ? 'Etwa die Anfrage: „Grillsortiment"' : null,
                  ),
                  onSubmitted: (_) => _anlegen(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _kunde,
                  decoration: InputDecoration(
                    labelText: 'Kunde',
                    helperText: gesamt ? 'Gilt für alle Muster' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (vorschlaege.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final k in vorschlaege)
                        ActionChip(
                          label: Text(k),
                          onPressed: () => setState(() => _kunde.text = k),
                        ),
                    ],
                  ),
                ],
                if (!gesamt) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nummer,
                    decoration:
                        const InputDecoration(labelText: 'Artikelnummer'),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _idee,
                  minLines: 2,
                  maxLines: aus == null ? 4 : 8,
                  decoration: InputDecoration(
                    labelText: gesamt ? 'Worum es geht' : 'Produktidee',
                  ),
                ),
                if (gesamt) ...[
                  const SizedBox(height: 14),
                  Text('Muster', style: theme.textTheme.titleSmall),
                  Text(
                    'Je Produkt, das aus der Anfrage entsteht, ein Muster — '
                    'mit eigener Rezeptur und eigenem Weg. Weitere lassen '
                    'sich jederzeit anlegen.',
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                  const SizedBox(height: 6),
                  for (final (i, c) in _muster.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: ValueKey('neu-muster-$i'),
                              controller: c,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: 'Muster ${i + 1}',
                                hintText: 'Name — leer: „Muster ${i + 1}"',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Muster entfernen',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _muster.length <= 1
                                ? null
                                : () => setState(() {
                                      _muster.removeAt(i).dispose();
                                    }),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('neu-muster-mehr'),
                      onPressed: () => setState(
                        () => _muster.add(TextEditingController()),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Weiteres Muster'),
                    ),
                  ),
                ],
              ],
              if (fehler != null) ...[
                const SizedBox(height: 10),
                Text(
                  fehler,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _speichert ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _speichert ? null : _anlegen,
          child: Text(ablegen ? 'Ablegen' : 'Anlegen'),
        ),
      ],
    );
  }
}

/// Die Mail, aus der ein Projekt entsteht: Betreff, Absender, Datum und
/// was mit ihr geschieht.
class _MailZeile extends StatelessWidget {
  const _MailZeile({required this.mail, this.art = NeuArt.produkt});

  final Mail mail;
  final NeuArt art;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final m = mail;
    final datum = m.datum;
    final anhaenge = m.anhaenge.length;
    final groesse = m.anhaenge.fold<int>(0, (s, a) => s + a.inhalt.length);
    final anhangText =
        anhaenge == 1 ? 'ihr Anhang' : 'ihre $anhaenge Anhänge';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppMasse.ecken,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mail_outline, size: 18, color: grau),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mailTitel(m),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  [
                    if (m.von.isNotEmpty) m.von,
                    if (datum != null) Format.datum(datum),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    switch (art) {
                      NeuArt.produkt =>
                        'Die Mail kommt als Anfrage in den Verlauf',
                      NeuArt.gesamtprojekt => 'Die Mail kommt als Anfrage in '
                          'den Verlauf des Gesamtprojekts — und damit zu '
                          'allen Mustern',
                      NeuArt.ablegen => 'Die Mail kommt in den Verlauf des '
                          'Gesamtprojekts — und damit zu allen Mustern',
                    },
                    if (anhaenge > 0)
                      ', $anhangText (${groesseText(groesse)}) zu den Dateien',
                    '.',
                  ].join(),
                  style: theme.textTheme.bodySmall?.copyWith(color: grau),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

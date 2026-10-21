// `show Value`: drift bringt eine eigene Klasse `Column` mit.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/auto_backup_trigger.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/fehler_text.dart';
import '../../../core/utils/format.dart';
import '../daten/dateien.dart';
import '../daten/entwicklung_repository.dart';
import '../haccp/prozess_modell.dart';
import '../rezepturen/rezepturen_ansicht.dart';
import 'datei_aktionen.dart';
import 'projekt_dateien.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';

/// Der zuletzt verwendete Name für Einträge und Kommentare — gilt, bis
/// die App schließt.
final entwicklungNameProvider = StateProvider<String>((ref) => '');

/// Die Farbe eines Eintragsstatus.
StatusArt eintragStatusArt(EintragStatus s) => switch (s) {
      EintragStatus.offen => StatusArt.warnung,
      EintragStatus.erhalten => StatusArt.info,
      EintragStatus.ok || EintragStatus.erledigt => StatusArt.ok,
    };

/// Der Verlauf eines Projekts: Meilensteine, Rezepturstände, Mails,
/// Parameter, Dateien und Notizen — der neueste zuerst.
class ProjektVerlauf extends ConsumerWidget {
  const ProjektVerlauf({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  Future<void> _neu(BuildContext context, WidgetRef ref) async {
    final eingabe = await showDialog<EintragEingabe>(
      context: context,
      builder: (_) => EintragDialog(name: ref.read(entwicklungNameProvider)),
    );
    if (eingabe == null || !context.mounted) return;
    try {
      final datei = eingabe.datei;
      final dateiId = datei == null
          ? null
          : await dateiAblegen(ref, datei, projektId: projekt.id);
      await ref.read(projektRepositoryProvider).eintragAnlegen(
            projektId: projekt.id,
            art: eingabe.art,
            titel: eingabe.titel,
            datum: eingabe.datum,
            benutzer: eingabe.benutzer,
            beschreibung: eingabe.beschreibung,
            status: eingabe.status,
            ziel: eingabe.ziel,
            dateiId: dateiId,
          );
      if (eingabe.benutzer != null) {
        ref.read(entwicklungNameProvider.notifier).state = eingabe.benutzer!;
      }
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final eintraege = ref.watch(projektEintraegeProvider(projekt.id));
    final dateien = {
      for (final d in ref.watch(projektDateienProvider(projekt.id)).valueOrNull ??
          const <EntwicklungsDatei>[])
        d.id: d,
    };
    final versionen = {
      for (final v in ref.watch(alleVersionenProvider).valueOrNull ??
          const <RezepturVersion>[])
        v.id: v,
    };
    return eintraege.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: HinweisBox(
          fehlerText(e),
          art: StatusArt.fehler,
          titel: 'Der Verlauf ließ sich nicht laden',
          auswaehlbar: true,
        ),
      ),
      data: (liste) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${liste.length} '
                  '${liste.length == 1 ? 'Eintrag' : 'Einträge'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => dateiAlsEintrag(context, ref, projekt.id),
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Datei ablegen'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _neu(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neuer Eintrag'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (liste.isEmpty)
            const LeerHinweis(
              'Noch keine Einträge.',
              icon: Icons.history,
            ),
          for (final e in liste)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EintragKarte(
                eintrag: e,
                datei: dateien[e.dateiId],
                version: versionen[e.versionId],
              ),
            ),
        ],
      ),
    );
  }
}

void _fehler(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Speichern fehlgeschlagen: ${fehlerText(e)}')),
  );
}

/// Ein Eintrag im Verlauf als Karte.
class EintragKarte extends ConsumerWidget {
  const EintragKarte({
    super.key,
    required this.eintrag,
    this.datei,
    this.version,
  });

  final ProjektEintrag eintrag;

  /// Die angehängte Datei — null, wenn keine da ist.
  final EntwicklungsDatei? datei;

  /// Der Rezepturstand, um den es geht.
  final RezepturVersion? version;

  Future<void> _bearbeiten(BuildContext context, WidgetRef ref) async {
    final eingabe = await showDialog<EintragEingabe>(
      context: context,
      builder: (_) => EintragDialog(eintrag: eintrag),
    );
    if (eingabe == null || !context.mounted) return;
    try {
      await ref.read(projektRepositoryProvider).eintragAendern(
            eintrag.id,
            EntwicklungProjektEintraegeCompanion(
              art: Value(eingabe.art.schluessel),
              titel: Value(eingabe.titel),
              datum: Value(eingabe.datum),
              benutzer: Value(eingabe.benutzer),
              beschreibung: Value(eingabe.beschreibung),
              status: Value(eingabe.status.schluessel),
              ziel: Value(eingabe.ziel),
            ),
          );
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  Future<void> _kommentieren(BuildContext context, WidgetRef ref) async {
    final kommentar = await showDialog<Kommentar>(
      context: context,
      builder: (_) => KommentarDialog(name: ref.read(entwicklungNameProvider)),
    );
    if (kommentar == null || !context.mounted) return;
    try {
      await ref
          .read(projektRepositoryProvider)
          .kommentieren(eintrag.id, kommentar);
      ref.read(entwicklungNameProvider.notifier).state = kommentar.name;
      ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Kommentar');
    } catch (e) {
      if (context.mounted) _fehler(context, e);
    }
  }

  Future<void> _loeschen(BuildContext context, WidgetRef ref) async {
    final mitDatei = datei != null;
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text(
          mitDatei
              ? '„${eintrag.titel}" wird mit der angehängten Datei gelöscht.'
              : '„${eintrag.titel}" wird gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    final d = datei;
    if (d != null) {
      await ref.read(entwicklungDateienProvider).loeschen(d.id);
      await ref.read(projektRepositoryProvider).dateiVerweiseEntfernen(d.id);
    }
    await ref.read(projektRepositoryProvider).eintragLoeschen(eintrag.id);
    ref.read(autoBackupTriggerProvider).fireDebounced(reason: 'Eintrag');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final e = eintrag;
    final art = EintragArt.aus(e.art);
    final status = EintragStatus.aus(e.status);
    final kopfzeile = [
      Format.datum(e.datum),
      if ((e.benutzer ?? '').trim().isNotEmpty) e.benutzer!.trim(),
      art.label,
    ].join(' · ');
    final beschreibung = e.beschreibung?.trim() ?? '';
    final ziel = e.ziel?.trim() ?? '';
    final aenderungen = texteAus(e.aenderungen);
    final kommentare = Kommentar.listeAus(e.kommentare);
    final parameter =
        art == EintragArt.parameter ? Prozessparameter.aus(e.wert) : null;
    final v = version;
    final d = datei;

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppMasse.ecken,
              ),
              child: Icon(art.icon, size: 18, color: grau),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.titel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusMarke(status.label, art: eintragStatusArt(status)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kopfzeile,
                    style: theme.textTheme.bodySmall?.copyWith(color: grau),
                  ),
                  if (beschreibung.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(beschreibung),
                  ],
                  if (ziel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ziel: $ziel',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (aenderungen.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (final a in aenderungen)
                      Text(
                        '• $a',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      ),
                  ],
                  if (parameter != null && !parameter.leer) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Prozessparameter Version ${parameter.version} · '
                      '${parameter.abschnitte.length} '
                      '${parameter.abschnitte.length == 1 ? 'Abschnitt' : 'Abschnitte'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (e.versionId != null) ...[
                    const SizedBox(height: 4),
                    if (v == null)
                      Text(
                        'Der Rezepturstand ist nicht mehr da.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: grau,
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => oeffneRezeptur(context, v.rezepturId),
                          icon: const Icon(Icons.menu_book_outlined, size: 16),
                          label: Text('Rezepturstand ${v.nummer} öffnen'),
                        ),
                      ),
                  ],
                  if (d != null) ...[
                    const SizedBox(height: 4),
                    DateiZeile(datei: d, loeschbar: false),
                  ] else if (e.dateiId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Die Datei ist nicht mehr da.',
                      style: theme.textTheme.bodySmall?.copyWith(color: grau),
                    ),
                  ],
                  if (kommentare.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final (i, k) in kommentare.indexed)
                      _KommentarZeile(
                        kommentar: k,
                        onLoeschen: () => ref
                            .read(projektRepositoryProvider)
                            .kommentarLoeschen(e.id, i),
                      ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (wahl) {
                switch (wahl) {
                  case 'bearbeiten':
                    _bearbeiten(context, ref);
                  case 'kommentieren':
                    _kommentieren(context, ref);
                  case 'loeschen':
                    _loeschen(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'kommentieren', child: Text('Kommentieren')),
                PopupMenuItem(value: 'bearbeiten', child: Text('Bearbeiten')),
                PopupMenuItem(value: 'loeschen', child: Text('Löschen')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KommentarZeile extends StatelessWidget {
  const _KommentarZeile({required this.kommentar, required this.onLoeschen});

  final Kommentar kommentar;
  final VoidCallback onLoeschen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final k = kommentar;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.colorScheme.outline, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  [
                    if (k.name.trim().isNotEmpty) k.name.trim(),
                    Format.datum(k.datum),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(color: grau),
                ),
                const SizedBox(height: 2),
                SelectableText(k.text, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kommentar löschen',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14),
            onPressed: onLoeschen,
          ),
        ],
      ),
    );
  }
}

/// Was das Eintragsfenster zurückgibt.
class EintragEingabe {
  const EintragEingabe({
    required this.art,
    required this.titel,
    required this.datum,
    required this.status,
    this.benutzer,
    this.beschreibung,
    this.ziel,
    this.datei,
  });

  final EintragArt art;
  final String titel;
  final DateTime datum;
  final EintragStatus status;
  final String? benutzer;
  final String? beschreibung;
  final String? ziel;

  /// Eine neu gewählte Datei — nur beim Anlegen.
  final GewaehlteDatei? datei;
}

/// Neuer Eintrag oder Eintrag bearbeiten.
class EintragDialog extends StatefulWidget {
  const EintragDialog({super.key, this.eintrag, this.name = ''});

  /// Der Eintrag zum Bearbeiten — null: ein neuer.
  final ProjektEintrag? eintrag;

  /// Der Name, der beim neuen Eintrag vorbelegt ist.
  final String name;

  @override
  State<EintragDialog> createState() => _EintragDialogState();
}

class _EintragDialogState extends State<EintragDialog> {
  late EintragArt _art;
  late EintragStatus _status;
  late DateTime _datum;
  late final TextEditingController _titel;
  late final TextEditingController _benutzer;
  late final TextEditingController _beschreibung;
  late final TextEditingController _ziel;
  GewaehlteDatei? _datei;
  String? _fehler;

  /// Arten, die man von Hand anlegt — Rezepturstände und Parameter
  /// entstehen beim Abschließen bzw. Speichern von selbst.
  static const List<EintragArt> _waehlbar = [
    EintragArt.meilenstein,
    EintragArt.notiz,
    EintragArt.email,
    EintragArt.datei,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.eintrag;
    final heute = DateTime.now();
    _art = e == null ? EintragArt.meilenstein : EintragArt.aus(e.art);
    _status = e == null ? EintragStatus.offen : EintragStatus.aus(e.status);
    _datum = e?.datum ?? DateTime(heute.year, heute.month, heute.day);
    _titel = TextEditingController(text: e?.titel ?? '');
    _benutzer = TextEditingController(text: e?.benutzer ?? widget.name);
    _beschreibung = TextEditingController(text: e?.beschreibung ?? '');
    _ziel = TextEditingController(text: e?.ziel ?? '');
  }

  @override
  void dispose() {
    _titel.dispose();
    _benutzer.dispose();
    _beschreibung.dispose();
    _ziel.dispose();
    super.dispose();
  }

  Future<void> _datumWaehlen() async {
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (gewaehlt != null && mounted) setState(() => _datum = gewaehlt);
  }

  Future<void> _dateiWaehlen() async {
    final d = await dateiWaehlen(context);
    if (d == null || !mounted) return;
    setState(() {
      _datei = d;
      if (_titel.text.trim().isEmpty) _titel.text = d.name;
    });
  }

  String? _oderNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _fertig() {
    final titel = _titel.text.trim();
    if (titel.isEmpty) {
      setState(() => _fehler = 'Bitte einen Titel eingeben.');
      return;
    }
    Navigator.of(context).pop(
      EintragEingabe(
        art: _art,
        titel: titel,
        datum: _datum,
        status: _status,
        benutzer: _oderNull(_benutzer),
        beschreibung: _oderNull(_beschreibung),
        ziel: _oderNull(_ziel),
        datei: _datei,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neu = widget.eintrag == null;
    final arten = _waehlbar.contains(_art) ? _waehlbar : [..._waehlbar, _art];
    final fehler = _fehler;
    final datei = _datei;
    return AlertDialog(
      title: Text(neu ? 'Neuer Eintrag' : 'Eintrag bearbeiten'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in arten)
                    ChoiceChip(
                      avatar: Icon(a.icon, size: 16),
                      label: Text(a.label),
                      selected: _art == a,
                      onSelected: (_) => setState(() => _art = a),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titel,
                autofocus: neu,
                decoration: const InputDecoration(labelText: 'Titel'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _datumWaehlen,
                      icon: const Icon(Icons.event_note, size: 18),
                      label: Text(Format.datum(_datum)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<EintragStatus>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final s in EintragStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (s) {
                        if (s != null) setState(() => _status = s);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _benutzer,
                      decoration: const InputDecoration(labelText: 'Von'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ziel,
                      decoration: const InputDecoration(
                        labelText: 'Ziel',
                        hintText: 'z. B. KW 12',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _beschreibung,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Beschreibung'),
              ),
              if (neu) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _dateiWaehlen,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      datei == null
                          ? 'Datei anhängen'
                          : '${datei.name} (${groesseText(datei.inhalt.length)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _fertig,
          child: Text(neu ? 'Anlegen' : 'Speichern'),
        ),
      ],
    );
  }
}

/// Ein Kommentar: Name und Text.
class KommentarDialog extends StatefulWidget {
  const KommentarDialog({super.key, this.name = ''});

  final String name;

  @override
  State<KommentarDialog> createState() => _KommentarDialogState();
}

class _KommentarDialogState extends State<KommentarDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  final _text = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _fertig() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(
      Kommentar(name: _name.text.trim(), text: text, datum: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kommentar'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Von'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Kommentar'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _fertig, child: const Text('Hinzufügen')),
      ],
    );
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/abteilungen.dart';
import '../../core/database/database.dart';
import '../../core/services/prozess_vorlagen.dart';
import '../../core/services/prozesskette_service.dart';
import '../articles/article_detail_providers.dart' show alleMaschinenProvider;
import 'vorlage_anzeige.dart';

/// Öffnet [vorlage] zum Bearbeiten. Gibt die geänderte Vorlage zurück —
/// null, wenn abgebrochen.
Future<ProzessVorlage?> vorlageBearbeiten(
  BuildContext context,
  ProzessVorlage vorlage,
) =>
    Navigator.of(context).push<ProzessVorlage>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VorlageBearbeiten(vorlage: vorlage),
      ),
    );

/// Die Stichworte als ein Text: Einträge mit Komma getrennt.
String _stichwortFeld(List<String> liste) => liste.join(', ');

List<String> _stichworteAus(String text) => [
      for (final t in text.split(','))
        if (t.trim().isNotEmpty) t.trim(),
    ];

/// Vorlage bearbeiten: Name, Stichworte und die Schritte.
class VorlageBearbeiten extends ConsumerStatefulWidget {
  const VorlageBearbeiten({super.key, required this.vorlage});

  final ProzessVorlage vorlage;

  @override
  ConsumerState<VorlageBearbeiten> createState() => _VorlageBearbeitenState();
}

class _VorlageBearbeitenState extends ConsumerState<VorlageBearbeiten> {
  late final _name = TextEditingController(text: widget.vorlage.name);
  late final _muss = TextEditingController(
    text: _stichwortFeld(widget.vorlage.muss),
  );
  late final _nicht = TextEditingController(
    text: _stichwortFeld(widget.vorlage.nicht),
  );

  /// Die Schritte mit einem Schlüssel je Zeile, damit Felder beim
  /// Verschieben bei ihrer Zeile bleiben.
  late final List<(int, VorlagenSchritt)> _schritte = [
    for (final s in widget.vorlage.schritte) (_naechster++, s),
  ];
  int _naechster = 0;
  String? _fehler;

  @override
  void dispose() {
    _name.dispose();
    _muss.dispose();
    _nicht.dispose();
    super.dispose();
  }

  void _setze(int i, VorlagenSchritt s) =>
      setState(() => _schritte[i] = (_schritte[i].$1, s));

  void _schiebe(int i, int nach) => setState(() {
        final e = _schritte.removeAt(i);
        _schritte.insert(nach, e);
      });

  void _dazu() => setState(() {
        final letzte = _schritte.isEmpty ? null : _schritte.last.$2.abteilung;
        _schritte.add(
          (
            _naechster++,
            VorlagenSchritt(
              abteilung: letzte ?? Abteilung.values.first.dbValue,
            ),
          ),
        );
      });

  void _speichern() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _fehler = 'Die Vorlage braucht einen Namen.');
      return;
    }
    if (_schritte.length > ProzesskettenService.maxSchritte) {
      setState(
        () => _fehler = 'Höchstens ${ProzesskettenService.maxSchritte} '
            'Schritte — so viele hat ein Artikel.',
      );
      return;
    }
    Navigator.of(context).pop(
      widget.vorlage.kopie(
        name: name,
        muss: _stichworteAus(_muss.text),
        nicht: _stichworteAus(_nicht.text),
        schritte: [for (final e in _schritte) e.$2],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final maschinen =
        ref.watch(alleMaschinenProvider).valueOrNull ?? const <Machine>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vorlage bearbeiten'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const ValueKey('vorlage-speichern'),
              onPressed: _speichern,
              child: const Text('Übernehmen'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('vorlage-name'),
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'z. B. Schnitzel paniert, gebraten',
                      errorText: _fehler,
                    ),
                    onChanged: (_) => setState(() => _fehler = null),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('vorlage-muss'),
                    controller: _muss,
                    decoration: const InputDecoration(
                      labelText: 'Vorschlagen, wenn die Bezeichnung enthält',
                      hintText: 'schnitzel, panier, gebrat|gegart',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Alle Einträge (mit Komma getrennt) müssen vorkommen; '
                    'Alternativen mit | („gebrat|gegart"). Groß und klein '
                    'und Umlaute sind egal. Mit = davor zählt nur das ganze '
                    'Wort („=roh" trifft nicht „Rohware").',
                    style: grau,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('vorlage-nicht'),
                    controller: _nicht,
                    decoration: const InputDecoration(
                      labelText: 'Nicht vorschlagen, wenn sie enthält',
                      hintText: '=roh, cordon',
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        'Schritte (${_schritte.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        key: const ValueKey('vorlage-schritt-dazu'),
                        onPressed: _dazu,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Schritt'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_schritte.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Noch keine Schritte — mit „Schritt" anlegen.',
                        style: grau,
                      ),
                    ),
                  for (final (i, (schluessel, s)) in _schritte.indexed)
                    _SchrittZeile(
                      key: ValueKey('vorlage-schritt-$schluessel'),
                      nummer: i + 1,
                      schritt: s,
                      maschinen: maschinen,
                      onAendern: (neu) => _setze(i, neu),
                      onHoch: i == 0 ? null : () => _schiebe(i, i - 1),
                      onRunter: i == _schritte.length - 1
                          ? null
                          : () => _schiebe(i, i + 1),
                      onWeg: () => setState(() => _schritte.removeAt(i)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Zeile im Editor: Abteilung, Anlage, Tätigkeit, Verschieben.
class _SchrittZeile extends StatefulWidget {
  const _SchrittZeile({
    super.key,
    required this.nummer,
    required this.schritt,
    required this.maschinen,
    required this.onAendern,
    required this.onHoch,
    required this.onRunter,
    required this.onWeg,
  });

  final int nummer;
  final VorlagenSchritt schritt;
  final List<Machine> maschinen;
  final ValueChanged<VorlagenSchritt> onAendern;
  final VoidCallback? onHoch;
  final VoidCallback? onRunter;
  final VoidCallback onWeg;

  @override
  State<_SchrittZeile> createState() => _SchrittZeileState();
}

class _SchrittZeileState extends State<_SchrittZeile> {
  late final _taetigkeit = TextEditingController(
    text: widget.schritt.prozessschritt ?? '',
  );

  @override
  void dispose() {
    _taetigkeit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schritt;
    // Die Anlagen der Abteilung zuerst, dann alle übrigen.
    final eigene = [
      for (final m in widget.maschinen)
        if (m.abteilung == s.abteilung) m,
    ];
    final andere = [
      for (final m in widget.maschinen)
        if (m.abteilung != s.abteilung) m,
    ];
    final bekannt = widget.maschinen.any((m) => m.id == s.maschineId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${widget.nummer}.',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          Abteilung.values.any((a) => a.dbValue == s.abteilung)
                              ? s.abteilung
                              : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Abteilung',
                        isDense: true,
                      ),
                      items: [
                        for (final a in Abteilung.values)
                          DropdownMenuItem(
                            value: a.dbValue,
                            child: Text(a.anzeigeName),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) widget.onAendern(s.kopie(abteilung: v));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      // Neu aufbauen, wenn die Abteilung wechselt — die
                      // Liste sortiert sich dann um.
                      key: ValueKey('anlage-${s.abteilung}-${s.maschineId}'),
                      initialValue: bekannt ? s.maschineId : '',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Anlage',
                        isDense: true,
                        helperText: !bekannt && s.maschine != null
                            ? 'nicht im Katalog: ${s.maschine}'
                            : null,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('— ohne Anlage —'),
                        ),
                        for (final m in [...eigene, ...andere])
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.abteilung == s.abteilung
                                  ? m.name
                                  : '${m.name} '
                                      '(${abteilungsName(m.abteilung)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        final m = widget.maschinen
                            .where((m) => m.id == v)
                            .firstOrNull;
                        widget.onAendern(
                          s.kopie(
                            maschineId: Value(m?.id),
                            maschine: Value(m?.name),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _taetigkeit,
                      decoration: const InputDecoration(
                        labelText: 'Tätigkeit (optional)',
                        hintText: 'z. B. von Hand vereinzeln',
                        isDense: true,
                      ),
                      onChanged: (t) => widget.onAendern(
                        s.kopie(
                          prozessschritt:
                              Value(t.trim().isEmpty ? null : t.trim()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Nach oben',
              onPressed: widget.onHoch,
              icon: const Icon(Icons.arrow_upward, size: 18),
            ),
            IconButton(
              tooltip: 'Nach unten',
              onPressed: widget.onRunter,
              icon: const Icon(Icons.arrow_downward, size: 18),
            ),
            IconButton(
              tooltip: 'Schritt entfernen',
              onPressed: widget.onWeg,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

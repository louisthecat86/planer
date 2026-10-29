import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../daten/entwicklung_repository.dart';
import 'angaben_assistent.dart';
import 'angaben_luecken.dart';
import 'entwicklungsstrang.dart';
import 'faellig.dart';
import 'projekt_checkliste.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_screen.dart';
import 'zeitstrahl.dart' show phasenFarbe;

// Der Kopf einer Projektseite — auf jedem Reiter gleich: in welcher Phase
// das Projekt ist (zum Weiterschalten), wie weit die Checkliste ist, was
// als Nächstes zu tun ist (mit dem Weg dorthin), was zurückgestellt ist
// und noch fehlt (dezent, F37), wie viele Angaben fehlen (antippen startet
// den Assistenten, F39) und wie viele Einträge im Verlauf noch offen sind
// (überfällige in der Farbe für Fehler).

/// Die Phasen der Reihe nach — „Nicht weiter verfolgen" und das Archiv
/// stehen im Menü.
const List<ProjektStatus> _phasen = [
  ProjektStatus.entwicklung,
  ProjektStatus.validierung,
  ProjektStatus.produktion,
];

/// Fragt, ob das Projekt in [neu] wechseln soll, und wechselt dann. Für
/// „Nicht weiter verfolgt" fragt es nach dem Grund.
Future<void> phaseWechseln(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
  ProjektStatus neu,
) async {
  final alt = ProjektStatus.aus(projekt.status);
  if (alt == neu) return;
  if (neu == ProjektStatus.eingestellt) {
    final grund = await showDialog<String>(
      context: context,
      builder: (_) => _NichtWeiterDialog(
        muster: projekt.gesamtprojektId != null,
        name: projekt.name,
      ),
    );
    if (grund == null || !context.mounted) return;
    await projektStatusAendern(context, ref, projekt.id, neu, grund: grund);
    return;
  }
  final ausDerRuhe = alt.ruht && !neu.ruht;
  final zurueck =
      !alt.ruht && _phasen.indexOf(neu) < _phasen.indexOf(alt);
  final titel = ausDerRuhe
      ? (projekt.gesamtprojektId == null
          ? 'Projekt wieder aufnehmen?'
          : 'Muster wieder aufnehmen?')
      : switch (neu) {
          ProjektStatus.entwicklung =>
            zurueck ? 'Zurück in die Entwicklung?' : 'In die Entwicklung?',
          ProjektStatus.validierung =>
            zurueck ? 'Zurück in die Validierung?' : 'Validierung beginnen?',
          ProjektStatus.produktion => 'In Produktion setzen?',
          ProjektStatus.eingestellt => 'Nicht weiter verfolgen?',
          ProjektStatus.archiviert => 'Projekt archivieren?',
        };
  final ja = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titel),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(
          [
            if (ausDerRuhe)
              'Es geht in der Phase „${neu.label}" weiter.',
            'Der Wechsel steht danach als Meilenstein im Verlauf.',
            if (neu == ProjektStatus.produktion && projekt.artikelId == null)
              'Mit „Als Artikel freigeben" in der Übersicht entsteht dabei '
                  'auch der Artikel in der Planung.',
            if (neu == ProjektStatus.archiviert)
              'Archivierte Projekte stehen in der Liste unter „Archiv" und '
                  'lassen sich jederzeit wieder aufnehmen.',
          ].join('\n\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            switch (neu) {
              ProjektStatus.archiviert => 'Archivieren',
              _ when ausDerRuhe => 'Wieder aufnehmen',
              _ => 'Wechseln',
            },
          ),
        ),
      ],
    ),
  );
  if (ja != true || !context.mounted) return;
  await projektStatusAendern(context, ref, projekt.id, neu);
}

/// Fragt, ob ein Projekt oder Muster nicht weiter verfolgt werden soll —
/// mit dem Grund, der danach im Verlauf steht. Gibt den Grund zurück
/// (leer, wenn keiner genannt ist), bei „Abbrechen" null.
class _NichtWeiterDialog extends StatefulWidget {
  const _NichtWeiterDialog({required this.muster, required this.name});

  final bool muster;
  final String name;

  @override
  State<_NichtWeiterDialog> createState() => _NichtWeiterDialogState();
}

class _NichtWeiterDialogState extends State<_NichtWeiterDialog> {
  final _grund = TextEditingController();

  @override
  void dispose() {
    _grund.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final was = widget.muster ? 'Das Muster' : 'Das Projekt';
    return AlertDialog(
      title: Text(
        widget.muster
            ? 'Muster nicht weiter verfolgen?'
            : 'Projekt nicht weiter verfolgen?',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$was „${widget.name}" ruht danach — mit allem, was dazu '
              'gehört. Es steht in der Liste unter „Nicht weiter verfolgt" '
              'und lässt sich jederzeit wieder aufnehmen.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('nicht-weiter-grund'),
              controller: _grund,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Grund',
                hintText: 'z. B. Der Kunde hat sich für ein anderes Muster '
                    'entschieden.',
                helperText: 'Steht als Meilenstein im Verlauf',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_grund.text.trim()),
          child: const Text('Nicht weiter verfolgen'),
        ),
      ],
    );
  }
}

/// Der Kopf über den Reitern.
class ProjektKopf extends ConsumerWidget {
  const ProjektKopf({super.key, required this.projekt});

  final EntwicklungsProjekt projekt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rezepturen = ref.watch(projektRezepturenProvider(projekt.id));
    final versionen = ref.watch(alleVersionenProvider);
    final eintraege =
        ref.watch(projektEintraegeProvider(projekt.id)).valueOrNull ??
            const <ProjektEintrag>[];
    final r = rezepturen.valueOrNull;
    final v = versionen.valueOrNull;
    final check = r == null || v == null
        ? null
        : projektCheckStand(projekt: projekt, rezepturen: r, versionen: v);
    final offen = offeneZaehlen(eintraege, heute: DateTime.now());

    final phase = _PhasenLeiste(
      projekt: projekt,
      onWahl: (s) => phaseWechseln(context, ref, projekt, s),
      onWiederAufnehmen: () => phaseWechseln(
        context,
        ref,
        projekt,
        phaseVorDemArchiv(eintraege),
      ),
    );
    // Ruht das Projekt, fragt der Kopf nach nichts.
    final ruht = ProjektStatus.aus(projekt.status).ruht;
    final fehlend =
        ruht ? const <AngabeSchritt>[] : fehlendeAngaben(projekt);
    final fortschritt = _Fortschritt(
      projektId: projekt.id,
      check: check,
      offen: offen,
      fehlend: fehlend,
      onAngaben: () => angabenErgaenzen(context, projekt),
    );
    return Container(
      key: const ValueKey('projekt-kopf'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppFarben.von(context).leiste,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  phase,
                  const SizedBox(width: 24),
                  Expanded(child: fortschritt),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [phase, const SizedBox(height: 10), fortschritt],
              ),
      ),
    );
  }
}

/// Entwicklung › Validierung › Produktion — die aktuelle hervorgehoben,
/// die anderen zum Antippen.
class _PhasenLeiste extends StatelessWidget {
  const _PhasenLeiste({
    required this.projekt,
    required this.onWahl,
    required this.onWiederAufnehmen,
  });

  final EntwicklungsProjekt projekt;
  final ValueChanged<ProjektStatus> onWahl;
  final VoidCallback onWiederAufnehmen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final status = ProjektStatus.aus(projekt.status);
    final ruht = status.ruht;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          switch (status) {
            ProjektStatus.archiviert => 'Phase · archiviert',
            ProjektStatus.eingestellt => 'Phase · nicht weiter verfolgt',
            _ => 'Phase',
          },
          key: const ValueKey('kopf-phase-titel'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: status == ProjektStatus.eingestellt
                ? phasenFarbe(context, status)
                : grau,
            fontWeight:
                status == ProjektStatus.eingestellt ? FontWeight.w600 : null,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 4,
          children: [
            for (final (i, s) in _phasen.indexed) ...[
              if (i > 0) Icon(Icons.chevron_right, size: 18, color: grau),
              _PhasenKnopf(
                status: s,
                aktuell: s == status,
                // Ruht das Projekt: erst wieder aufnehmen.
                onTap: ruht || s == status ? null : () => onWahl(s),
              ),
            ],
            if (ruht) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                key: const ValueKey('kopf-wieder-aufnehmen'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onWiederAufnehmen,
                icon: const Icon(Icons.unarchive_outlined, size: 16),
                label: const Text('Wieder aufnehmen'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PhasenKnopf extends StatelessWidget {
  const _PhasenKnopf({
    required this.status,
    required this.aktuell,
    required this.onTap,
  });

  final ProjektStatus status;
  final bool aktuell;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final farbe = phasenFarbe(context, status);
    final tippen = onTap;
    final inhalt = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        status.label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: aktuell ? farbe : theme.colorScheme.onSurfaceVariant,
          fontWeight: aktuell ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    final knopf = Material(
      key: ValueKey('phase-${status.schluessel}'),
      color: aktuell ? farbe.withValues(alpha: 0.14) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(
          color: aktuell ? farbe : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: tippen == null ? inhalt : InkWell(onTap: tippen, child: inhalt),
    );
    final hinweis = aktuell
        ? 'Hier steht das Projekt gerade'
        : tippen == null
            ? null
            : 'Zur Phase „${status.label}" wechseln';
    return hinweis == null ? knopf : Tooltip(message: hinweis, child: knopf);
  }
}

/// Wie weit die Checkliste ist, was als Nächstes kommt und was im Verlauf
/// offen ist.
class _Fortschritt extends StatelessWidget {
  const _Fortschritt({
    required this.projektId,
    required this.check,
    required this.offen,
    this.fehlend = const [],
    this.onAngaben,
  });

  final String projektId;
  final ProjektCheckStand? check;
  /// Die offenen Einträge im Verlauf — und wie viele davon überfällig
  /// sind.
  final OffeneEintraege offen;

  /// Angaben, die dem Projekt noch fehlen.
  final List<AngabeSchritt> fehlend;
  final VoidCallback? onAngaben;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final farben = AppFarben.von(context);
    final c = check;
    final naechster = c?.naechster;
    final zurueckgestellt = c?.zurueckgestellt ?? const <CheckStand>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Checkliste',
              style: theme.textTheme.labelSmall?.copyWith(color: grau),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c?.anteil,
                  minHeight: 6,
                  color: farben.ok,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              c?.text ?? '…',
              key: const ValueKey('kopf-checkliste'),
              style: theme.textTheme.labelMedium?.copyWith(color: grau),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (c != null && c.fertig)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 18, color: farben.ok),
                  const SizedBox(width: 6),
                  Text(
                    'Alles erledigt',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: farben.ok,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else if (naechster != null)
              Tooltip(
                message: naechster.text ?? naechster.punkt.label,
                child: TextButton.icon(
                  key: const ValueKey('kopf-naechster'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => checkpunktOeffnen(
                    context,
                    naechster,
                    projektId: projektId,
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('Als Nächstes: ${checkAufgabe(naechster)}'),
                ),
              ),
            // Zurückgestellt: dezent, aber nicht vergessen.
            for (final z in zurueckgestellt)
              TextButton.icon(
                key: ValueKey('kopf-fehlt-${z.punkt.schluessel}'),
                style: TextButton.styleFrom(
                  foregroundColor: grau,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    checkpunktOeffnen(context, z, projektId: projektId),
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(checkFehlt(z)),
              ),
            if (fehlend.isNotEmpty)
              Tooltip(
                message: 'Fehlt: ${angabenAufzaehlen(fehlend)}',
                child: TextButton.icon(
                  key: const ValueKey('kopf-angaben'),
                  style: TextButton.styleFrom(
                    foregroundColor: farben.warnung,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onAngaben,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: Text(
                    '${angabenFehlenText(fehlend.length)} — ergänzen…',
                  ),
                ),
              ),
            if (offen.offen > 0)
              TextButton.icon(
                key: const ValueKey('kopf-offen'),
                style: TextButton.styleFrom(
                  // Ist etwas überfällig, in der Farbe für Fehler.
                  foregroundColor: offen.ueberfaellig > 0
                      ? farben.fehler
                      : farben.warnung,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => projektReiterZeigen(
                  context,
                  ProjektReiter.verlauf,
                ),
                icon: const Icon(Icons.error_outline, size: 16),
                label: Text(offeneEintraegeText(offen, imVerlauf: true)),
              ),
          ],
        ),
      ],
    );
  }
}

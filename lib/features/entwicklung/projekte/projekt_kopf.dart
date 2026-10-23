import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../daten/entwicklung_repository.dart';
import 'angaben_assistent.dart';
import 'angaben_luecken.dart';
import 'entwicklungsstrang.dart';
import 'projekt_checkliste.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_screen.dart';
import 'zeitstrahl.dart' show phasenFarbe;

// Der Kopf einer Projektseite — auf jedem Reiter gleich: in welcher Phase
// das Projekt ist (zum Weiterschalten), wie weit die Checkliste ist, was
// als Nächstes zu tun ist (mit dem Weg dorthin), was zurückgestellt ist
// und noch fehlt (dezent, F37), wie viele Angaben fehlen (antippen startet
// den Assistenten, F39) und wie viele Einträge im Verlauf noch offen sind.

/// Die Phasen der Reihe nach — das Archiv steht im Menü.
const List<ProjektStatus> _phasen = [
  ProjektStatus.entwicklung,
  ProjektStatus.validierung,
  ProjektStatus.produktion,
];

/// Fragt, ob das Projekt in [neu] wechseln soll, und wechselt dann.
Future<void> phaseWechseln(
  BuildContext context,
  WidgetRef ref,
  EntwicklungsProjekt projekt,
  ProjektStatus neu,
) async {
  final alt = ProjektStatus.aus(projekt.status);
  if (alt == neu) return;
  final ausDemArchiv = alt == ProjektStatus.archiviert;
  final zurueck =
      !ausDemArchiv && _phasen.indexOf(neu) < _phasen.indexOf(alt);
  final titel = ausDemArchiv
      ? 'Projekt wieder aufnehmen?'
      : switch (neu) {
          ProjektStatus.entwicklung =>
            zurueck ? 'Zurück in die Entwicklung?' : 'In die Entwicklung?',
          ProjektStatus.validierung =>
            zurueck ? 'Zurück in die Validierung?' : 'Validierung beginnen?',
          ProjektStatus.produktion => 'In Produktion setzen?',
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
            if (ausDemArchiv)
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
              _ when ausDemArchiv => 'Wieder aufnehmen',
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
    final offen = eintraege
        .where((e) => EintragStatus.aus(e.status) == EintragStatus.offen)
        .length;

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
    // Archiviert ruht das Projekt — dann fragt der Kopf nach nichts.
    final archiviert =
        ProjektStatus.aus(projekt.status) == ProjektStatus.archiviert;
    final fehlend =
        archiviert ? const <AngabeSchritt>[] : fehlendeAngaben(projekt);
    final fortschritt = _Fortschritt(
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
    final archiviert = status == ProjektStatus.archiviert;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          archiviert ? 'Phase · archiviert' : 'Phase',
          style: theme.textTheme.labelSmall?.copyWith(color: grau),
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
                // Archiviert: erst wieder aufnehmen.
                onTap: archiviert || s == status ? null : () => onWahl(s),
              ),
            ],
            if (archiviert) ...[
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
    required this.check,
    required this.offen,
    this.fehlend = const [],
    this.onAngaben,
  });

  final ProjektCheckStand? check;
  final int offen;

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
                  onPressed: () => checkpunktOeffnen(context, naechster),
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
                onPressed: () => checkpunktOeffnen(context, z),
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
            if (offen > 0)
              TextButton.icon(
                key: const ValueKey('kopf-offen'),
                style: TextButton.styleFrom(
                  foregroundColor: farben.warnung,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => projektReiterZeigen(
                  context,
                  ProjektReiter.verlauf,
                ),
                icon: const Icon(Icons.error_outline, size: 16),
                label: Text(
                  offen == 1
                      ? '1 offener Eintrag im Verlauf'
                      : '$offen offene Einträge im Verlauf',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

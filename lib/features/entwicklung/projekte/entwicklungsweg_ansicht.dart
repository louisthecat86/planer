import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_stil.dart';
import '../../../core/ui/bausteine.dart';
import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../etikett/etikett_dialog.dart';
import '../rezepturen/rezepturen_ansicht.dart';
import '../rezepturen/versionsvergleich.dart';
import 'entwicklungsstrang.dart';
import 'projekt_modell.dart';
import 'projekt_repository.dart';
import 'projekt_rezeptur.dart' show projektRezepturZeigen;
import 'zeitstrahl.dart';

// Der Entwicklungsweg eines Produkts — von oben nach unten: die Idee und
// die Anfrage, dann jede Station (ein abgeschlossener Rezepturstand) mit
// dem Grund, was neu ist, den Kennzahlen und dem, was danach kam
// (Rückmeldungen, Mails, Spezifikationen), dazwischen die Wechsel der
// Phase — bis zur Freigabe und dem, was gerade in Arbeit ist.

/// Breite der Spalte mit Linie und Knoten.
const double _spalte = 40;

/// Der Entwicklungsweg eines Projekts.
class EntwicklungswegAnsicht extends ConsumerWidget {
  const EntwicklungswegAnsicht({
    super.key,
    required this.projekt,
    required this.eintraege,
    this.versionen = const {},
  });

  final EntwicklungsProjekt projekt;
  final List<ProjektEintrag> eintraege;

  /// Alle Rezepturstände nach ID.
  final Map<String, RezepturVersion> versionen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final punkte = entwicklungsweg(eintraege);
    final rezepturen =
        ref.watch(projektRezepturenProvider(projekt.id)).valueOrNull ??
            const <Rezeptur>[];

    // Die vorige Station derselben Rezeptur — für die Veränderung der
    // Kennzahlen und den Vergleich.
    final vorher = <String, String>{};
    final letzte = <String, String>{};
    for (final p in punkte.whereType<WegStation>()) {
      final rezepturId = versionen[p.versionId]?.rezepturId;
      if (rezepturId == null) continue;
      final davor = letzte[rezepturId];
      if (davor != null) vorher[p.versionId] = davor;
      letzte[rezepturId] = p.versionId;
    }
    final stationen = {
      for (final p in punkte.whereType<WegStation>()) p.versionId,
    };
    final inArbeit = [
      for (final r in rezepturen)
        for (final v in versionen.values)
          if (v.rezepturId == r.id &&
              v.status == VersionStatus.entwurf &&
              !stationen.contains(v.id))
            (rezeptur: r, version: v),
    ]..sort((a, b) => a.version.updatedAt.compareTo(b.version.updatedAt));
    final freigabe = projekt.freigabeVersionId;

    final schritte = <({Widget knoten, Widget inhalt, bool klein})>[
      for (final p in punkte)
        switch (p) {
          WegAnfang() => (
              knoten: const _Knoten(icon: Icons.lightbulb_outline),
              inhalt: _AnfangKarte(projekt: projekt, eintraege: p.eintraege),
              klein: false,
            ),
          WegStation() => (
              knoten: _Knoten(
                nummer: versionen[p.versionId]?.nummer,
                farbe: eintragFarbe(context, EintragArt.rezeptur),
              ),
              inhalt: _StationKarte(
                station: p,
                version: versionen[p.versionId],
                vorherId: vorher[p.versionId],
                versionen: versionen,
                freigegeben: freigabe == p.versionId,
              ),
              klein: false,
            ),
          // Der Schritt in die Produktion — meist die Freigabe — sticht
          // heraus.
          WegPhase(status: ProjektStatus.produktion) => (
              knoten: _Knoten(
                icon: Icons.verified_outlined,
                farbe: phasenFarbe(context, p.status),
              ),
              inhalt: _PhasenZeile(
                phase: p,
                stand: versionen[p.eintrag.versionId]?.nummer,
                gross: true,
              ),
              klein: false,
            ),
          WegPhase() => (
              knoten: _Knoten(
                farbe: phasenFarbe(context, p.status),
                klein: true,
              ),
              inhalt: _PhasenZeile(
                phase: p,
                stand: versionen[p.eintrag.versionId]?.nummer,
              ),
              klein: true,
            ),
        },
      if (!punkte.any((p) => p is WegStation))
        (
          knoten: const _Knoten(icon: Icons.more_horiz),
          inhalt: const _Hinweis(
            'Noch kein abgeschlossener Stand. Sobald du in der Rezeptur '
            'einen Stand abschließt, steht er hier als Station — mit dem, '
            'was neu ist, und den Rückmeldungen dazu.',
          ),
          klein: false,
        ),
      for (final a in inArbeit)
        (
          knoten: const _Knoten(icon: Icons.edit_outlined),
          inhalt: _InArbeitZeile(rezeptur: a.rezeptur, version: a.version),
          klein: false,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in schritte.indexed)
          _Schritt(
            knoten: s.knoten,
            klein: s.klein,
            letzter: i == schritte.length - 1,
            child: s.inhalt,
          ),
      ],
    );
  }
}

/// Ein Schritt des Wegs: links die Linie mit dem Knoten, rechts der
/// Inhalt.
class _Schritt extends StatelessWidget {
  const _Schritt({
    required this.knoten,
    required this.child,
    this.klein = false,
    this.letzter = false,
  });

  final Widget knoten;
  final Widget child;
  final bool klein;
  final bool letzter;

  @override
  Widget build(BuildContext context) {
    final linie = Theme.of(context).colorScheme.outlineVariant;
    return Stack(
      children: [
        Positioned(
          left: _spalte / 2 - 1.5,
          width: 3,
          top: 0,
          bottom: letzter ? null : 0,
          height: letzter ? 18 : null,
          child: ColoredBox(color: linie),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: _spalte + 8,
            bottom: klein ? 8 : 14,
          ),
          child: child,
        ),
        Positioned(
          left: 0,
          top: klein ? 2 : 6,
          width: _spalte,
          child: Center(child: knoten),
        ),
      ],
    );
  }
}

/// Ein Knoten auf der Linie: eine Nummer, ein Symbol oder ein Punkt.
class _Knoten extends StatelessWidget {
  const _Knoten({this.nummer, this.icon, this.farbe, this.klein = false});

  final int? nummer;
  final IconData? icon;
  final Color? farbe;
  final bool klein;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hinten = farbe ?? theme.colorScheme.surfaceContainerHighest;
    final vorne = farbe == null
        ? theme.colorScheme.onSurfaceVariant
        : (ThemeData.estimateBrightnessForColor(hinten) == Brightness.dark
            ? Colors.white
            : const Color(0xFF1B1B1B));
    final groesse = klein ? 14.0 : 30.0;
    final n = nummer;
    final symbol = icon;
    return Container(
      width: groesse,
      height: groesse,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hinten,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      child: klein
          ? null
          : Center(
              child: n != null
                  ? Text(
                      '$n',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: vorne,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : Icon(symbol ?? Icons.circle, size: 16, color: vorne),
            ),
    );
  }
}

/// Eine Karte auf dem Weg.
class _Karte extends StatelessWidget {
  const _Karte({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppMasse.ecken,
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: child,
      ),
    );
  }
}

class _Hinweis extends StatelessWidget {
  const _Hinweis(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Die Idee: Produktidee, Kunde, Vereinbarungen und was vor dem ersten
/// Stand geschah.
class _AnfangKarte extends StatelessWidget {
  const _AnfangKarte({required this.projekt, required this.eintraege});

  final EntwicklungsProjekt projekt;
  final List<ProjektEintrag> eintraege;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final p = projekt;
    final idee = p.produktidee?.trim() ?? '';
    final vereinbart = p.kundenvereinbarungen?.trim() ?? '';
    final kunde = p.kunde?.trim() ?? '';
    return _Karte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Idee und Anfrage',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            [
              'seit ${Format.datum(p.createdAt)}',
              if (kunde.isNotEmpty) kunde,
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
          if (idee.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(idee),
          ],
          if (vereinbart.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Vereinbart: $vereinbart',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (eintraege.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in eintraege)
              _EintragZeile(projektId: p.id, eintrag: e),
          ],
        ],
      ),
    );
  }
}

/// Eine Station: Stand, Grund, Änderungen, Kennzahlen, Aktionen und was
/// danach kam.
class _StationKarte extends ConsumerWidget {
  const _StationKarte({
    required this.station,
    required this.version,
    required this.vorherId,
    required this.versionen,
    required this.freigegeben,
  });

  final WegStation station;
  final RezepturVersion? version;

  /// Der vorige Stand derselben Rezeptur — null beim ersten.
  final String? vorherId;
  final Map<String, RezepturVersion> versionen;
  final bool freigegeben;

  Future<void> _vergleichen(BuildContext context, RezepturVersion v) {
    final liste = versionen.values
        .where((x) => x.rezepturId == v.rezepturId)
        .toList()
      ..sort((a, b) => b.nummer.compareTo(a.nummer));
    return showDialog<void>(
      context: context,
      builder: (_) => VersionsVergleichDialog(
        versionen: liste,
        aId: vorherId!,
        bId: v.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final e = station.eintrag;
    final v = version;
    final beschreibung = e.beschreibung?.trim() ?? '';
    final aenderungen = texteAus(e.aenderungen);
    final ergebnis =
        ref.watch(rezepturErgebnisProvider(station.versionId)).valueOrNull;
    final vorher = vorherId;
    final alt = vorher == null
        ? null
        : ref.watch(rezepturErgebnisProvider(vorher)).valueOrNull;
    final kennzahlen =
        ergebnis == null ? null : wegKennzahlen(ergebnis, vorher: alt);
    final rueck = station.rueckmeldungen;
    return _Karte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.titel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (freigegeben)
                const StatusMarke(
                  'freigegeben',
                  art: StatusArt.ok,
                  icon: Icons.verified_outlined,
                ),
            ],
          ),
          Text(
            'Station ${station.nummer} · ${Format.datum(e.datum)}',
            style: theme.textTheme.bodySmall?.copyWith(color: grau),
          ),
          if (beschreibung.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(beschreibung),
          ],
          if (aenderungen.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final a in aenderungen)
              Text(
                '• $a',
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
          ],
          if (kennzahlen != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in kennzahlen) _KennzahlMarke(kennzahl: k),
              ],
            ),
          ],
          if (v != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => etikettZeigen(context, v.id),
                  icon: const Icon(Icons.label_outline, size: 16),
                  label: const Text('Etikett'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      projektRezepturZeigen(context, e.projektId, v.rezepturId),
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: const Text('Rezeptur'),
                ),
                if (vorher != null && versionen.containsKey(vorher))
                  TextButton.icon(
                    onPressed: () => _vergleichen(context, v),
                    icon: const Icon(Icons.compare_arrows, size: 16),
                    label: Text(
                      'Mit Stand ${versionen[vorher]!.nummer} vergleichen',
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 14),
          Text(
            rueck.isEmpty
                ? 'Noch nichts danach — Rückmeldungen ordnest du im Eintrag '
                    '„Zu Stand" zu.'
                : 'Danach',
            style: theme.textTheme.labelMedium?.copyWith(color: grau),
          ),
          for (final r in rueck) _EintragZeile(projektId: e.projektId, eintrag: r),
        ],
      ),
    );
  }
}

/// Eine Kennzahl mit ihrer Veränderung.
class _KennzahlMarke extends StatelessWidget {
  const _KennzahlMarke({required this.kennzahl});

  final WegKennzahl kennzahl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = kennzahl;
    final aenderung = k.aenderung;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppMasse.ecken,
      ),
      child: Text.rich(
        TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '${k.label} ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: k.wert,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (aenderung != null)
              TextSpan(
                text: ' ($aenderung)',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein Eintrag als Zeile: Symbol, Titel, Datum, offen — antippen öffnet
/// ihn.
class _EintragZeile extends StatelessWidget {
  const _EintragZeile({required this.projektId, required this.eintrag});

  final String projektId;
  final ProjektEintrag eintrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = eintrag;
    final art = EintragArt.aus(e.art);
    final offen = EintragStatus.aus(e.status) == EintragStatus.offen;
    return InkWell(
      borderRadius: AppMasse.ecken,
      onTap: () => eintragZeigen(context, projektId: projektId, eintragId: e.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Icon(art.icon, size: 16, color: eintragFarbe(context, art)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.titel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (offen) ...[
              const SizedBox(width: 6),
              const StatusMarke('offen', art: StatusArt.warnung),
            ],
            const SizedBox(width: 8),
            Text(
              Format.datum(e.datum),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Wechsel der Phase: „Validierung begonnen · 12.05.2026" — die
/// Freigabe mit ihrem Stand: „Freigegeben als neuer Artikel 4711 · Stand 3
/// · 21.10.2026".
class _PhasenZeile extends StatelessWidget {
  const _PhasenZeile({required this.phase, this.stand, this.gross = false});

  final WegPhase phase;

  /// Die Nummer des Stands, auf den sich der Wechsel bezieht.
  final int? stand;

  /// Neben einem großen Knoten: mittig zu ihm.
  final bool gross;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = phase.eintrag;
    final n = stand;
    return Padding(
      padding: EdgeInsets.only(top: gross ? 11 : 0),
      child: Text(
        [e.titel, if (n != null) 'Stand $n', Format.datum(e.datum)].join(' · '),
        style: theme.textTheme.labelLarge?.copyWith(
          color: phasenFarbe(context, phase.status),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Ein Stand, der gerade in Arbeit ist.
class _InArbeitZeile extends StatelessWidget {
  const _InArbeitZeile({required this.rezeptur, required this.version});

  final Rezeptur rezeptur;
  final RezepturVersion version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Karte(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In Arbeit: ${rezeptur.name} · Stand ${version.nummer}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'Entwurf — wird zur Station, sobald er abgeschlossen ist.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => switch (rezeptur.projektId) {
              final projektId? =>
                projektRezepturZeigen(context, projektId, rezeptur.id),
              null => oeffneRezeptur(context, rezeptur.id),
            },
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: const Text('Öffnen'),
          ),
        ],
      ),
    );
  }
}

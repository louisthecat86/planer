import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../daten/entwicklung_repository.dart';
import '../projekte/projekt_modell.dart';
import '../projekte/projekt_repository.dart';
import '../spezifikation/spez_angaben.dart';
import 'etikett.dart';

// Das Etikett eines Stands aus der Datenbank: Rechenergebnis des Stands
// (abgeschlossen aus seinem eingefrorenen JSON), Name der Rezeptur und
// die Angaben ihres Projekts.

/// Das Etikett eines Stands — null, wenn es den Stand nicht gibt.
final etikettProvider =
    FutureProvider.autoDispose.family<EtikettInhalt?, String>(
  (ref, versionId) async {
    final versionen = await ref.watch(alleVersionenProvider.future);
    final v = versionen.where((x) => x.id == versionId).firstOrNull;
    if (v == null) return null;
    final ergebnis = await ref.watch(rezepturErgebnisProvider(versionId).future);
    if (ergebnis == null) return null;
    final rezepturen = await ref.watch(alleRezepturenProvider.future);
    final r = rezepturen[v.rezepturId];
    final projektId = r?.projektId;
    final projekt = projektId == null
        ? null
        : await ref.watch(projektProvider(projektId).future);
    final abgeschlossen = v.abgeschlossenAm;
    return etikettAus(
      bezeichnung: r?.name ?? '',
      ergebnis: ergebnis,
      angaben: SpezAngaben.aus(projekt?.spezifikation),
      sensorik: Sensorik.aus(projekt?.sensorik),
      stand: [
        if (r != null) r.name,
        'Stand ${v.nummer}',
        if (v.status == VersionStatus.abgeschlossen && abgeschlossen != null)
          'abgeschlossen am ${Format.datum(abgeschlossen)}'
        else
          'Entwurf',
      ].join(' · '),
    );
  },
);


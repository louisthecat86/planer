import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

// Das Paket per QR-Code aufs Handy: Der Planer zeigt die Bilder im Kreis
// (qr_uebertragung.dart im Format-Paket), die App sammelt sie mit der
// Kamera ein. Kein Netz, keine Datei.

/// Wie die Bilder gezeigt werden.
enum QrTempo {
  schnell('Schnell', 1000, 6),
  sicher('Sicher', 450, 4);

  const QrTempo(this.label, this.bytesJeBild, this.bilderJeSekunde);

  final String label;

  /// Größere Bilder tragen mehr, brauchen aber eine ruhigere Hand.
  final int bytesJeBild;
  final int bilderJeSekunde;
}

/// Zeigt das gepackte Paket ([qrPacken]) als wechselnde QR-Codes, bis
/// der Dialog geschlossen wird. [info] steht darüber — was im Paket ist.
Future<void> qrSendenZeigen(
  BuildContext context, {
  required Uint8List daten,
  required String info,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => QrSendenDialog(daten: daten, info: info),
  );
}

class QrSendenDialog extends StatefulWidget {
  const QrSendenDialog({super.key, required this.daten, required this.info});

  final Uint8List daten;
  final String info;

  @override
  State<QrSendenDialog> createState() => _QrSendenDialogState();
}

class _QrSendenDialogState extends State<QrSendenDialog> {
  static final _zufall = Random();

  QrTempo _tempo = QrTempo.schnell;
  late List<String> _bilder;
  final Map<int, QrImage> _bildCache = {};
  int? _version;
  int _nummer = 0;
  bool _pause = false;
  Timer? _takt;

  @override
  void initState() {
    super.initState();
    _aufteilen();
  }

  @override
  void dispose() {
    _takt?.cancel();
    super.dispose();
  }

  /// Ein neuer Lauf: Die App erkennt daran, dass sie von vorn sammeln muss.
  static String _neuerLauf() {
    const z = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return String.fromCharCodes(
      List.generate(4, (_) => z.codeUnitAt(_zufall.nextInt(z.length))),
    );
  }

  void _aufteilen() {
    _bilder = qrBilderAus(
      widget.daten,
      lauf: _neuerLauf(),
      bytesJeBild: _tempo.bytesJeBild,
    );
    _bildCache.clear();
    // Alle Bilder in derselben Größe — das erste ist das längste.
    _version = _kleinsteVersion(_bilder.first);
    _nummer = 0;
    _takt?.cancel();
    _takt = Timer.periodic(
      Duration(milliseconds: 1000 ~/ _tempo.bilderJeSekunde),
      (_) {
        if (_pause || !mounted) return;
        setState(() => _nummer = (_nummer + 1) % _bilder.length);
      },
    );
  }

  static int _kleinsteVersion(String text) {
    for (var v = 1; v <= 40; v++) {
      try {
        QrImage.withMaskPattern(
          QrCode(v, QrErrorCorrectLevel.L)..addAlphaNumeric(text),
          0,
        );
        return v;
      } on InputTooLongException {
        continue;
      }
    }
    return 40;
  }

  QrImage _bild(int i) => _bildCache[i] ??= QrImage(
        QrCode(_version!, QrErrorCorrectLevel.L)..addAlphaNumeric(_bilder[i]),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grau = theme.colorScheme.onSurfaceVariant;
    final runde = (_bilder.length / _tempo.bilderJeSekunde).ceil();
    final groesse = MediaQuery.sizeOf(context);
    final kante = min(560.0, min(groesse.width - 120, groesse.height - 300))
        .clamp(220.0, 560.0);
    return AlertDialog(
      key: const ValueKey('qr-senden'),
      title: const Text('Per QR-Code aufs Handy'),
      content: SizedBox(
        width: kante,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'In „Planer Erfassung" auf „Per QR-Code empfangen" tippen '
                'und das Handy ruhig auf diesen Code halten. Die App sammelt '
                'die Bilder in jeder Reihenfolge ein und meldet sich, wenn '
                'alles da ist.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                widget.info,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
              const SizedBox(height: 12),
              SizedBox.square(
                dimension: kante,
                child: CustomPaint(
                  key: const ValueKey('qr-bild'),
                  painter: _QrMaler(_bild(_nummer)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Bild ${_nummer + 1} von ${_bilder.length}'
                ' · eine Runde etwa ${_dauer(runde)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: grau),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SegmentedButton<QrTempo>(
                    key: const ValueKey('qr-tempo'),
                    segments: [
                      for (final t in QrTempo.values)
                        ButtonSegment(value: t, label: Text(t.label)),
                    ],
                    selected: {_tempo},
                    onSelectionChanged: (s) => setState(() {
                      _tempo = s.first;
                      _aufteilen();
                    }),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _pause ? 'Weiter' : 'Anhalten',
                    onPressed: () => setState(() => _pause = !_pause),
                    icon: Icon(_pause ? Icons.play_arrow : Icons.pause),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Liest das Handy nichts, auf „Sicher" stellen — kleinere '
                'Codes, dafür mehr davon.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: grau),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('qr-schliessen'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fertig'),
        ),
      ],
    );
  }

  static String _dauer(int sekunden) => sekunden < 60
      ? '$sekunden s'
      : '${sekunden ~/ 60}:${(sekunden % 60).toString().padLeft(2, '0')} min';
}

/// Malt einen QR-Code schwarz auf weiß mit dem vorgeschriebenen Rand von
/// vier Modulen — auch im dunklen Design, sonst liest ihn keine Kamera.
class _QrMaler extends CustomPainter {
  _QrMaler(this.bild);

  final QrImage bild;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final n = bild.moduleCount;
    // Ganze Pixel je Modul, damit alle Module gleich breit sind.
    final modul = max(1, (size.shortestSide / (n + 8)).floor()).toDouble();
    final rand = (size.shortestSide - n * modul) / 2;
    final schwarz = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    final pfad = Path();
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (bild.isDark(r, c)) {
          pfad.addRect(
            Rect.fromLTWH(rand + c * modul, rand + r * modul, modul, modul),
          );
        }
      }
    }
    canvas.drawPath(pfad, schwarz);
  }

  @override
  bool shouldRepaint(_QrMaler alt) => !identical(alt.bild, bild);
}

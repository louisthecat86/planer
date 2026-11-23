import 'package:erfassung_format/erfassung_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'stil.dart';

/// Öffnet die Kamera und sammelt die QR-Codes ein, die der Planer zeigt
/// (Einstellungen → Handy-Erfassung → „Per QR-Code aufs Handy").
/// Liefert, wenn alle da sind, wie das Paket zu lesen ist — null, wenn
/// abgebrochen.
Future<ErfassungsPaket Function()?> qrEmpfangen(BuildContext context) =>
    Navigator.of(context).push<ErfassungsPaket Function()>(
      MaterialPageRoute(builder: (_) => const QrEmpfangSeite()),
    );

class QrEmpfangSeite extends StatefulWidget {
  const QrEmpfangSeite({super.key});

  @override
  State<QrEmpfangSeite> createState() => _QrEmpfangSeiteState();
}

class _QrEmpfangSeiteState extends State<QrEmpfangSeite> {
  // Jedes Kamerabild auswerten — der Planer wechselt mehrmals in der
  // Sekunde. Höhere Auflösung, damit auch dichte Codes aus etwas Abstand
  // lesbar sind.
  final _kamera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
    cameraResolution: const Size(1920, 1080),
  );
  final _sammler = QrSammler();
  bool _fertig = false;

  @override
  void dispose() {
    _kamera.dispose();
    super.dispose();
  }

  void _erkannt(BarcodeCapture fang) {
    if (_fertig) return;
    var neu = false;
    for (final code in fang.barcodes) {
      final text = code.rawValue;
      if (text != null && _sammler.aufnehmen(text)) neu = true;
    }
    if (!neu) return;
    if (_sammler.fertig) {
      _fertig = true;
      HapticFeedback.mediumImpact();
      _kamera.stop();
      Navigator.of(context).pop<ErfassungsPaket Function()>(_sammler.paket);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anzahl = _sammler.anzahl;
    final da = _sammler.vorhanden;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Per QR-Code empfangen'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            key: const ValueKey('qr-kamera'),
            controller: _kamera,
            onDetect: _erkannt,
            errorBuilder: (context, fehler) => _KameraFehler(fehler),
          ),
          // Ein Rahmen zum Anvisieren.
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.78,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70, width: 3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: Masse.ecken,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        anzahl == 0
                            ? 'Kamera auf den QR-Code im Planer halten'
                            : '$da von $anzahl Bildern',
                        key: const ValueKey('qr-stand'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: anzahl == 0 ? null : da / anzahl,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        anzahl == 0
                            ? 'Im Planer: Einstellungen → Handy-Erfassung → '
                                '„Per QR-Code aufs Handy".'
                            : 'Ruhig halten — verpasste Bilder kommen in der '
                                'nächsten Runde wieder.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KameraFehler extends StatelessWidget {
  const _KameraFehler(this.fehler);

  final MobileScannerException fehler;

  @override
  Widget build(BuildContext context) {
    final text = switch (fehler.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Die App darf die Kamera nicht nutzen. In den Einstellungen des '
            'Handys unter Apps → Planer Erfassung → Berechtigungen die '
            'Kamera erlauben.',
      MobileScannerErrorCode.unsupported =>
        'Dieses Handy kann keine QR-Codes lesen.',
      _ => 'Die Kamera ließ sich nicht starten: ${fehler.errorCode.message}',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

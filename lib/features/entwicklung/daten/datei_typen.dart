import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';

// Was eine Datei ist — nach ihrer Endung — und wie groß, zum Lesen.

/// „12 KB", „3,4 MB".
String groesseText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${Format.zahl(bytes / 1024)} KB';
  return '${Format.zahl(bytes / (1024 * 1024), nachkomma: 1)} MB';
}

/// Der Medientyp nach der Endung — null, wenn sie unbekannt ist.
String? mimeTypAus(String name) {
  switch (p.extension(name).toLowerCase()) {
    case '.pdf':
      return 'application/pdf';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.txt':
      return 'text/plain';
    case '.csv':
      return 'text/csv';
    case '.msg':
      return 'application/vnd.ms-outlook';
    case '.eml':
      return 'message/rfc822';
    case '.xlsx':
      return 'application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.sheet';
    case '.xls':
      return 'application/vnd.ms-excel';
    case '.docx':
      return 'application/vnd.openxmlformats-officedocument.'
          'wordprocessingml.document';
    case '.doc':
      return 'application/msword';
  }
  return null;
}

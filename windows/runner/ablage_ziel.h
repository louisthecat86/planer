#ifndef RUNNER_ABLAGE_ZIEL_H_
#define RUNNER_ABLAGE_ZIEL_H_

#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

// Nimmt Dateien und Mails an, die auf das Fenster gezogen werden: aus dem
// Explorer als Dateien, aus Outlook als "virtuelle Dateien" (Mails und
// Anhaenge, die noch nirgends als Datei liegen). Virtuelle Dateien schreibt
// es in einen eigenen Ordner unter %TEMP%; die App liest sie und raeumt sie
// weg. Ueber den Kanal "planer/ablage" meldet es der App:
//
//   "ueber"     {x, y}                    gezogen ueber dem Punkt (x, y);
//                                         die App antwortet, ob dort etwas
//                                         abgelegt werden kann
//   "weg"                                 nicht mehr ueber dem Fenster
//   "abgelegt"  {x, y, pfade, virtuell}   losgelassen
//
// x und y sind Pixel im Fenster der App. Eine Mail aus Outlook wird nur
// kopiert, nie verschoben.
class AblageZiel final : public IDropTarget {
 public:
  // Meldet das Ziel fuer |fenster| an. Null, wenn es nicht geht.
  static AblageZiel* Anmelden(HWND fenster,
                              flutter::BinaryMessenger* messenger);

  // Meldet das Ziel ab und gibt es frei.
  void Abmelden();

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** objekt) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IDropTarget
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* daten,
                                      DWORD tasten,
                                      POINTL punkt,
                                      DWORD* wirkung) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD tasten,
                                     POINTL punkt,
                                     DWORD* wirkung) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* daten,
                                 DWORD tasten,
                                 POINTL punkt,
                                 DWORD* wirkung) override;

 private:
  // Was die Antworten der App betrifft - sie kommen spaeter und duerfen
  // das Ziel ueberleben. Die gemeldeten Punkte sind durchgezaehlt.
  struct Zustand {
    // Der zuletzt gemeldete Punkt ...
    int gemeldet = 0;
    // ... der zuletzt beantwortete ...
    int beantwortet = 0;
    // ... und ob die App dort etwas annimmt.
    bool annehmen = false;

    // Die Antwort zum Punkt |nummer| - eine aeltere zaehlt nicht mehr.
    void Antwort(int nummer, bool ja) {
      if (nummer >= beantwortet) {
        beantwortet = nummer;
        annehmen = ja;
      }
    }
  };

  AblageZiel(HWND fenster, flutter::BinaryMessenger* messenger);
  ~AblageZiel();

  // Die Wirkung fuer die Quelle: kopieren, wenn die App hier etwas
  // annimmt - sonst nichts.
  DWORD Wirkung(DWORD erlaubt) const;

  // Meldet der App den Punkt, wenn er sich geaendert hat.
  void Melden(POINTL punkt);

  // Die Dateien aus dem Explorer.
  std::vector<std::wstring> Dateien(IDataObject* daten) const;

  // Die virtuellen Dateien, geschrieben in einen neuen Ordner.
  std::vector<std::wstring> VirtuelleDateien(IDataObject* daten) const;

  // Schreibt die virtuelle Datei |index| nach |pfad|.
  bool Schreiben(IDataObject* daten,
                 LONG index,
                 const FILEDESCRIPTORW& beschreibung,
                 const std::wstring& pfad) const;

  LONG zaehler_ = 1;
  HWND fenster_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> kanal_;
  std::shared_ptr<Zustand> zustand_;
  CLIPFORMAT format_beschreibung_;
  CLIPFORMAT format_inhalt_;
  IDropTargetHelper* bild_ = nullptr;
  bool hat_dateien_ = false;
  bool gemeldet_ = false;
  POINT letzter_ = {0, 0};
};

#endif  // RUNNER_ABLAGE_ZIEL_H_

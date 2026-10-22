#include "ablage_ziel.h"

#include <shellapi.h>

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <utility>

namespace {

// Text als UTF-8 - so erwartet ihn die App.
std::string Utf8(const std::wstring& text) {
  if (text.empty()) {
    return std::string();
  }
  const int eingabe = static_cast<int>(text.size());
  const int laenge = WideCharToMultiByte(CP_UTF8, 0, text.data(), eingabe,
                                         nullptr, 0, nullptr, nullptr);
  if (laenge <= 0) {
    return std::string();
  }
  std::string ergebnis(static_cast<size_t>(laenge), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), eingabe, ergebnis.data(),
                      laenge, nullptr, nullptr);
  return ergebnis;
}

// Ob |daten| das Format |format| anbietet.
bool HatFormat(IDataObject* daten, CLIPFORMAT format) {
  FORMATETC f = {format, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  return daten->QueryGetData(&f) == S_OK;
}

// Ein Dateiname, den jedes Dateisystem annimmt - hoechstens 120 Zeichen,
// die Endung bleibt.
std::wstring Sauber(const wchar_t* name) {
  std::wstring ergebnis(name);
  const std::wstring verboten = L"<>:\"/\\|?*";
  for (auto& zeichen : ergebnis) {
    if (zeichen < 32 || verboten.find(zeichen) != std::wstring::npos) {
      zeichen = L'_';
    }
  }
  while (!ergebnis.empty() &&
         (ergebnis.back() == L'.' || ergebnis.back() == L' ')) {
    ergebnis.pop_back();
  }
  if (ergebnis.empty()) {
    ergebnis = L"Datei";
  }
  const size_t hoechstens = 120;
  if (ergebnis.size() > hoechstens) {
    const size_t punkt = ergebnis.find_last_of(L'.');
    const std::wstring endung =
        punkt != std::wstring::npos && ergebnis.size() - punkt <= 10
            ? ergebnis.substr(punkt)
            : std::wstring();
    ergebnis = ergebnis.substr(0, hoechstens - endung.size()) + endung;
  }
  return ergebnis;
}

// Ein Pfad in |ordner|, den es noch nicht gibt: "Name.msg",
// "Name (2).msg", ...
std::wstring FreierPfad(const std::wstring& ordner, const std::wstring& name) {
  std::wstring pfad = ordner + L"\\" + name;
  if (GetFileAttributesW(pfad.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return pfad;
  }
  const size_t punkt = name.find_last_of(L'.');
  const std::wstring stamm =
      punkt == std::wstring::npos ? name : name.substr(0, punkt);
  const std::wstring endung =
      punkt == std::wstring::npos ? std::wstring() : name.substr(punkt);
  for (int nummer = 2; nummer < 1000; ++nummer) {
    pfad = ordner + L"\\" + stamm + L" (" + std::to_wstring(nummer) + L")" +
           endung;
    if (GetFileAttributesW(pfad.c_str()) == INVALID_FILE_ATTRIBUTES) {
      return pfad;
    }
  }
  return pfad;
}

// Ein neuer, leerer Ordner unter %TEMP%\planer_ablage - leer, wenn es
// nicht geht.
std::wstring NeuerOrdner() {
  wchar_t temp[MAX_PATH + 1] = {};
  const DWORD laenge = GetTempPathW(MAX_PATH + 1, temp);
  if (laenge == 0 || laenge > MAX_PATH) {
    return std::wstring();
  }
  const std::wstring basis = std::wstring(temp, laenge) + L"planer_ablage";
  CreateDirectoryW(basis.c_str(), nullptr);
  for (int versuch = 0; versuch < 100; ++versuch) {
    const std::wstring ordner =
        basis + L"\\" + std::to_wstring(GetTickCount64()) + L"_" +
        std::to_wstring(versuch);
    if (CreateDirectoryW(ordner.c_str(), nullptr)) {
      return ordner;
    }
  }
  return std::wstring();
}

// Eine Mail aus Outlook: ein Speicher (Verbunddatei) - als .msg-Datei.
bool SpeicherSchreiben(IStorage* quelle, const std::wstring& pfad) {
  IStorage* ziel = nullptr;
  if (FAILED(StgCreateDocfile(
          pfad.c_str(), STGM_CREATE | STGM_READWRITE | STGM_SHARE_EXCLUSIVE,
          0, &ziel))) {
    return false;
  }
  const HRESULT kopiert = quelle->CopyTo(0, nullptr, nullptr, ziel);
  const HRESULT fertig = ziel->Commit(STGC_DEFAULT);
  ziel->Release();
  return SUCCEEDED(kopiert) && SUCCEEDED(fertig);
}

// Ein Strom - etwa ein Anhang aus Outlook.
bool StromSchreiben(IStream* quelle, const std::wstring& pfad) {
  LARGE_INTEGER anfang = {};
  quelle->Seek(anfang, STREAM_SEEK_SET, nullptr);
  HANDLE datei = CreateFileW(pfad.c_str(), GENERIC_WRITE, 0, nullptr,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (datei == INVALID_HANDLE_VALUE) {
    return false;
  }
  std::vector<BYTE> puffer(64 * 1024);
  bool gut = true;
  for (;;) {
    ULONG gelesen = 0;
    const HRESULT hr = quelle->Read(
        puffer.data(), static_cast<ULONG>(puffer.size()), &gelesen);
    if (FAILED(hr)) {
      gut = false;
      break;
    }
    if (gelesen == 0) {
      break;
    }
    DWORD geschrieben = 0;
    if (!WriteFile(datei, puffer.data(), gelesen, &geschrieben, nullptr) ||
        geschrieben != gelesen) {
      gut = false;
      break;
    }
    if (hr == S_FALSE) {
      break;
    }
  }
  CloseHandle(datei);
  return gut;
}

// Ein Speicherblock - so viel davon, wie die Beschreibung angibt.
bool BlockSchreiben(HGLOBAL block,
                    const FILEDESCRIPTORW& beschreibung,
                    const std::wstring& pfad) {
  SIZE_T groesse = GlobalSize(block);
  if ((beschreibung.dwFlags & FD_FILESIZE) != 0) {
    const ULONGLONG angegeben =
        (static_cast<ULONGLONG>(beschreibung.nFileSizeHigh) << 32) |
        beschreibung.nFileSizeLow;
    if (angegeben < groesse) {
      groesse = static_cast<SIZE_T>(angegeben);
    }
  }
  const void* inhalt = GlobalLock(block);
  if (inhalt == nullptr) {
    return false;
  }
  bool gut = false;
  HANDLE datei = CreateFileW(pfad.c_str(), GENERIC_WRITE, 0, nullptr,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (datei != INVALID_HANDLE_VALUE) {
    DWORD geschrieben = 0;
    const DWORD menge = static_cast<DWORD>(groesse);
    gut = WriteFile(datei, inhalt, menge, &geschrieben, nullptr) != FALSE &&
          geschrieben == menge;
    CloseHandle(datei);
  }
  GlobalUnlock(block);
  return gut;
}

}  // namespace

AblageZiel* AblageZiel::Anmelden(HWND fenster,
                                 flutter::BinaryMessenger* messenger) {
  if (fenster == nullptr || messenger == nullptr) {
    return nullptr;
  }
  if (FAILED(OleInitialize(nullptr))) {
    return nullptr;
  }
  AblageZiel* ziel = new AblageZiel(fenster, messenger);
  if (FAILED(RegisterDragDrop(fenster, ziel))) {
    ziel->Release();
    OleUninitialize();
    return nullptr;
  }
  return ziel;
}

void AblageZiel::Abmelden() {
  RevokeDragDrop(fenster_);
  kanal_.reset();
  if (bild_ != nullptr) {
    bild_->Release();
    bild_ = nullptr;
  }
  Release();
  OleUninitialize();
}

AblageZiel::AblageZiel(HWND fenster, flutter::BinaryMessenger* messenger)
    : fenster_(fenster),
      kanal_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger,
          "planer/ablage",
          &flutter::StandardMethodCodec::GetInstance())),
      zustand_(std::make_shared<Zustand>()),
      format_beschreibung_(static_cast<CLIPFORMAT>(
          RegisterClipboardFormatW(CFSTR_FILEDESCRIPTORW))),
      format_inhalt_(static_cast<CLIPFORMAT>(
          RegisterClipboardFormatW(CFSTR_FILECONTENTS))) {
  // Das Bild, das beim Ziehen mitkommt - etwa die Mail aus Outlook.
  if (FAILED(CoCreateInstance(CLSID_DragDropHelper, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&bild_)))) {
    bild_ = nullptr;
  }
}

AblageZiel::~AblageZiel() {
  if (bild_ != nullptr) {
    bild_->Release();
  }
}

HRESULT AblageZiel::QueryInterface(REFIID riid, void** objekt) {
  if (objekt == nullptr) {
    return E_POINTER;
  }
  if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IDropTarget)) {
    *objekt = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  *objekt = nullptr;
  return E_NOINTERFACE;
}

ULONG AblageZiel::AddRef() {
  return static_cast<ULONG>(InterlockedIncrement(&zaehler_));
}

ULONG AblageZiel::Release() {
  const LONG rest = InterlockedDecrement(&zaehler_);
  if (rest == 0) {
    delete this;
  }
  return static_cast<ULONG>(rest);
}

DWORD AblageZiel::Wirkung(DWORD erlaubt) const {
  if (!hat_dateien_ || !zustand_->annehmen) {
    return DROPEFFECT_NONE;
  }
  // Nie verschieben: Outlook wuerde die Mail sonst loeschen.
  if ((erlaubt & DROPEFFECT_COPY) == 0) {
    return DROPEFFECT_NONE;
  }
  return DROPEFFECT_COPY;
}

void AblageZiel::Melden(POINTL punkt) {
  if (!kanal_ || !hat_dateien_) {
    return;
  }
  POINT p = {punkt.x, punkt.y};
  ScreenToClient(fenster_, &p);
  if (gemeldet_ && p.x == letzter_.x && p.y == letzter_.y) {
    return;
  }
  gemeldet_ = true;
  letzter_ = p;
  const int nummer = ++zustand_->gemeldet;
  std::shared_ptr<Zustand> zustand = zustand_;
  auto antwort =
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [zustand, nummer](const flutter::EncodableValue* ergebnis) {
            const bool* ja =
                ergebnis == nullptr ? nullptr : std::get_if<bool>(ergebnis);
            zustand->Antwort(nummer, ja != nullptr && *ja);
          },
          [zustand, nummer](const std::string& code,
                            const std::string& meldung,
                            const flutter::EncodableValue* details) {
            zustand->Antwort(nummer, false);
          },
          [zustand, nummer]() {
            // Die App hoert (noch) nicht zu.
            zustand->Antwort(nummer, false);
          });
  kanal_->InvokeMethod(
      "ueber",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
          {flutter::EncodableValue("x"),
           flutter::EncodableValue(static_cast<double>(p.x))},
          {flutter::EncodableValue("y"),
           flutter::EncodableValue(static_cast<double>(p.y))},
      }),
      std::move(antwort));
}

HRESULT AblageZiel::DragEnter(IDataObject* daten,
                              DWORD tasten,
                              POINTL punkt,
                              DWORD* wirkung) {
  if (wirkung == nullptr) {
    return E_INVALIDARG;
  }
  hat_dateien_ =
      daten != nullptr &&
      (HatFormat(daten, static_cast<CLIPFORMAT>(CF_HDROP)) ||
       HatFormat(daten, format_beschreibung_));
  zustand_->annehmen = false;
  gemeldet_ = false;
  *wirkung = Wirkung(*wirkung);
  if (bild_ != nullptr) {
    POINT p = {punkt.x, punkt.y};
    bild_->DragEnter(fenster_, daten, &p, *wirkung);
  }
  Melden(punkt);
  return S_OK;
}

HRESULT AblageZiel::DragOver(DWORD tasten, POINTL punkt, DWORD* wirkung) {
  if (wirkung == nullptr) {
    return E_INVALIDARG;
  }
  *wirkung = Wirkung(*wirkung);
  if (bild_ != nullptr) {
    POINT p = {punkt.x, punkt.y};
    bild_->DragOver(&p, *wirkung);
  }
  Melden(punkt);
  return S_OK;
}

HRESULT AblageZiel::DragLeave() {
  if (bild_ != nullptr) {
    bild_->DragLeave();
  }
  hat_dateien_ = false;
  gemeldet_ = false;
  zustand_->annehmen = false;
  if (kanal_) {
    kanal_->InvokeMethod("weg", nullptr);
  }
  return S_OK;
}

HRESULT AblageZiel::Drop(IDataObject* daten,
                         DWORD tasten,
                         POINTL punkt,
                         DWORD* wirkung) {
  if (wirkung == nullptr) {
    return E_INVALIDARG;
  }
  POINT p = {punkt.x, punkt.y};
  ScreenToClient(fenster_, &p);
  // Hat die App zu genau diesem Punkt schon gesagt, dass sie hier nichts
  // annimmt, entstehen gar nicht erst Kopien. Fehlt ihre Antwort noch,
  // entscheidet sie nach dem Ablegen.
  const bool abgelehnt = gemeldet_ && p.x == letzter_.x &&
                         p.y == letzter_.y &&
                         zustand_->beantwortet == zustand_->gemeldet &&
                         !zustand_->annehmen;
  const bool annehmen =
      hat_dateien_ && daten != nullptr && kanal_ && !abgelehnt;
  hat_dateien_ = false;
  gemeldet_ = false;
  zustand_->annehmen = false;
  if (annehmen && (*wirkung & DROPEFFECT_COPY) != 0) {
    *wirkung = DROPEFFECT_COPY;
  } else {
    *wirkung = DROPEFFECT_NONE;
  }
  if (bild_ != nullptr) {
    POINT bildschirm = {punkt.x, punkt.y};
    bild_->Drop(daten, &bildschirm, *wirkung);
  }
  if (!annehmen) {
    // Zeigt die App noch etwas an, verschwindet es.
    if (kanal_) {
      kanal_->InvokeMethod("weg", nullptr);
    }
    return S_OK;
  }
  bool virtuell = false;
  std::vector<std::wstring> pfade = Dateien(daten);
  if (pfade.empty()) {
    pfade = VirtuelleDateien(daten);
    virtuell = !pfade.empty();
  }
  flutter::EncodableList liste;
  for (const auto& pfad : pfade) {
    liste.emplace_back(Utf8(pfad));
  }
  kanal_->InvokeMethod(
      "abgelegt",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
          {flutter::EncodableValue("x"),
           flutter::EncodableValue(static_cast<double>(p.x))},
          {flutter::EncodableValue("y"),
           flutter::EncodableValue(static_cast<double>(p.y))},
          {flutter::EncodableValue("pfade"), flutter::EncodableValue(liste)},
          {flutter::EncodableValue("virtuell"),
           flutter::EncodableValue(virtuell)},
      }));
  return S_OK;
}

std::vector<std::wstring> AblageZiel::Dateien(IDataObject* daten) const {
  std::vector<std::wstring> pfade;
  FORMATETC format = {static_cast<CLIPFORMAT>(CF_HDROP), nullptr,
                      DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (FAILED(daten->GetData(&format, &medium))) {
    return pfade;
  }
  // Der Block selbst ist die Liste - DragQueryFileW sperrt ihn selbst.
  HDROP drop = static_cast<HDROP>(medium.hGlobal);
  const UINT anzahl = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < anzahl; ++i) {
    const UINT laenge = DragQueryFileW(drop, i, nullptr, 0);
    std::wstring pfad(static_cast<size_t>(laenge) + 1, L'\0');
    DragQueryFileW(drop, i, pfad.data(), laenge + 1);
    pfad.resize(laenge);
    if (!pfad.empty()) {
      pfade.push_back(pfad);
    }
  }
  ReleaseStgMedium(&medium);
  return pfade;
}

std::vector<std::wstring> AblageZiel::VirtuelleDateien(
    IDataObject* daten) const {
  std::vector<std::wstring> pfade;
  FORMATETC format = {format_beschreibung_, nullptr, DVASPECT_CONTENT, -1,
                      TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (FAILED(daten->GetData(&format, &medium))) {
    return pfade;
  }
  const auto* gruppe =
      static_cast<const FILEGROUPDESCRIPTORW*>(GlobalLock(medium.hGlobal));
  if (gruppe != nullptr) {
    const std::wstring ordner = NeuerOrdner();
    for (UINT i = 0; !ordner.empty() && i < gruppe->cItems; ++i) {
      const FILEDESCRIPTORW& beschreibung = gruppe->fgd[i];
      if ((beschreibung.dwFlags & FD_ATTRIBUTES) != 0 &&
          (beschreibung.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        continue;
      }
      const std::wstring pfad =
          FreierPfad(ordner, Sauber(beschreibung.cFileName));
      if (Schreiben(daten, static_cast<LONG>(i), beschreibung, pfad)) {
        pfade.push_back(pfad);
      }
    }
    GlobalUnlock(medium.hGlobal);
  }
  ReleaseStgMedium(&medium);
  return pfade;
}

bool AblageZiel::Schreiben(IDataObject* daten,
                           LONG index,
                           const FILEDESCRIPTORW& beschreibung,
                           const std::wstring& pfad) const {
  FORMATETC format = {format_inhalt_, nullptr, DVASPECT_CONTENT, index,
                      TYMED_ISTORAGE | TYMED_ISTREAM | TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  if (FAILED(daten->GetData(&format, &medium))) {
    return false;
  }
  bool geschrieben = false;
  if (medium.tymed == static_cast<DWORD>(TYMED_ISTORAGE)) {
    geschrieben = SpeicherSchreiben(medium.pstg, pfad);
  } else if (medium.tymed == static_cast<DWORD>(TYMED_ISTREAM)) {
    geschrieben = StromSchreiben(medium.pstm, pfad);
  } else if (medium.tymed == static_cast<DWORD>(TYMED_HGLOBAL)) {
    geschrieben = BlockSchreiben(medium.hGlobal, beschreibung, pfad);
  }
  ReleaseStgMedium(&medium);
  if (!geschrieben) {
    DeleteFileW(pfad.c_str());
  }
  return geschrieben;
}

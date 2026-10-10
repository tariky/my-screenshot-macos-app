# Screenshot app — dizajn

Datum: 2026-10-10

## Cilj

Super jednostavan macOS screenshot alat: ⌘⇧2 → označi dio ekrana → slika je odmah u clipboardu.
Mini thumbnail dolje lijevo 5 s nudi brzi edit (strelice); svaki edit odmah ažurira clipboard,
a iz editora se slika može snimiti na disk.

## Zahtjevi

1. Globalna prečica **⌘⇧2** pokreće selektor područja.
2. Nakon selekcije PNG slika odmah ide u clipboard.
3. Thumbnail se pojavi dolje lijevo s odbrojavanjem od **5 s**.
   - Bez klika: thumbnail nestane, slika ostaje u clipboardu.
   - Klik: otvara se editor.
4. Editor: klik + povlačenje crta strelicu (početak = mjesto pritiska, vrh = mjesto puštanja).
   Nakon svake promjene (nova strelica, undo) kompozitna slika se odmah upisuje u clipboard.
5. Editor nudi snimanje na disk (⌘S / dugme *Save*).
6. Esc u selektoru = ništa se ne dešava, clipboard ostaje netaknut.

## Tehnologija

- **Swift 5.10 + AppKit**, Swift Package Manager, bez Xcode projekta (dostupni su samo Command Line Tools).
- Build skripta `build-app.sh` pakuje izvršni fajl u `Screenshot.app` (`Info.plist` sa `LSUIElement = true`, ad-hoc `codesign`).
- Minimalna verzija: macOS 13.
- Selektor: sistemski `/usr/sbin/screencapture -i -x <tmp>.png` (nativni crosshair, Esc, Space za prozor, Retina, više monitora).
- Dozvola: prvo pokretanje traži *Screen Recording*. *Accessibility* nije potreban (Carbon hotkey).

## Struktura paketa

```
Package.swift
Sources/
  ScreenshotCore/      # čista logika, bez UI — testabilno
    ArrowRenderer.swift
    Arrow.swift
    Geometry.swift
    Countdown.swift
  Screenshot/          # AppKit app (executable)
    main.swift
    AppController.swift
    HotKey.swift
    Capturer.swift
    Clipboard.swift
    ThumbnailPanel.swift
    EditorWindow.swift
    CanvasView.swift
  CoreChecks/          # izvršni testovi za ScreenshotCore (swift run CoreChecks)
    main.swift
build-app.sh
```

## Komponente

| Modul | Odgovornost | Interfejs (okvirno) |
|---|---|---|
| `HotKey` | Registruje ⌘⇧2 preko Carbon `RegisterEventHotKey`, poziva callback. | `HotKey(keyCode:modifiers:handler:)` |
| `Capturer` | Pokreće `screencapture -i -x` u temp fajl (async, van main threada), čita sliku, briše fajl. `nil` ako je otkazano (fajl ne postoji / prazan). | `capture() async -> CGImage?` |
| `Clipboard` | Briše pasteboard i upisuje PNG. | `Clipboard.write(_ image: CGImage)` |
| `Arrow` | Vrijednosni tip: `start`, `end` u pikselima slike. | `struct Arrow { var start, end: CGPoint }` |
| `ArrowRenderer` | Crta original + strelice u novu `CGImage` iste pikselne veličine. Strelica: crvena `#FF3B30`, debljina `max(3, 0.005 × min(w,h))` px, ispunjen trouglasti vrh, blaga tamna sjenka. Takođe PNG enkodiranje. | `render(base: CGImage, arrows: [Arrow]) -> CGImage`, `pngData(_:) -> Data` |
| `Geometry` | Konverzija tačaka view ↔ piksel slike (aspect-fit skaliranje); prag "premala strelica" (< 5 pt). | `ImageFit(imageSize:viewSize)`, `toImage(_:)`, `toView(_:)` |
| `Countdown` | Logika tajmera bez UI: trajanje 5 s, `pause()`, `resume()`, `remaining(at:)`, `isExpired(at:)`. Vrijeme se ubrizgava (testabilno). | `struct Countdown` |
| `ThumbnailPanel` | Nonactivating `NSPanel`, floating, ~200 pt širok (proporcionalno), dolje lijevo 16 pt od ivice ekrana na kojem je miš; zaobljeni uglovi, sjenka, traka napretka. Hover pauzira `Countdown`. Klik → callback `onOpen`; istek → fade-out → `onExpire`. | `show(image:onOpen:onExpire:)`, `dismiss()` |
| `EditorWindow` | Prozor sa toolbarom (*Undo*, *Save*, *Done*) i `CanvasView`. Drži `[Arrow]`; nakon svake promjene renderuje i piše u clipboard. ⌘Z undo, ⌘S `NSSavePanel` (Desktop, `Screenshot YYYY-MM-DD at HH.mm.ss.png`), Esc/⌘W/Done zatvara. Slika veća od ekrana se smanji (aspect-fit), strelice ostaju u punoj rezoluciji. | `EditorWindow(image:)` |
| `CanvasView` | `NSView`: crta sliku + strelice (+ strelicu u toku povlačenja uživo); mouseDown/Dragged/Up → `Arrow` u pikselima slike preko `Geometry`; ignoriše povlačenje < 5 pt. | callback `onArrowAdded(Arrow)` |
| `AppController` | Status bar item (menu: *Take Screenshot ⌘⇧2*, *Quit*). Orkestrira: hotkey → `Capturer` → `Clipboard` → `ThumbnailPanel` → (klik) `EditorWindow`. | — |

## Tok podataka

```
⌘⇧2 ─▶ Capturer.capture()
          ├─ nil (Esc) ─▶ kraj
          └─ image ─▶ Clipboard.write(image)
                      ─▶ ThumbnailPanel.show(image)
                           ├─ istek 5 s ─▶ dismiss (clipboard ostaje)
                           └─ klik ─▶ EditorWindow(image)
                                       └─ svaka promjena ─▶ ArrowRenderer.render ─▶ Clipboard.write
                                       └─ ⌘S ─▶ NSSavePanel ─▶ PNG na disk
```

## Rubni slučajevi i greške

- **Novi screenshot dok je thumbnail vidljiv:** stari thumbnail se odmah uklanja, novi ga zamjenjuje.
- **Ponovni ⌘⇧2 dok je selektor aktivan:** ignoriše se (flag `isCapturing`).
- **Otvoren editor + novi screenshot:** editor ostaje otvoren (nezavisan); clipboard dobija novi screenshot.
- **Nema Screen Recording dozvole:** `screencapture` vraća samo pozadinu / prazno — pri prvom pokretanju app poziva `CGRequestScreenCaptureAccess()`; ako `CGPreflightScreenCaptureAccess()` vrati false, menu prikazuje stavku *Grant Screen Recording…* koja otvara System Settings.
- **Hotkey zauzet** (`RegisterEventHotKey` ≠ `noErr`): `NSAlert` jednom pri startu; menu stavka i dalje radi.
- **Greška pri snimanju na disk:** `NSAlert` s porukom greške.
- **Undo bez strelica:** no-op (dugme onemogućeno).

## Van opsega (YAGNI)

Tekst, pravougaonici, izbor boje/debljine, pomjeranje/brisanje pojedinačnih strelica, istorija screenshota,
podešavanja prečice, launch at login, automatsko snimanje na disk.

## Testiranje

XCTest nije dostupan (samo Command Line Tools) → `CoreChecks` izvršna meta s malim assert helperom,
pokreće se `swift run CoreChecks`, exit code ≠ 0 pri grešci. Pokriva `ScreenshotCore`:

- `ArrowRenderer`: izlaz ima iste pikselne dimenzije kao ulaz; bez strelica slika je identična; sa strelicom
  piksel na sredini linije je crven, piksel daleko od strelice nepromijenjen; PNG data počinje PNG potpisom.
- `Geometry`: aspect-fit konverzija tamo-nazad (round-trip), skaliranje pri slici većoj od viewa, prag 5 pt.
- `Countdown`: istek nakon 5 s; pauza zaustavlja odbrojavanje; resume nastavlja od preostalog vremena.

Ručna provjera (AppKit dio):
1. ⌘⇧2 → Esc → clipboard nepromijenjen, nema thumbnaila.
2. ⌘⇧2 → selekcija → paste u Notes radi; thumbnail nestane nakon 5 s; hover pauzira.
3. Klik na thumbnail → nacrtaj 2 strelice → paste pokazuje obje; ⌘Z → paste pokazuje jednu.
4. ⌘S → fajl na Desktopu, otvara se u Preview sa strelicama.
5. Retina + eksterni monitor: strelice oštre i na pravom mjestu.

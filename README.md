# DiskAnalyzer

Eine native macOS-App, die zeigt, **was auf deinem Mac Speicherplatz belegt**. Sie scannt einen Ordner oder Datenträger und stellt das Ergebnis als interaktives Kreisdiagramm (Sunburst) und als sortierbare Listen dar. Außerdem findet sie Duplikate, schlägt bekannte Platzfresser zum Aufräumen vor und löscht Dateien direkt aus der App.

Die App ist in SwiftUI geschrieben, hat keine Abhängigkeiten und läuft komplett lokal. Es werden keine Daten übertragen.

## Inhalt

- [Funktionen](#funktionen)
- [Installation](#installation)
- [Bedienungsanleitung](#bedienungsanleitung)
  - [1. Einen Scan starten](#1-einen-scan-starten)
  - [2. Das Fenster im Überblick](#2-das-fenster-im-überblick)
  - [3. Das Diagramm](#3-das-diagramm)
  - [4. Navigation](#4-navigation)
  - [5. Die fünf Ansichten](#5-die-fünf-ansichten)
  - [6. Dateien auswählen und löschen](#6-dateien-auswählen-und-löschen)
  - [7. Tastenkürzel](#7-tastenkürzel)
- [Zugriffsrechte (Festplattenvollzugriff)](#zugriffsrechte-festplattenvollzugriff)
- [Wie die App rechnet](#wie-die-app-rechnet)
- [Kommandozeile](#kommandozeile)
- [Aus dem Quellcode bauen](#aus-dem-quellcode-bauen)
- [Projektstruktur](#projektstruktur)
- [Häufige Fragen](#häufige-fragen)

## Funktionen

- **Sunburst-Diagramm** mit bis zu fünf Ebenen. Ein Klick auf einen Ordner springt hinein, ein Klick auf die Mitte führt eine Ebene hoch.
- **Fünf Ansichten:** Baum, Dateien, Typen, Duplikate und Aufräumen.
- **Schnelle Suche und Filter** nach Dateiname, Dateityp und Alter.
- **Duplikat-Suche** über den Inhalt (SHA-256). Hardlinks zählen dabei nicht als Duplikat.
- **Aufräum-Vorschläge** für Caches, Xcode-Daten, `node_modules`, iPhone-Backups, Papierkorb und alte Installationsabbilder.
- **Löschen mit Sicherheitsabfrage:** wahlweise in den Papierkorb oder endgültig. Die Statusleiste zeigt, wie viel Platz du in dieser Sitzung freigegeben hast.
- **Drag & Drop:** Ordner einfach ins Fenster ziehen.
- **Zuletzt gescannte Orte** und Schnellzugriff auf Benutzerordner, Schreibtisch, Dokumente, Downloads, Programme, den ganzen Mac und eingehängte Datenträger.
- **Anzeige des freien Speicherplatzes** des gescannten Datenträgers.

## Installation

### Fertige App (empfohlen)

1. Lade unter [Releases](https://github.com/makro5652/DiskAnalyzer/releases) die Datei `DiskAnalyzer.zip` herunter.
2. Entpacke sie und ziehe `DiskAnalyzer.app` in den Ordner **Programme**.
3. Starte die App.

**Voraussetzungen:** macOS 14 (Sonoma) oder neuer. Der veröffentlichte Build läuft nur auf **Apple Silicon** (arm64). Für Intel-Macs musst du die App selbst bauen (siehe unten).

**Hinweis zu Gatekeeper:** Die App ist weder mit einem Apple-Developer-Zertifikat signiert noch notarisiert. Beim ersten Start meldet macOS deshalb, dass die App nicht überprüft werden kann. So öffnest du sie trotzdem:

- Rechtsklick auf `DiskAnalyzer.app` → **Öffnen** → im Dialog erneut **Öffnen**, oder
- im Terminal die Quarantäne-Markierung entfernen:

  ```sh
  xattr -dr com.apple.quarantine /Applications/DiskAnalyzer.app
  ```

## Bedienungsanleitung

### 1. Einen Scan starten

Nach dem Start siehst du den Begrüßungsbildschirm. Es gibt mehrere Wege, einen Scan zu beginnen:

| Weg | So geht's |
| --- | --- |
| **Ordner wählen** | Klick auf **Ordner wählen …** (oder ⌘O) und einen Ordner oder Datenträger auswählen. |
| **Schnellzugriff** | Auf dem Begrüßungsbildschirm stehen Buttons für Benutzerordner, Schreibtisch usw. In der Symbolleiste öffnet ein längerer Klick auf das Ordner-Symbol ein Menü mit allen Orten, eingehängten Datenträgern und den zuletzt gescannten Ordnern. |
| **Drag & Drop** | Einen Ordner aus dem Finder ins App-Fenster ziehen. |
| **Zuletzt** | Im Ordner-Menü der Symbolleiste unter „Zuletzt" (die letzten sechs Orte). |

Während des Scans zeigt die App einen Zähler der bisher gefundenen Objekte. Über **Abbrechen** kannst du den Vorgang stoppen. Mit **⌘R** (oder dem Pfeil-Symbol „Neu scannen") wiederholst du den letzten Scan, zum Beispiel nach Änderungen außerhalb der App.

> **Tipp:** Wenn du nicht weißt, wo der Platz hin ist, scanne zuerst den **Benutzerordner**. Dort liegen die meisten Platzfresser, und die Ansicht „Aufräumen" ist dort am hilfreichsten. Ein Scan des ganzen Macs (`/`) dauert deutlich länger.

### 2. Das Fenster im Überblick

```
┌──────────────────────────────────────────────────────────────────────┐
│ Symbolleiste: Ordner wählen · Neu scannen · Hoch │ Finder · Öffnen · Löschen │ Suche │
├──────────────────────────────────────────────────────────────────────┤
│ ‹ › ↑  Brotkrumen-Pfad:  Benutzer › makro › Library › Caches         │
├───────────────────────────────┬──────────────────────────────────────┤
│                               │ [ Baum | Dateien | Typen |           │
│       Sunburst-Diagramm       │   Duplikate | Aufräumen ]            │
│                               │                                      │
│                               │   Liste der gewählten Ansicht        │
│                               │                                      │
│                               ├──────────────────────────────────────┤
│                               │ Auswahl: 3 ausgewählt · 1,2 GB       │
├───────────────────────────────┴──────────────────────────────────────┤
│ Statusleiste: Pfad, Größe, Objekte, ohne Zugriff, freigegeben │ Frei: … │
└──────────────────────────────────────────────────────────────────────┘
```

- **Links** liegt das Diagramm, **rechts** die Listenansichten. Die Trennlinie dazwischen lässt sich verschieben.
- Die **Brotkrumen-Leiste** zeigt den Pfad des aktuell angezeigten Ordners. Jeder Teil ist klickbar.
- Die **Statusleiste** zeigt den gescannten Pfad, dessen Gesamtgröße und die Zahl der Objekte. Sie zeigt außerdem, wie viele Ordner nicht gelesen werden konnten (orange), wie viel Speicher du schon freigegeben hast (grün) und rechts den freien Platz des Datenträgers.

### 3. Das Diagramm

Das Diagramm ist ein **Sunburst**: Der Ordner, den du gerade ansiehst, bildet die Mitte. Jeder Ring darum ist eine Ebene tiefer. Die Breite eines Segments entspricht seiner Größe.

**Bedienung:**

| Aktion | Wirkung |
| --- | --- |
| Mit der Maus über ein Segment fahren | In der Mitte erscheinen Name, Größe und Anteil am angezeigten Ordner. |
| **Klick auf einen Ordner** | Springt in diesen Ordner, er wird zur neuen Mitte. |
| **Klick auf eine Datei** | Wählt die Datei aus. Sie wird im Baum markiert und aufgeklappt. |
| **⌘-Klick oder ⇧-Klick** | Fügt ein Segment zur Auswahl hinzu oder nimmt es heraus, ohne zu springen. So wählst du mehrere Objekte aus. |
| **Klick auf die Mitte** | Eine Ebene nach oben. |
| Klick ins Leere | Hebt die Auswahl auf. |

**Farbmodus:** Oben links im Diagramm wechselst du zwischen zwei Darstellungen:

- **Ordner:** Jeder Hauptordner bekommt eine eigene Farbe. Seine Unterordner erscheinen in Abstufungen davon. So siehst du schnell, welcher Bereich wie viel belegt.
- **Typ:** Die Farbe zeigt den Dateityp (Bilder, Videos, Audio, Dokumente, Archive, Code, Programme, Sonstige). Unten links erscheint eine Legende. Ordner sind grau.

Segmente, die kleiner als etwa 0,1 % des Kreises sind, werden nicht gezeichnet. Das Diagramm zeigt maximal fünf Ebenen. Tiefere Ebenen erreichst du, indem du in einen Ordner springst.

### 4. Navigation

- **Zurück / Vor** (‹ und ›, ⌘[ und ⌘]) funktionieren wie im Browser über den Verlauf der besuchten Ordner.
- **Eine Ebene hoch** (↑, ⌘↑) wechselt zum übergeordneten Ordner.
- **Brotkrumen:** Ein Klick auf einen Ordner im Pfad springt direkt dorthin.
- **Doppelklick auf einen Ordner** im Baum springt hinein. Ein Doppelklick auf eine Datei öffnet sie mit der Standard-App.
- **Im Diagramm zeigen** (Rechtsklick) springt zu einem Objekt aus Listen wie „Dateien" oder „Aufräumen" und markiert es im Baum.

### 5. Die fünf Ansichten

Rechts oben wählst du mit dem Umschalter eine der fünf Ansichten. Alle beziehen sich auf den **Scan**, nicht auf eine Live-Suche im Dateisystem.

#### Baum

Zeigt den aktuell angezeigten Ordner als aufklappbare Liste, **größte Einträge zuerst**.

- Spalten: Name, **Anteil** (Balken und Prozent am angezeigten Ordner) und **Größe**.
- Mit dem Pfeil vor einem Ordner klappst du ihn auf oder zu.
- Doppelklick auf einen Ordner: hineinspringen. Doppelklick auf eine Datei: öffnen.
- Rechtsklick öffnet das Kontextmenü (siehe [Auswählen und Löschen](#6-dateien-auswählen-und-löschen)).

#### Dateien

Eine **flache Liste aller Dateien** unterhalb des angezeigten Ordners, **größte zuerst**. Sie eignet sich, um die größten Einzeldateien zu finden, egal wo sie liegen.

- **Typfilter:** Alle Typen oder gezielt Bilder, Videos, Audio, Dokumente, Archive & Images, Code & Daten, Programme oder Sonstige.
- **Altersfilter:** Beliebiges Alter, älter als 30 Tage, 6 Monate, 1 Jahr oder 3 Jahre (nach Änderungsdatum). Damit findest du alte Dateien, die du vermutlich nicht mehr brauchst.
- **Suche:** Das Suchfeld oben rechts in der Symbolleiste filtert nach Dateinamen. Sobald du tippst, wechselt die App automatisch in diese Ansicht.
- **Zurücksetzen** setzt Typ, Alter und Suche zurück.
- Jede Zeile zeigt Name, Ordnerpfad, Änderungsdatum und Größe.
- Aus Performance-Gründen zeigt die Liste höchstens 1000 Treffer. Ein „+" hinter der Anzahl weist darauf hin, dass es mehr gibt. Verfeinere dann die Filter.

#### Typen

Zeigt, **welche Dateitypen** wie viel Platz belegen. Pro Typ siehst du Anzahl, Anteil (Balken und Prozent) und Größe, sortiert nach Größe. Ein Klick auf eine Zeile öffnet die Ansicht „Dateien" mit dem passenden Typfilter.

Die Zuordnung erfolgt über die Dateiendung:

| Typ | Endungen (Auswahl) |
| --- | --- |
| Bilder | jpg, png, gif, heic, tiff, bmp, webp, raw, cr2, cr3, nef, arw, dng, svg, psd, ico |
| Videos | mp4, mov, mkv, avi, m4v, wmv, flv, webm, mpg, mpeg |
| Audio | mp3, m4a, wav, aac, flac, aiff, ogg, wma |
| Dokumente | pdf, doc(x), xls(x), ppt(x), pages, numbers, key, txt, rtf, md, csv, odt, ods, odp, epub |
| Archive & Images | zip, rar, 7z, tar, gz, tgz, bz2, xz, dmg, iso, pkg, xip |
| Code & Daten | swift, m, h, c, cpp, js, ts, py, java, rb, go, rs, json, html, css, xml, sh, yml, yaml |
| Programme | alle Dateien innerhalb von `.app`-Paketen |
| Sonstige | alles andere |

#### Duplikate

Findet **identische Dateien**, auch wenn sie unterschiedlich heißen oder an verschiedenen Orten liegen.

1. Wähle die **Mindestgröße** (ab 100 KB, 1 MB, 10 MB oder 100 MB). Kleinere Dateien werden ignoriert, damit die Suche schnell bleibt.
2. Klicke auf **Duplikate suchen**. Ein Fortschrittstext zeigt den Stand. Mit **Abbrechen** stoppst du die Suche.
3. Das Ergebnis erscheint als **Gruppen** gleicher Dateien. Jede Gruppe zeigt Name, Größe, Anzahl der Kopien und die „Verschwendung" (Platz, den die überzähligen Kopien belegen). Oben steht die Gesamtsumme.
4. Entscheide, was weg soll:
   - **Kopien markieren (älteste behalten):** markiert in jeder Gruppe alle Dateien außer der ältesten.
   - **Rechtsklick → Nur diese Kopie behalten:** markiert in der Gruppe alle anderen Dateien.
   - Oder wähle einzelne Dateien von Hand aus.
5. Lösche die markierten Dateien über die Leiste unten oder die Symbolleiste.

**So wird verglichen:** Erst nach Dateigröße, dann über die ersten 64 KB, zuletzt über den vollständigen SHA-256-Hash. Zwei Dateien gelten nur als Duplikat, wenn ihr Inhalt Byte für Byte übereinstimmt. **Hardlinks** (mehrere Namen für dieselbe Datei auf der Platte) werden nicht gezählt, weil sie keinen zusätzlichen Platz belegen. Die Ansicht zeigt maximal 300 Gruppen.

> **Wichtig:** Prüfe Duplikate, bevor du löschst. Die App kann nicht wissen, ob eine Kopie absichtlich an einem bestimmten Ort liegt, zum Beispiel in einem Projektordner.

#### Aufräumen

Zeigt **bekannte Platzfresser**, die sich meist gefahrlos entfernen lassen, jeweils mit einer Begründung. Oben steht, wie viel Platz du höchstens freibekommst. **Alle markieren** wählt alle Vorschläge aus.

Folgende Kandidaten werden erkannt:

| Kandidat | Hinweis |
| --- | --- |
| `Library/Caches/…` | App-Caches, werden bei Bedarf neu aufgebaut |
| `node_modules` | Node-Abhängigkeiten, mit `npm install` wiederherstellbar |
| Xcode `DerivedData` | Build-Zwischendaten, werden neu erzeugt |
| Xcode `Archives` | nur löschen, wenn du die Builds nicht mehr brauchst |
| Xcode `iOS DeviceSupport` | wird beim nächsten Anschließen neu geladen |
| `Developer/CoreSimulator` | Simulator-Daten, Geräte lassen sich neu anlegen |
| `.Trash` | Papierkorb |
| `MobileSync/Backup` | iPhone- und iPad-Backups |
| `.dmg`, `.iso`, `.pkg`, `.xip` im Downloads-Ordner | Installationsabbilder, nach der Installation meist überflüssig |

Doppelklick auf einen Eintrag springt im Diagramm dorthin, damit du ansehen kannst, was drinsteckt. Liegt ein Vorschlag in einem anderen Vorschlag, erscheint nur der äußere.

> **Vorsicht:** Das sind Vorschläge, keine Garantien. Prüfe vor allem **iPhone-Backups** und **Xcode-Archive**, denn sie lassen sich nicht neu erzeugen. Der Papierkorb wird beim endgültigen Löschen unwiderruflich geleert.

### 6. Dateien auswählen und löschen

**Auswählen**

- Klick auf eine Zeile wählt sie aus. Mit ⌘ oder ⇧ wählst du mehrere Zeilen aus (wie im Finder).
- Im Diagramm wählst du mit ⌘-Klick oder ⇧-Klick mehrere Segmente aus.
- Die Auswahl gilt in allen Ansichten. Unter der Liste steht die Zusammenfassung, zum Beispiel „3 ausgewählt · 1,2 GB", mit den Buttons **Aufheben**, **Im Finder zeigen** und **Löschen …**.
- Ist ein Ordner und eine seiner Dateien gleichzeitig ausgewählt, zählt nur der Ordner. So wird nichts doppelt gezählt oder gelöscht.

**Kontextmenü (Rechtsklick)**

| Eintrag | Wirkung |
| --- | --- |
| Im Finder zeigen | Öffnet den Finder und markiert das Objekt (bei Mehrfachauswahl alle). |
| Öffnen | Öffnet die Datei oder den Ordner mit der Standard-App. |
| Im Diagramm zeigen | Springt im Diagramm und im Baum zum Objekt. |
| Pfad kopieren | Kopiert den vollständigen Pfad in die Zwischenablage. |
| Löschen … | Startet den Löschdialog. |

Ist das angeklickte Objekt Teil der aktuellen Auswahl, gilt die Aktion für die gesamte Auswahl.

**Löschen**

Beim Löschen (Symbolleiste, Kontextmenü, Auswahl-Leiste oder ⌘⌫) erscheint immer eine Sicherheitsabfrage mit Name und Größe. Du hast drei Optionen:

- **In den Papierkorb:** Die Dateien landen im Papierkorb und lassen sich dort wiederherstellen. Der Speicher wird aber **erst frei, wenn du den Papierkorb leerst**.
- **Endgültig löschen:** Die Dateien werden sofort und **unwiderruflich** entfernt.
- **Abbrechen:** Es passiert nichts.

Nach dem Löschen aktualisiert die App Diagramm, Größen und Listen sofort, **ohne neu zu scannen**. Die Statusleiste zählt mit, wie viel du in dieser Sitzung freigegeben hast. Konnte etwas nicht gelöscht werden (zum Beispiel wegen fehlender Rechte), zeigt die App eine Fehlermeldung mit den betroffenen Objekten.

### 7. Tastenkürzel

| Kürzel | Aktion |
| --- | --- |
| ⌘O | Ordner wählen |
| ⌘R | Neu scannen |
| ⌘↑ | Eine Ebene hoch |
| ⌘[ | Zurück |
| ⌘] | Vor |
| ⌘⌫ | Auswahl löschen (mit Rückfrage) |
| ⌘-Klick / ⇧-Klick | Mehrfachauswahl (Liste und Diagramm) |
| Doppelklick | Ordner: hineinspringen · Datei: öffnen |

## Zugriffsrechte (Festplattenvollzugriff)

DiskAnalyzer läuft **ohne App-Sandbox**, damit sie beliebige Ordner lesen kann. macOS schützt aber manche Bereiche (zum Beispiel Mail, Fotos, Safari-Daten oder Teile von `~/Library`) zusätzlich.

Zeigt die Statusleiste **„N Ordner ohne Zugriff"** in Orange, konnten diese Ordner nicht gelesen werden. Ihr Platzbedarf fehlt dann in der Auswertung, und die Summe ist niedriger als in Wirklichkeit. So behebst du das:

1. Öffne **Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff**.
2. Aktiviere den Schalter für **DiskAnalyzer** (über **+** hinzufügen, falls die App fehlt).
3. Starte die App neu und scanne erneut.

Ohne Festplattenvollzugriff fragt macOS beim Scannen bestimmter Ordner (Schreibtisch, Dokumente, Downloads, externe Datenträger) einzeln nach Erlaubnis. Bestätige diese Abfragen, damit der Scan vollständig ist.

## Wie die App rechnet

- **Größen sind belegter Speicherplatz auf der Platte** (allokierte Größe), nicht die Dateigröße, die der Finder bei „Informationen" als „Größe" nennt. Das ist die Zahl, die zählt, wenn es um freien Platz geht. Kleine Dateien belegen mindestens einen Block, daher kann die Summe leicht über der Summe der Dateigrößen liegen.
- **Symbolische Links werden übersprungen**, damit nichts doppelt gezählt wird und Schleifen vermieden werden.
- **Pakete wie `.app`** werden wie Ordner durchsucht. Ihr Inhalt zählt als Typ „Programme".
- **Beim Scan von `/`** werden `/System/Volumes`, `/Volumes` und `/dev` ausgelassen, weil sie sonst Daten doppelt zählen (Firmlinks) oder keine echten Dateien sind. Eingehängte Datenträger scannst du separat.
- Der Scan ist eine **Momentaufnahme**. Änderungen außerhalb der App siehst du erst nach einem neuen Scan (⌘R). Löschungen in der App werden dagegen sofort übernommen.
- **Speicherplatz in iCloud/OneDrive:** Dateien, die nur in der Cloud liegen und nicht heruntergeladen sind, belegen lokal (fast) keinen Platz und erscheinen entsprechend klein.
- **Zeitmaschine und APFS-Schnappschüsse** werden nicht erfasst. Lokale Schnappschüsse können Speicher belegen, der in der App nicht auftaucht.

## Kommandozeile

Die App lässt sich mit einem Ordner als Argument starten und beginnt dann sofort mit dem Scan:

```sh
/Applications/DiskAnalyzer.app/Contents/MacOS/DiskAnalyzer --scan ~/Downloads
```

## Aus dem Quellcode bauen

**Voraussetzungen:** Xcode (mit Unterstützung für macOS 14 oder neuer) und macOS 14+.

```sh
git clone https://github.com/makro5652/DiskAnalyzer.git
cd DiskAnalyzer
xcodebuild -project DiskAnalyzer.xcodeproj -scheme DiskAnalyzer -configuration Release build
```

Alternativ öffnest du `DiskAnalyzer.xcodeproj` in Xcode und startest die App mit ⌘R. Die gebaute App liegt bei einem Kommandozeilen-Build unter `~/Library/Developer/Xcode/DerivedData/…/Build/Products/Release/`.

Für ein **Universal-Binary** (Apple Silicon und Intel) hängst du `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` an den `xcodebuild`-Aufruf an.

Zum Weitergeben als Archiv:

```sh
ditto -c -k --sequesterRsrc --keepParent DiskAnalyzer.app DiskAnalyzer.zip
```

## Projektstruktur

| Datei | Inhalt |
| --- | --- |
| `DiskAnalyzerApp.swift` | App-Einstieg, Fenster, Start-Argument `--scan` |
| `ContentView.swift` | Hauptfenster: Symbolleiste, Brotkrumen, Statusleiste, Drag & Drop |
| `Models.swift` | Datenmodell, Scanner, Dateitypen, Aufräum-Regeln, Filter, App-Zustand und Löschlogik |
| `SunburstView.swift` | Berechnung und Zeichnung des Kreisdiagramms |
| `FileListView.swift` | Baumansicht, Kontextmenü, Auswahl-Leiste |
| `Panels.swift` | Ansichten „Dateien", „Typen", „Duplikate" und „Aufräumen" |
| `Duplicates.swift` | Duplikat-Suche (Größe → Dateianfang → SHA-256) |
| `Assets.xcassets` | App-Icon |

## Häufige Fragen

**Warum ist die Summe kleiner als der belegte Speicher in den Systemeinstellungen?**
Wahrscheinlich konnten Ordner nicht gelesen werden (siehe [Festplattenvollzugriff](#zugriffsrechte-festplattenvollzugriff)). Auch APFS-Schnappschüsse, Time-Machine-Daten und Systembereiche, die beim Scan von `/` ausgelassen werden, tauchen nicht auf.

**Ich habe gelöscht, aber der freie Speicher ist nicht gestiegen.**
Du hast vermutlich „In den Papierkorb" gewählt. Leere den Papierkorb oder wähle beim nächsten Mal „Endgültig löschen". Auch lokale Zeitmaschinen-Schnappschüsse können Platz festhalten.

**Kann ich mit der App etwas kaputt machen?**
Die App löscht nur, was du ausdrücklich bestätigst. Lösche aber nichts in Systemordnern (`/System`, `/Library`, `/usr`) oder in den Daten laufender Programme, wenn du nicht sicher bist, was es ist. Im Zweifel den Weg über den Papierkorb nehmen.

**Warum zeigt die Duplikat-Suche nichts an?**
Entweder gibt es in diesem Scan keine identischen Dateien ab der gewählten Mindestgröße, oder die Kopien sind Hardlinks. Senke die Mindestgröße und suche erneut.

**Warum fehlen kleine Segmente im Diagramm?**
Segmente unter etwa 0,1 % des Kreises werden nicht gezeichnet. Sie sind in den Listen weiterhin vorhanden. Springe in einen Ordner, damit seine Inhalte größer dargestellt werden.

**Warum läuft die App nicht auf meinem Intel-Mac?**
Der veröffentlichte Build ist nur für Apple Silicon. Baue die App selbst (siehe oben), idealerweise als Universal-Binary.

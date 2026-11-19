# AZ Budget

[English](README.md) · [Bei Google Play laden](https://play.google.com/store/apps/details?id=dev.artiz.az_budget&hl=de)

Kein Konto, kein Server, keine Werbung.

**iOS:** Es gibt keine offizielle iOS-Version. Apple hat mein Entwicklerkonto
wegen meiner belarussischen Staatsbürgerschaft gesperrt, deshalb kann ich
nicht im App Store veröffentlichen.

Android-App (Flutter) für ein Haushaltsbudget, das in einer Tabelle pro Jahr
lebt, `Budget <Jahr>.xlsx`, in einem Cloud-Ordner (Google Drive, Dropbox,
iCloud oder lokaler Speicher). Die App hängt Buchungen an diese Datei an; die
Tabelle behält alle Formeln, die Übersicht und die Diagramme und bleibt am
Laptop bearbeitbar. Belege werden **auf dem Gerät** mit
[docling.rs](https://github.com/docling-project/docling.rs) gelesen;
Kontoauszüge und Screenshots aus Banking-Apps werden von docling.rs (Text)
und einem OpenAI-Modell (Struktur) zu Buchungen, mit dem eigenen API-Schlüssel.

```
Eingabe von Hand / Schnellbuchung ─┐
Belegfoto ──► rust/receipt_ocr (docling.rs OCR + rqrr QR) ──► Parser ──► eine Buchung zum Bestätigen
Screenshot ─► rust/receipt_ocr OCR ──► Text ─┐
Auszug-PDF ─► docling.rs Textebene (Zeilen) ─┴► OpenAI (gpt-4.1-mini, JSON-Schema) ──► Prüfliste
                                                     │
                     lokale Warteschlange ◄──────────┘
                            │ Abgleich (wie ein Drive-Client)
                            ▼
          Budget <Jahr>.xlsx im gewählten Ordner: Blatt "Buchungen" bekommt neue Zeilen,
          Eingaben in "Übersicht" sind bearbeitbar, "Einstellungen" enthält Kategorien + Limits
```

## Die Tabelle ist die Datenbank

Eine Datei pro Jahr. Neue Nutzer bekommen sie aus einer mitgelieferten
Vorlage (`app/assets/templates/budget_{de,en,ru}.xlsx`, erzeugt von
`tools/budget_template.py`); der Aufbau unten ist der Vertrag, hier mit den
deutschen Namen. Die englische und die russische Vorlage haben denselben
Aufbau mit übersetzten Blattnamen, Beschriftungen und Kategorien (die
englischen Namen stehen in der [README.md](README.md)). Der Leser findet jede
Zeile über die Bedeutung ihrer Beschriftung (`app/lib/budget/budget_labels.dart`),
daher wird eine Datei in jeder der drei Sprachen, auch mit umbenannten
Blättern, gleich gelesen. Kategorienamen sind nirgends fest eingebaut; sie
kommen aus der Datei.

| Blatt | Vertrag |
| --- | --- |
| `Buchungen` | Zeile 1 Kopf, dann `A` Datum, `B` Monat (Formel), `C` Kategorie, `D` Beschreibung, `E` Betrag (€), `F` Notiz. Ausgaben positiv, Einnahmen negativ. Die Zeilen sind bis 2000 vorformatiert; die App füllt die nächste leere (und legt bei Bedarf Zeilen über 2000 an). |
| `Übersicht` | Eingabezeilen werden über ihre Beschriftung in Spalte `A` gefunden (`Kontostand Monatsanfang…`, `Sparkonto`, `Kreditkarte offen…`), Monate in `B..M`; der Plan-Block von der Zeile `Plan` bis `Summe Plan`. Alles andere sind Formeln. |
| `Einstellungen` | Kategorien unter dem Kopf `Kategorie` (`A` Name, `B` Typ: Ausgabe / Einnahme / Umbuchung, `D` Hinweis, `E` Symbol und Farbe wie in der App gewählt, z. B. `basket #FF2E7E`); Einstellungen als Beschriftung/Wert in `F`/`G` (`Monatslimit 1/2`, `Ausgabenlimit 1/2/3`). Weitere Einstellungen können darunter ergänzt werden; die App liest, was dort steht. |
| `Verlauf` | Monatsbeschriftungen `JJJJ-MM`; die App setzt sie nur beim Anlegen eines neuen Jahres neu. |
| `Regeln` | Optional. Unter dem Kopf `Muster`: `A` Muster (Groß-/Kleinschreibung egal, `*` für beliebigen Text), `B` Kategorie, `C` Beschreibung. Auszug-Import und Belegscan prüfen diese vor der gelernten Historie und vor dem Modell; „Als Regel merken“ in der Import-Prüfung hängt hier an (in einer alten Datei wird das Blatt angelegt). |

Die App schreibt die Arbeitsmappe nie neu. Sie ändert einzelne Zellen im
Blatt-XML innerhalb der ZIP-Datei (`app/lib/budget/xlsx_workbook.dart`) und
kopiert jeden anderen Eintrag Byte für Byte, so dass Formeln aus
Excel/LibreOffice, bedingte Formate, die Tabelle, Datenüberprüfung, Kommentare
und Diagramme erhalten bleiben. Sie setzt `fullCalcOnLoad`, damit die Tabelle
beim Öffnen neu rechnet. Tests prüfen das an einer erzeugten Datei und an
einer in LibreOffice neu gespeicherten Kopie.

Nichts an Kategorien oder Schnellbuchungen ist fest eingebaut: die
Kategorieliste, die Autovervollständigung je Kategorie („S“ → „Spar“ unter
Lebensmittel), die Schnellbuchungen auf dem Startbildschirm (häufigste Paare
aus Kategorie und Beschreibung mit ihrem letzten Betrag) und die für einen
gescannten Händler geschätzte Kategorie kommen alle aus den Buchungen der
Datei.

## Aufbau

| Pfad | Was |
| --- | --- |
| `rust/receipt_ocr/` | Rust-Crate: Texterkennung (Detektor + Erkenner) von docling.rs und der Leser für die PDF-Textebene hinter einer C-ABI (`receipt_ocr_*`) für `dart:ffi`, dazu das Kommandozeilenwerkzeug `receipt-ocr`. Liest auch österreichische RKSV-QR-Codes. |
| `app/` | Flutter-App (Android). Budgetmodell + xlsx-Patcher, Ordnerzugriff (Storage Access Framework), Beleg-Parser, Auszug-Import, Oberfläche, Übersetzungen (en/de/ru). |
| `app/android/.../MainActivity.kt` | Die Ordner-Brücke: einmal einen Ordner wählen (dauerhafte Freigabe), Dateien über den Dokumentanbieter von Drive, Dropbox, iCloud oder dem lokalen Speicher auflisten, lesen und schreiben. |
| `samples/receipts/`, `samples/golden/` | Beispielbelege und ihre OCR-Ausgabe: Regressionsdaten für die Parser-Tests in Dart. |
| `app/test/fixtures/` | Kleine synthetische `Budget 2026.xlsx` (plus eine in LibreOffice neu gespeicherte Kopie) für die xlsx-Tests. |
| `scripts/download_models.sh` / `.bat` | Lädt die ONNX-Modelle (~31 MB) mit SHA256-Prüfung nach `app/assets/models`. |
| `scripts/build_android_rust.sh` / `.bat` | Baut die Rust-Crate mit `cargo-ndk` für Android nach `app/android/app/src/main/jniLibs`. |
| `scripts/build_android.bat` | Windows in einem Schritt: Modelle → Rust-`.so` → `flutter build apk` (`--run`, `--install`, `--debug`). |

## Die App benutzen

1. **Startbildschirm**: Beim ersten Start erklärt die App sich in fünf
   Schritten und fragt nach dem Ordner (später wieder unter *Einstellungen →
   So funktioniert die App*). Den Ordner wählen, in dem `Budget <Jahr>.xlsx`
   liegt (in der Ordnerauswahl der Drive-App den Ordner wählen, nicht die
   Datei). Die Freigabe bleibt bestehen; die App listet die Jahresdateien auf
   und lädt das aktuelle Jahr. In einem leeren Ordner wird `Budget <Jahr>.xlsx`
   aus der Vorlage in der App-Sprache angelegt (Deutsch, Englisch oder
   Russisch, nach der Systemsprache, außer sie ist in den Einstellungen
   gesetzt), mit übersetzten Kategorien, Plan-Block und Limits (3000/4000 € pro
   Monat, 200/500/1000 € pro Buchung), die du in der *Übersicht* oder in der
   Datei ändern kannst. Hat das Kalenderjahr noch keine Datei, bietet die App
   an, sie aus der neuesten anzulegen (Kategorien, Einstellungen und Plan
   kopiert, keine Buchungen), oder, wenn der Ordner leer ist, aus der Vorlage
   mit Sprachauswahl.
2. **Buchungen**: Oben auf dem Bildschirm liegen die Schnellbuchungen (tippen
   → Betrag bestätigen oder ändern; eine Kachel lange drücken, oder eine
   Tabellenzeile lange drücken oder nach rechts wischen, heftet diese
   Kombination aus Kategorie und Beschreibung vorne an, noch einmal löst sie;
   Anheftungen bleiben auf dem Gerät), darunter die Buchungstabelle mit
   Suchfeld, beim Scrollen in Schritten von 20 geladen. Der Kalender-Knopf
   neben den Schnellbuchungen schaltet auf einen **Monatskalender** um (wird
   gemerkt): Jeder Tag zeigt seinen Geldfluss mit Vorzeichen und Währung
   (Ausgaben „-424 €“, Zahltag „+3 200 €“ in Grün; Umbuchungen zählen nicht),
   darunter Einnahmen, Ausgaben und Saldo des Tages und des Monats bis dahin
   (Summen und Farben wie in der Übersicht), dann die Buchungen des gewählten
   Tages; Wischen oder die Pfeile wechseln den Monat innerhalb des geladenen
   Jahres, und *+ Buchung* bucht auf den gewählten Tag. Eine Zeile antippen
   bearbeitet sie (wartende Zeilen ebenso wie Zeilen, die schon in der Datei
   stehen; die Zeile in der Datei wird an Ort und Stelle neu geschrieben); das
   **+** an einer Zeile stockt sie auf („+6 Glühwein“: Betrag addiert, Detail an
   die Notiz angehängt). *Neue Buchung* hat Kategorie, Beschreibung mit
   Autovervollständigung, Betrag, Notiz und Datum (die Kategorieauswahl ist
   alphabetisch, die meistgenutzte ist vorausgewählt); fehlen Kategorie oder
   Betrag, sagt das Formular es am jeweiligen Feld. Einnahmen werden als
   einfache Zahl eingegeben und negativ gespeichert. Langes Drücken auf
   *+ Buchung* öffnet ein Menü mit allen Wegen: von Hand, Belegfoto, Bild aus
   der Galerie, Auszug-PDF. Hat eine neue Buchung denselben Betrag wie eine
   innerhalb von drei Tagen gebuchte, fragt die App, ob die Details stattdessen
   an deren Notiz angehängt werden sollen (ein gescannter Beleg zu einem schon
   von Hand gebuchten Kauf). Neue Buchungen kommen in eine lokale
   Warteschlange und werden sofort in die Datei geschrieben; ohne Netz warten
   sie und werden beim nächsten Start, Fortsetzen oder Abgleich geschrieben,
   wie bei einem Drive-Client. Wartende Buchungen, deren Jahr keine Datei hat
   (ein falsch gelesenes Belegdatum), erscheinen in einem Hinweis mit der
   Aktion *Datum korrigieren*, statt ewig zu warten. Das Jahr folgt dem
   Kalender: Die Datei des aktuellen Jahres wird geladen, das Jahresmenü in der
   Statuszeile wechselt zu einer anderen Datei, und wenn ein neues Jahr noch
   keine Datei hat, bietet ein Hinweis an, `Budget <Jahr>.xlsx` aus der
   neuesten Datei anzulegen (Kategorien, Einstellungen und Plan bleiben,
   Buchungen und Kontoeingaben werden geleert; `Verlauf` bleibt dem Laptop
   überlassen).
3. **Kamera-Knopf**: einen Beleg fotografieren. docling.rs-OCR und der Parser
   schlagen eine Buchung vor: Händler als Beschreibung, Summe als Betrag, die
   Positionen in der Notiz, die Kategorie aus der Historie der Datei für
   diesen Händler. Die eigene Kamera der App zeigt zwei senkrechte
   Hilfslinien und löst selbst aus, sobald eine Papierkante im Bild ist
   (Linien gelb: eine Kante, grün: der ganze Beleg) und das Handy 0,3 s still
   gehalten wird; ein einzelnes schlechtes Bild startet die Wartezeit nicht
   neu, Änderungen der automatischen Belichtung zählen nicht als Bewegung
   (`lib/camera/receipt_frame.dart`: aufsummierte vorzeichenbehaftete
   Helligkeitssprünge je Spalte finden die Papierkanten, kein Modell, etwa
   eine Millisekunde pro Bild). Hinweise sagen „näher“, „etwas zurück“,
   „mittig“; langes Drücken auf den Hinweis zeigt die Werte des Detektors
   (Kanten, Sprung, Zeilen, Bewegung, Haltezeit, Bilder pro Sekunde) zum
   Abstimmen. Der Auslöser geht jederzeit, die Taschenlampe ist einen Tipp
   entfernt. *Einstellungen → Belegkamera* schaltet das automatische Auslösen
   ab oder kehrt zur Kamera-App des Handys zurück, die auch einspringt, wenn
   die Kamera-Berechtigung verweigert wird.
4. **Bild-Knopf**: ein Screenshot aus einer Banking-App aus der Galerie → OCR →
   OpenAI → Prüfliste.
5. **PDF-Knopf**: ein Kontoauszug → Textebene von docling.rs (als Zeilen
   aufgebaut: Text, Valutadatum, Betrag) → die Zeilen werden deterministisch
   gelesen: Datum und Betrag genau wie gedruckt, Händler aus der Zeile oder
   ihrer Detailzeile, Kreditkartenabrechnungen als Umbuchungen auf die
   Kreditkarte, Bargeldabhebungen und eigene Überweisungen übersprungen. Die
   Kategorie kommt aus der eigenen Historie der Datei für diesen Händler; nur
   Händler, die die Datei nie gesehen hat, gehen in einer kleinen Anfrage
   nach ihrer Kategorie an OpenAI. Ohne API-Schlüssel werden diese Zeilen nur
   zum Auswählen markiert. Zeilen, deren Betrag und Datum zu einer bestehenden
   Buchung passen, werden als *schon gebucht* markiert und abgewählt. Nichts
   wird geschrieben vor *n übernehmen*. Freier Text (Screenshots) geht
   weiterhin als Ganzes an das Modell.
6. **Übersicht**: Einnahmen, Ausgaben mit Ampel gegen `Monatslimit 1/2` (grün,
   gelb ab Limit 1, rot ab Limit 2; dasselbe Symbol sitzt oben im
   Startbildschirm), Saldo, Ist gegen Plan je Kategorie mit einem Stift zum
   Ändern des Monatsplans, und die Eingabezeilen der `Übersicht` (Kontostand,
   Sparkonto, Kreditkarte offen) je Monat bearbeitbar; sie nehmen eine kleine
   Formel an (`=500+232,23`), die in der Zelle bleibt. Ein Tipp auf die
   Ausgaben-Karte bearbeitet die beiden Monatslimits (geschrieben nach
   `Einstellungen`). Die App sendet eine Systembenachrichtigung, sobald die
   Ausgaben des Kalendermonats Limit 1 erreichen, und noch einmal bei Limit 2;
   vor jedem davon eine optionale Frühwarnung („Limit 1/2 fast erreicht“),
   wenn sie in die Nähe des Limits kommen, standardmäßig 5 % davon, für jedes
   Limit getrennt einstellbar unter *Einstellungen → Benachrichtigungen* als
   Prozent oder fester Betrag, oder abschaltbar. Die Warnung vor Limit 2 kommt
   erst, wenn Limit 1 überschritten ist.
7. **Einstellungen → OpenAI**: API-Schlüssel (im verschlüsselten Speicher von
   Android) und Modell (Standard `gpt-4.1-mini`). Nur der Import von Auszügen
   und Screenshots nutzt es. **Einstellungen → Sprache** überschreibt die
   Systemsprache (Deutsch, Englisch, Russisch).
8. **Einstellungen → Kategorien**: Name, Typ, Hinweis, Symbol (aus einem
   eingebauten Satz) und Farbe jeder Kategorie, gespeichert im Blatt
   `Einstellungen` der Datei, dazu *Kategorie hinzufügen* (mehrere
   Einnahmekategorien, mehrere Kreditkarten). Eine Umbenennung zieht sich durch
   die Buchungen, die Zeilen der Übersicht, die Formeln, die den Namen zitieren
   (Einnahme- und Umbuchungskategorien), und das bedingte Format des
   Buchungsblatts. Ein geänderter oder neuer Typ baut die Zeile `Einnahmen`
   der Übersicht (Summe über alle Einnahmekategorien) und die Zeile `Ausgaben`
   (alles außer Einnahmen und Umbuchungen) neu auf, leert oder füllt die Zeile
   der Kategorie im Ist-Block, erweitert die Kategorieauswahl im Buchungsblatt
   und übernimmt das grau-kursive Format der Umbuchungszeilen. Eine neue
   *Ausgabe*-Kategorie bekommt keine eigene Zeile in den Ist-/Plan-Blöcken des
   Blatts (die App zählt sie trotzdem). Ist die Datei in einer anderen Sprache
   als die App (etwa weil sie angelegt wurde, bevor die Sprache gewechselt
   wurde), übersetzt *Datei auf … übersetzen* Kategorienamen und Hinweise,
   Typbezeichnungen, Beschriftungen der Einstellungen und die Beschriftungen
   von Übersicht und Verlauf in die App-Sprache; Buchungen werden mit ihren
   Kategorien umbenannt, eigene Texte und die Blattnamen bleiben (Formeln
   verweisen auf die Blattnamen, die Tabellendefinition der Buchungen auf
   ihren Kopf). **Dateiversion**: Das Einstellungsblatt hat eine Zeile
   `Dateiversion` (die Vorlagen schreiben 2; eine Datei ohne die Zeile ist
   Version 1, der Aufbau, mit dem diese App begann). Die Einstellungen zeigen
   die Version der geladenen Datei und für eine ältere Datei einen Knopf
   *Aktualisieren*, der in der Sprache der Datei ergänzt, was fehlt: das Blatt
   `Regeln`, den Spaltenkopf `Symbol & Farbe`, die Limit-Einstellungen der
   Vorlage, die Versionszeile. Bestehende Zeilen, Beschriftungen und Formeln
   bleiben unberührt; die Aktualisierung kann beliebig oft laufen.
9. **In die App teilen**: AZ Budget ist ein Teilen-Ziel für PDFs, Bilder und
   Text („Teilen“ in der App eines Geschäfts, in Gmail, in der Galerie, oder
   „Öffnen mit“ für eine heruntergeladene Datei). Ein digitaler Beleg eines
   Geschäfts (PDF-E-Bon) wird aus seiner Textebene mit Positionen gelesen und
   läuft durch denselben Parser wie ein Foto, direkt ins Buchungsformular; ein
   Kontoauszug-PDF geht in die Prüfliste; ein Bild wird wie ein Kamerafoto
   gescannt; Text geht an das Modell. Dieselbe PDF-Weiche gilt für den
   PDF-Knopf auf dem Startbildschirm. Teilen braucht einen gewählten Ordner;
   die geteilte Kopie wird danach gelöscht.
10. **Sicher schreiben**: Jeder Schreibvorgang liest die Datei neu und
    vergleicht direkt davor ihre Änderungszeit; hat der Laptop zwischendurch
    gespeichert, wird die Änderung auf die frische Datei neu angewendet, statt
    sie zu überschreiben. Vor jedem Schreiben wird die vorige Fassung nach
    `.backup/` im Budget-Ordner kopiert (höchstens alle zehn Minuten pro Jahr,
    standardmäßig bleiben die neuesten drei; *Einstellungen → Daten* legt fest,
    wie viele, oder schaltet es ab). Ältere Kopien werden nach jeder
    Sicherung gelöscht, einmal nach dem ersten Abgleich einer Sitzung und
    sofort, wenn die Anzahl verringert wird.
11. **Beleg aufteilen**: Das Buchungsformular eines gescannten Belegs bietet
    *Nach Kategorie aufteilen*: jeder Position eine Kategorie geben, dann wird
    eine Buchung pro Kategorie gespeichert, die Positionen in den Notizen, ein
    Rundungsrest bei der Hauptbuchung. Die gescannte Datei (Foto oder PDF)
    kommt nach `Belege/<Jahr>/` neben die Budget-Dateien und wird in der Notiz
    verlinkt (*Einstellungen → Daten*).
12. **Jahresansicht**: Das Monatsmenü der *Übersicht* hat einen Eintrag *Jahr*.
    Wischen geht Schritt für Schritt durch „… Nov 2025, Dez 2025, Jahr 2025,
    Jan 2026 …“ über die Jahresdateien im Ordner. Die Ansicht zeigt zwölf
    Monate als Balken (Farbe = Limit, Plan grau, Linie = kumuliertes Saldo)
    und für jede Kategorie das Ist über dem Monatsdurchschnitt (über die
    Monate bisher: im laufenden Jahr bis zum aktuellen Monat, ein vergangenes
    Jahr über 12) und den Plan über dem Vorjahr (aus `Budget <Jahr-1>.xlsx`).
    Ein Tipp auf eine Kategorie öffnet ihr Jahr: die Monate mit einem Betrag
    (ein Tipp darauf öffnet den Monat) und die Beschreibungen mit Anzahl und
    Summe.
13. **Widget und Verknüpfungen**: Ein Widget auf dem Startbildschirm zeigt die
    Ausgaben des Monats gegen Limit 1 mit der Ampelfarbe und ein „+“ für eine
    Buchung; langes Drücken auf das App-Symbol bietet Scannen, neue Buchung
    und Auszug-Import.
14. **Einstellungen → Daten**: Währungssymbol (die Datei enthält keins),
    CSV-Export des geladenen Jahres in den Ordner; die *Übersicht* teilt eine
    Zusammenfassung des Monats als Text.
15. **Übersicht**: unter dem Saldo ein Balken je Ausgabekategorie für den
    Monat, der Plan in Grau mit dem Ist-Betrag darüber in der Farbe der
    Kategorie, Symbole an der x-Achse, die größten rechts; ein Tipp auf einen
    Balken zeigt Name und Zahlen.

## Bauen

Voraussetzungen: Rust ≥ 1.92, Flutter 3.47 stable, Android SDK + NDK (r26+),
`cargo install cargo-ndk`.

```bash
scripts/download_models.sh                      # Modelle → app/assets/models (nicht in git)
```

```bash
scripts/build_android_rust.sh                   # libreceipt_ocr.so → app/android/app/src/main/jniLibs/arm64-v8a
```

```bash
cd app && flutter pub get && flutter build apk --release
```

Der Gradle-Build verweigert das Packen der App, wenn `libreceipt_ocr.so`
fehlt, und die App startet die OCR nicht, wenn die Modelldateien fehlen; eine
halb gebaute APK scheitert also deutlich, statt still leere Scans zu liefern.

Die Anwendungs-ID ist jetzt `dev.artiz.az_budget` (Name *AZ Budget*): Die
alte App *Receipts* kann deinstalliert werden, sie enthielt nichts, was die
neue braucht.

### Windows

Einmal installieren:

1. **Git for Windows** und **Visual Studio Build Tools** mit der Workload
   *Desktop development with C++*.
2. **Rust**: `rustup-init.exe` von <https://rustup.rs> ausführen, dann
   `cargo install cargo-ndk`.
3. **Flutter SDK** 3.47 stable: z. B. nach `C:\src\flutter` entpacken und
   `C:\src\flutter\bin` zum `PATH` hinzufügen.
4. **Android Studio**: im *SDK Manager → SDK Tools* *Android SDK
   Platform-Tools*, *Android SDK Command-line Tools* und *NDK (Side by side)*
   anhaken. Dann `flutter doctor --android-licenses` und `flutter doctor`
   ausführen, bis die Zeile für die Android-Toolchain grün ist.
5. Auf dem Handy *Entwickleroptionen → USB-Debugging* einschalten und es
   anschließen; `adb devices` muss es auflisten.

Das Build-Skript findet das NDK selbst unter `%ANDROID_HOME%\ndk` oder
`%LOCALAPPDATA%\Android\Sdk\ndk`; `ANDROID_NDK_HOME` setzt einen anderen Pfad.
Im Wurzelverzeichnis des Repositorys:

```bat
scripts\build_android.bat --run
```

lädt die Modelle, baut die Rust-Crate für `arm64-v8a`, führt
`flutter pub get` aus und startet einen Debug-Build auf dem angeschlossenen
Gerät. `scripts\build_android.bat` allein baut
`app\build\app\outputs\flutter-apk\app-release.apk`; `--install` baut und
installiert sie; `--debug` baut nur eine Debug-APK. Die Schritte gehen auch
einzeln (`scripts\download_models.bat [--verify] [Verzeichnis]`,
`scripts\build_android_rust.bat [--debug] [--abi arm64-v8a,x86_64]`).

Bauzeit: Der Modellschritt kehrt sofort zurück, wenn die Dateien da sind
(`--verify` prüft die Prüfsummen neu). Der Rust-Schritt ist inkrementell; er
dauert nur Minuten, wenn sich eine Rust-Quelle geändert hat, weil das
Release-Profil mit LTO linkt. `--no-rust` überspringt ihn, wenn sich nur
Dart/Kotlin geändert hat. Der Flutter-Release-Build (Dart AOT + Gradle) ist
der langsame Teil; für die tägliche Arbeit `--run` nehmen, ein Debug-Build mit
Hot Reload, und die Release-APK nur zum Installieren bauen.

### Kommandozeilenwerkzeug (Testdaten, Fehlersuche, Auszugstext, E-Bons)

```bash
cd rust/receipt_ocr && cargo build --release
```

```bash
rust/receipt_ocr/target/release/receipt-ocr \
  --models /pfad/zu/models --ort-lib /pfad/zu/libonnxruntime.so \
  --pretty --out-dir samples/golden samples/receipts/*.webp samples/receipts/*.png
```

```bash
rust/receipt_ocr/target/release/receipt-ocr --pdf-text Kontoauszug.pdf
```

```bash
rust/receipt_ocr/target/release/receipt-ocr --pdf-lines ebon.pdf --pretty > samples/golden/ebon.ocr.json
```

`--pdf-text` gibt einen Auszug so aus, wie der Import der App ihn sieht (eine
gedruckte Zeile pro Zeile, Spalten durch zwei Leerzeichen getrennt);
`--pdf-lines` gibt die Textebene eines PDFs im JSON-Format des Scans aus
(Zeilen mit Rahmen), so kommt ein digitaler Beleg zum Beleg-Parser und so
entsteht seine Testdatei. Keines von beiden braucht ein Modell. `--models` ist
ein beliebiges Verzeichnis mit den vier Dateien aus `download_models.sh`; eine
`libonnxruntime.so` für den Rechner ist z. B. `onnxruntime/capi/libonnxruntime.so.*`
aus dem PyPI-Paket `onnxruntime` (`onnxruntime.dll` unter Windows).

## Veröffentlichung (Google Play)

Einmal `scripts\make_keystore.bat` (Upload-Schlüssel +
`app\android\key.properties`, beide außerhalb von git), dann
`scripts\build_android.bat --bundle` für die `.aab`. Der Versionscode ist die
Anzahl der Commits des Branches, der Versionsname kommt aus `pubspec.yaml`.
Die Schritte in der Play Console, die Antworten zur Datensicherheit und der
Ablauf für interne Tests stehen in [docs/release.md](docs/release.md); die
Datenschutzerklärung, auf die der Eintrag verlinkt, ist
[docs/privacy.md](docs/privacy.md). Ohne `key.properties` nutzen Release-Builds
weiter den Debug-Schlüssel, wie bisher.

## Warum Detektor + Erkenner und nicht die ganze docling-Pipeline

Die Bild-Pipeline von docling.rs macht eine Layout-Analyse (RT-DETR, 65 MB
int8) und fasst Text zu Layout-Bereichen zusammen. Ein Beleg-Parser braucht das
Gegenteil: einen Rahmen pro gedruckter Zeile mit seiner Lage, damit sich
Zeilen „Name … Preis“ wieder aufbauen lassen. Die Crate ruft deshalb
`docling_pdf::ocr_det::DetModel` + `docling_pdf::OcrModel` direkt auf, wofür nur
`ocr_det.onnx` + `ocr_rec_v6.onnx` (+ optional `ocr_textline_ori.onnx`) nötig
sind. Dasselbe gilt für Auszüge: Der Absatz-Export der Textebene liest einen
Auszug Spalte für Spalte, deshalb nimmt die Crate die Zeilenzellen des Parsers
mit ihrer Position (`docling_pdf::textparse::pdf_textlines`) und gruppiert sie
nach der Höhe zu gedruckten Zeilen.

ONNX Runtime wird beim Bauen **nicht** gelinkt: Die Crate nutzt `load-dynamic`
von `ort` und lädt `libonnxruntime.so` mit `dlopen`. Auf Android kommt diese
Bibliothek aus dem AAR `com.microsoft.onnxruntime:onnxruntime-android`, das
Gradle mitpackt (angegeben in `app/android/app/build.gradle.kts`); auf einem
Rechner geht jede libonnxruntime ≥ 1.17.

## Tests und Regression

* `app/test/budget_file_test.dart`: xlsx lesen (Kategorien, Einstellungen,
  Buchungen, Eingaben der Übersicht), Anhängen innerhalb und jenseits der
  vorformatierten Zeilen, Änderungen an Eingaben, Plan und Einstellungen, und
  die Garantie, dass sich in der ZIP-Datei nur das berührte Blatt (und
  `workbook.xml`) ändert. Läuft gegen die erzeugte Testdatei und ihre in
  LibreOffice neu gespeicherte Kopie. Außerdem die Vorschläge
  (Schnellbuchungen, Autovervollständigung, gelernte Kategorien).
* `app/test/budget_service_test.dart`: Warteschlange + Abgleich mit einem
  nachgebildeten Ordner, auch offline, nach einem Neustart und beim direkten
  Schreiben von Eingaben der Übersicht.
* `app/test/budget_template_test.dart`: jede mitgelieferte Vorlage durch
  denselben Code gelesen (Kategorien, Typen, Limits, Eingabe- und Planzeilen),
  beschrieben (Buchungen, Limits, Eingaben, Plan, neues Jahr) und der Weg des
  leeren Ordners (Vorlage in App- oder Systemsprache, einmal pro Ordner
  versucht, Kopie, sobald eine Datei existiert); Änderungen an Kategorien
  (Symbol und Farbe in Spalte `E`, Umbenennung bis in Buchungen,
  Beschriftungen der Übersicht, zitierende Formeln und das bedingte Format)
  und die Übersetzung der Datei gegen die englische Vorlage und gegen eine
  Testdatei wie die eines Nutzers. Nach Änderungen an `tools/budget_template.py`
  mit `python3 tools/budget_template.py` neu erzeugen (braucht openpyxl; es
  schreibt auch `app/lib/budget/template_texts.dart` neu, das Wörterbuch der
  Übersetzung) und mit einer Neuberechnung in LibreOffice prüfen, dass keine
  Zelle einen Fehler zeigt. LibreOffice vertraut zwischengespeicherten Werten
  in einer xlsx, eine neu geschriebene Formel wird daher ohne einen solchen
  gespeichert.
* `app/test/statement_import_test.dart`: Vertrag für Prompt und JSON-Schema,
  erzwungene Vorzeichen, unbekannte Kategorien, Duplikaterkennung.
* `app/test/receipt_parser_test.dart` und `units_test.dart`: der Beleg-Parser
  gegen jede Testdatei in `samples/golden` (Fotos, dazu `billa_ebon`, ein
  synthetischer digitaler Beleg als PDF, gelesen mit
  `receipt-ocr --pdf-lines`, bei dem Mengenzeilen über ihrer Position stehen),
  Geldbeträge lesen, Zeilen gruppieren, RKSV-QR, Kategorisierung.
* `app/test/calendar_view_test.dart` und `entry_form_validation_test.dart`:
  Kalenderansicht (Tageswerte, Einnahmen/Ausgaben/Saldo wie in der Übersicht,
  360 dp breite Handys) und die Hinweise des Buchungsformulars an den Feldern.
* `app/test/share_receiver_test.dart`: die Warteschlange geteilter Dateien.
* `cargo test` in `rust/receipt_ocr` deckt den Vertrag der C-ABI ab.

```bash
cd app && flutter analyze && flutter test
```

```bash
cd rust/receipt_ocr && cargo fmt --check && cargo clippy --all-targets && cargo test --release
```

Die docling.rs-Abhängigkeit ist in `rust/receipt_ocr/Cargo.toml` auf einen
Commit festgelegt. Ein Update kann die OCR-Ausgabe ändern; die Testdateien mit
dem Kommandozeilenwerkzeug neu erzeugen und die Dart-Tests laufen lassen, um
zu sehen, was sich bewegt hat, bevor die neuen Testdateien committet werden.

## Wie Belege gelesen werden

1. **Zeilen.** Die Rahmen des Detektors werden nach ihrer vertikalen Mitte zu
   gedruckten Zeilen gruppiert (`ocr_rows.dart`); das Fragment ganz rechts ist
   der Platz der Preise.
2. **Zuerst der QR-Code.** Österreichische RKSV-Codes (`_R1-AT1_…`) liefern den
   genauen Zeitpunkt, den Bruttobetrag je Steuersatz und die Kassen- und
   Belegnummern; die OCR ergänzt nur Händler und Positionen. Das Dekodieren
   geschieht rein in Rust (`rqrr`) auf dem Foto in voller Auflösung.
3. **Wörterbücher, zuerst Deutsch.** Summenzeilen (`SUMME`, `TOTAL`, `Gesamt`,
   `zu zahlen`…), Zeilen ohne Position (`MwSt`, `Netto`, `Bar`, `Rückgeld`,
   Zeilen des Kartenterminals…), Vorrang beim Datum, Zahlungsart
   (Kartenbegriffe schlagen Bargeldbegriffe), Steuertabellen per Rechnung
   aufgelöst (netto + MwSt = brutto).
4. **Positionen.** Zeilen zwischen Kopf und Summe mit einem Preis am rechten
   Rand; mehrzeilige Positionen, Mengenzeilen (`= 2 x 1,89`) und OCR-Fehler
   werden ausdrücklich behandelt und sind von den Testdateien abgedeckt.
5. **Kategorie.** Zuerst die eigene Historie der Datei für den Händler
   (`EntrySuggestions.categoryFor`), dann das eingebaute Händlerverzeichnis
   (`merchants.dart`), abgebildet auf die Kategorienamen der Datei, dann die
   meistgenutzte Ausgabekategorie; im Buchungsformular bestätigst du in jedem
   Fall.

## Bekannte Grenzen

* Nur Android: keine offizielle iOS-Version (Apple hat das Entwicklerkonto
  wegen der belarussischen Staatsbürgerschaft gesperrt, siehe oben). Der Code
  ist Flutter, aber die Ordner-Brücke (Storage Access Framework) und der Build
  der OCR-Bibliothek gibt es nur für Android. iCloud Drive funktioniert nur
  dort, wo es Apples Android-Client gibt; Dropbox und Google Drive stellen
  ihre Ordner über ihre Android-Apps bereit.
* Ein Kontoauszug, der ein gescanntes Bild ist (keine Textebene), wird als leer
  gemeldet; dann die Seite fotografieren (Weg über den Screenshot).
* Die fünf Beispielfotos sind Vorschaubilder, deren QR-Codes zu klein zum
  Dekodieren sind; Handyfotos in voller Auflösung werden dekodiert.
  Standardmäßig wird nur `arm64-v8a` gebaut.

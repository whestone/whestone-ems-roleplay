# Whestone EMS – PvE-Server (LSPD + Rettungsdienst)

FiveM-Server für Einsatzkräfte-Roleplay **PvE**: Spieler sind Polizisten oder
Sanitäter und bearbeiten KI-generierte Einsätze. Kein PvP, keine Economy.
Deutsche Texte, US-Setting (Vanilla-Fahrzeuge/-Uniformen).

---

## 1. Infrastruktur

| Komponente | Ort / Zugang |
|---|---|
| Server-Daten | `E:\txData\whestoneEMS.base` |
| FXServer/txAdmin | `E:\txAdmin\FXServer.exe` (txAdmin-UI: Port 40120) |
| MariaDB (portable) | `E:\MariaDB` – Port 3306, Autostart via Startup-Ordner (VBS) |
| MariaDB manuell starten | `E:\MariaDB\start_mariadb.bat` |
| Datenbank | `whestone_ems` |
| DB-User (App) | `whestone` / `<Passwort – siehe lokale server.cfg>` |
| DB-User (root) | `root` / `<Passwort – siehe lokale server.cfg>` |

### server.cfg – wichtige Einträge
- `sv_licenseKey` steht direkt in der cfg (CFX keymaster).
- `sv_enforceGameBuild 3717` – DLC „A Safehouse in the Hills". Nötig für die
  neuen Polizeifahrzeuge (polbuffalo6, polcaracara, …). Wirkt **nur nach
  vollem Server-Neustart**; Artifact ≥ 23683 und aktuelles GTA V bei allen
  Spielern erforderlich.
- OneSync wird von txAdmin verwaltet (nicht in der cfg setzen).
- Admins per ACE: `add_ace identifier.license:<LICENSE> ws.admin allow`
  (+ `command.callout allow`). Live-Übernahme: Zeile in der Konsole ausführen.

### Restart-Workflow (txAdmin-Konsole)
- Geänderte Datei → `restart <ressource>`.
- **Neue Datei/Ressource** (fxmanifest geändert) → erst `refresh`, dann restart.
- `restart ws_core` oder `restart ox_lib` **stoppt alle abhängigen
  Ressourcen ohne Neustart** → danach `ensure` für: ox_target (nur bei
  ox_lib), ws_core, ws_police, ws_dispatch, ws_tablet, ws_traffic, ws_ems.
- Gamebuild-/cfg-Änderungen → voller Server-Neustart über txAdmin.

### Angepasste Fremd-Ressourcen (nach ox_lib-Update erneut patchen!)
- `ox_lib/resource/settings.lua`: Notification-Standardposition
  `top-right` → `top` (oben mittig). Spieler-Override via `/ox_lib`.
- `ox_lib/resource/interface/client/notify.lua`: Standard-Anzeigedauer
  auf 8000 ms erhöht (`data.duration = data.duration or 8000`).

---

## 2. Datenbank

Tabelle `players` (Schema: `sql/schema.sql`, Migrationen inkl.
`sql/migrate_jobdata.sql`):

- `license` (eindeutig), `name`, `job` (aktive Fraktion), `stats` (JSON),
  `position` (JSON, wird gespeichert, aber Spawn ist immer Job-Station).
- **`jobdata` (JSON) = Wahrheit je Laufbahn**: pro Job eigener
  `rank`, `xp`, `skillpoints`, `skills`. Die flachen Spalten
  `rank/xp/skills/skillpoints` spiegeln nur die aktive Laufbahn (Legacy).

---

## 3. Fraktionen & Progression (ws_core)

- **Fraktions-Auswahl** beim Verbinden: Vollbild-NUI (`html/jobselect.html`)
  mit zwei Karten (LSPD/EMS) inkl. Laufbahn-Stand; Schnellwahl Tasten 1/2.
  Wechsel jederzeit per `/dienst`. Erscheint erst NACH dem Laden (ein Dialog
  während „Awaiting Scripts" würde den Beitritt blockieren!).
- **Getrennte Laufbahnen**: Rang, XP, Skillpunkte, Skills je Fraktion.
  Beförderung automatisch bei XP-Schwelle; jede Beförderung = 1 Skillpunkt.
- **Ränge LSPD**: Polizeianwärter → Officer → Senior Officer → Sergeant →
  Lieutenant → Captain → Chief of Police (0/300/1000/2500/6000/12000/25000 XP).
- **Ränge EMS**: Praktikant → Rettungssanitäter → Notfallsanitäter →
  Senior Paramedic → Notarzt → Ärztlicher Leiter → Klinikdirektor (gleiche XP).
- **Skills** (max. Stufe 3, Verteilung im Tablet):
  - LSPD: 🔫 Waffen (SMG/Pumpgun/Marksman) · 🚓 Fahrzeuge (Tuning; Stufe 3
    zusätzlich schusssichere Reifen) · 🏃 Ausdauer · 🚔 Unterstützung
    (schaltet die F7-Verstärkung frei und stuft sie auf: 1 Stanier + Pistolen,
    2 Interceptor + MPs, 3 Riot + NOOSE mit Sturmgewehren; ohne Skill keine
    Verstärkung). Beamten-Anzahl je Stufe konfigurierbar (Standard 2:
    `WSPolice.Backup.Tiers[n].officers`). Im Tablet → **Leitstelle** wählt jeder
    Beamte, welche freigeschaltete Stufe F7 ruft (Standard: höchste).
  - EMS: 🩺 Medizin (15 %/Stufe schnellere Behandlung, ab St. 2 ein
    Extra-Reanimationsversuch) · 🚑 Fahrzeuge (Tuning; Stufe 3 schusssichere
    Reifen) · 🏃 Ausdauer
- **PvE-Regeln** (client): kein Wanted-Level (komplett unterdrückt), keine
  KI-Polizei, Gangs neutral, Friendly Fire aus, Waffen fallen nie zu Boden,
  alle Türen des Türsystems entriegelt (`WSConfig.UnlockAllDoors`).
- **Tod**: Handlungsunfähig-Screen mit Countdown (siehe Downed-System) →
  danach sofortiger Respawn am Pillbox (Zivil, ohne Waffen) – ohne
  Wasted-Overlay und ohne Schwarzblende. Aktiver Einsatz endet beim Tod
  des Einsatzleiters.
- **Krankenhaus-Roller**: 14 Faggios am Pillbox (Reihe konfigurierbar),
  automatisches Nachfüllen; weggefahrene despawnen 10 min nach Verlassen.

---

## 4. Polizei (ws_police, ws_dispatch, ws_traffic)

### Station Mission Row (Koordinaten: `ws_police/config.lua`)
- **Umkleide**: Uniformliste nach Rang (Streife, Sheriff, Highway, Ranger,
  Detective ab 3, SWAT ab 4), zufällige Modell-Varianten.
- **Waffenkammer**: „Komplett ausrüsten" (alles Verfügbare + Weste),
  Standard-Loadout, Gewehrschrank (ab Sergeant), Skill-Waffen.
- **Garage**: 13 Fahrzeuge rangbeschränkt (Stanier → … → SWAT Riot,
  Gefangenenbus, Coquette Pursuit). Nicht vorhandene Modelle werden
  ausgegraut (Gamebuild!). Tuning gemäß Fahrzeug-Skill, Spieler wird
  direkt reingesetzt.

### Einsätze (ws_dispatch)
- Auto-Generierung solange Officer im Dienst (Intervall/Limit in config),
  5 Typen × 12–15 Orte, nie derselbe Ort zweimal in Folge, zufällige
  Täterzahl/Fahrzeuge/Verletzte je Szenario.
- Typen/IDs: `traffic_accident`, `shoplifting`, `brawl`, `vehicle_theft`,
  `armed_robbery`.
- **Festnahme-Loop**: stellen (Taser/Nähe → Kapitulation) → Festnehmen →
  Durchsuchen (Zufallsfunde + XP) → Eskortieren (X = loslassen) → ins
  Fahrzeug (übers Fahrzeug anvisieren!) → blauer Marker an der
  Gefangenenübergabe (nur mit Gefangenem sichtbar) → Einliefern (+25 XP)
  **oder** Gefangenentransport rufen (+15 XP, NPC-Van mit Sonderrechten).
- **XP-Quote**: Einsatz-XP skaliert mit Festnahmequote
  (`WSDispatch.MinXPFactor` = 40 % bei null Festnahmen) – Festnehmen lohnt
  sich mehr als Erschießen.
- Verdächtige rot auf der Karte; Ziele selbstheilend (abgeschlepptes Wrack
  am Haken = erledigt, weggelaufene Verletzte geben frei).

### Werkzeuge
- **Anhaltezeichen (U)**: anvisiertes Fahrzeug fährt rechts ran und bleibt
  (eingefroren) stehen, bis Kontrolle übernommen wird oder Officer sich
  >60 m entfernt. Fußgänger bleiben stehen. Verdächtige/Flüchtende
  ignorieren es.
- **Verkehrskontrolle** (am stehenden Auto): Papiere/Führerschein,
  Alkoholtest, Fahrzeug durchsuchen, aussteigen lassen, Verwarnung (+8 XP),
  Bußgeld (+25 XP, nur bei echtem Verstoß), Festnahme (voller
  Abführungs-Loop) – 40 % Fluchtrisiko → Verfolgungsjagd mit rotem Blip.
  Kontrolle am ausgestiegenen Fahrer fortsetzbar.
- **Ausrüstung (F6)**: Leitkegel, Absperrgitter, Reifenkrallen
  (zerstören Reifen), „alles einsammeln".
- **Verstärkung (F7, Toggle)**: KI-Streife rückt an, bekämpft feindliche
  Verdächtige, F7 erneut = abziehen. 60 s Cooldown.
- **Abschleppdienst** (jedes Fahrzeug): echter Towtruck mit Gelblicht fährt
  an, lädt auf, fährt weg. Bis zu 3 parallel. Callout-Wracks zählen als
  erledigt, sobald am Haken.
- **Alkoholtest** an Zivilisten (Flavor).
- **Blaulicht L / Sirene K** getrennt, synchronisiert (alle Einsatzfahrzeuge).

---

## 5. Rettungsdienst (ws_ems)

### Station Pillbox Medical (Koordinaten: `ws_ems/config.lua`)
- Umkleide (Sanitäter, Notarzt ab Rang 4), Notfallrucksack (Selbstheilung +
  Weste), Garage (RTW, Lifeguard SUV ab Rang 1; Tuning nach Fahrzeug-Skill).

### Helipad (Pillbox-Dach)
- **Helikopterausgabe** auf dem Dach: Air Ambulance (`polmav`, Livery 1)
  ab Rang 2; Rückgabe an Garage ODER Helipad (`WSEms.Helicopters`).
- **Patientenabgabe** auch auf dem Dach möglich (zweiter Abgabepunkt,
  gleicher roter Marker/XP wie Notaufnahme).
- **Aufzug** Dach ↔ Erdgeschoss (per Alt-Interaktion, gestützte Patienten
  fahren mit). Alle Punkte in `ws_ems/config.lua` → `WSEms.Helipad`.
- Patienten lassen sich in RTW **und** Heli laden (Fahrzeugklassen 18/15).

### Notfälle
- Auto-Generierung für Sanitäter im Dienst; Typen/IDs: `cardiac`,
  `overdose`, `fall`, `traffic`, `allergic`, `workplace`, `drowning`
  (Daten: `ws_ems/shared/emergencies.lua`).
- Roter Punkt-Blip + Route wie bei LSPD-Einsätzen.
- **Verkehrsunfälle** spawnen zufällig **1–3 Verletzte** (je mit Unfallwrack,
  `maxPatients` im Notfalltyp). Der Einsatz gilt erst als abgeschlossen, wenn
  **alle** Patienten versorgt und abtransportiert sind.

### Behandlungs-Loop
1. **Untersuchen** → Diagnose mit Vitalwerten (Puls/Atmung) → +10 XP.
2. Je nach Zustand: **Reanimieren** (Defi-Minispiel `WSEms.Defi`: 3 Timing-
   Treffer in Folge nötig, jede Runde schneller; 3 Fehlversuche = Patient
   stirbt) · **Stabilisieren** · **Wunde versorgen** → +40 XP.
3. Abtransport – zwei Wege:
   - **Selbst:** Stützen (X = loslassen) → in RTW laden (übers Fahrzeug!) →
     roter Marker an der Notaufnahme/Helipad → **Einliefern** → +60 XP.
   - **NPC-RTW rufen** (ox_target am stabilen Patienten, „RTW zum Abtransport
     rufen"): ein Rettungswagen fährt an, lädt den Patienten **und alle
     stabilen Patienten in der Nähe** ein und transportiert sie ab → +40 XP
     je Patient (analog zum Gefangenentransporter der Polizei).
   - Nach Versorgung **aller** Patienten zusätzlich der Einsatz-XP-Bonus.

### Spieler-Wiederbelebung (Downed-System)
Statt sofort zu sterben, geht ein Spieler **zu Boden** und blutet aus —
konfigurierbar in `ws_core/shared/config.lua` → `WSConfig.Downed`.

- **Am Boden**: grafische Vollbild-Oberfläche (NUI) mit Countdown
  (Standard 5 Minuten) und zwei Schaltflächen — **„Auf Hilfe warten"**
  und **„Aufgeben"** (erst nach 30 s freigeschaltet, zeigt bis dahin die
  Restsperre). Nach „Warten" wird der Mauszeiger freigegeben: das Overlay
  läuft weiter, der Spieler kann sich umsehen — **Taste G** holt die
  Auswahl zurück. Bewegung/Waffen gesperrt, unverwundbar. Behandelt ein
  Sanitäter, wechselt die Anzeige auf „Ein Sanitäter versorgt dich".
- **Notruf wie ein NPC-Einsatz**: Der Hilferuf läuft durch dieselbe
  Notfall-Engine (Typ `player_rescue`) — Angebot an alle Sanitäter,
  Annahme mit **Y**, Blip + Route, Anzeige im Tablet. Anders als NPC-Rufe
  verfällt er **nicht** nach 90 s, sondern bleibt offen, solange der
  Spieler am Boden liegt; wer neu in den Dienst geht, bekommt ihn
  nachgereicht.
- **Wiederbeleben** (Sanitäter, ox_target am Spieler): Behandlungsbalken
  (Medizin-Skill verkürzt ihn) + Defi-Minispiel → Spieler steht mit 50 %
  Gesundheit wieder auf. Sanitäter bekommt **+100 XP** (Wiederbelebung)
  **+40 XP** (Einsatzabschluss) sowie die Statistiken `revives` und
  `emergencies`. Serverseitig validiert (Job, Dienst, max. 8 m Abstand).
- **Aufgeben**: Schaltfläche oder `/aufgeben` als Fallback → normaler
  Respawn am Pillbox. Gleiches gilt, wenn die Zeit abläuft.
- Deaktivieren: `WSConfig.Downed.enabled = false` → sofortiger Respawn wie
  zuvor.

---

## 6. Tablet (F5, beide Fraktionen)

- **Einsätze**: aktive Callouts/Notfälle, Annehmen/Unterstützen/Abbrechen.
- **Beamte**: alle Spieler, Rang/XP/Status/Statistik.
- **Skills**: XP-Fortschrittsbalken zum nächsten Rang, Skillpunkte
  verteilen (job-eigene Zweige).
- **Leitstelle**: Einsatz/Notfall generieren
  (`WSTablet.GenerateMinRank`, aktuell Rang 6).
- **Admin** (nur ACE `ws.admin`): je Spieler BEIDE Laufbahnen bearbeiten
  (Rang ↔ XP gekoppelt, Skillpunkte, alle Skill-Zweige) – wirkt sofort.
- Branding wechselt automatisch (LSPD Terminal / EMS Terminal).

### Fraktionsauswahl (Lobby)
Während der Auswahl steht der Spieler auf dem **Dach des Maze Bank Tower**:
eingefroren, unverwundbar und über einen **eigenen Routing-Bucket** für alle
anderen Spieler unsichtbar. Der Auswahl-Hintergrund ist halbtransparent, die
Skyline bleibt sichtbar. Nach der Wahl geht es zur Station der gewählten
Fraktion; der Bucket wird dabei automatisch zurückgesetzt (auch nach einem
Ressourcen-Neustart, damit niemand unsichtbar hängen bleibt).

---

## 6b. Soziales / Rollenspiel (`ws_social`)

Fraktionsübergreifende Downtime-Inhalte ohne Progressionsbezug:

- **Emote-Menü** (F3 / `/emotes`): selbstbestimmte Animationen (Arme
  verschränken, Anlehnen, Rauchen, Kaffee, Handy, Hände hoch …) plus
  fraktionseigene (Polizei: Streifen-Idle, Klemmbrett, Fernglas; EMS:
  Patient versorgen). Jede Bewegung oder `/stopemote` beendet das Emote.
- **`/me <Text>`** (lila) und **`/do <Text>`** (blau): schwebender
  Rollenspiel-Text über dem Kopf, für Spieler im Umkreis (`RpRange`, 20 m)
  sichtbar. Server säubert den Text (Farbcodes, Länge).
- **`/dienstzeit`**: eigene Gesamt-Dienstzeit + Top-10-Rangliste. Die
  Dienstzeit wird server­seitig als Statistik `dutyseconds` erfasst
  (persistent, alle 2 Min. gesichert).
- **Kaffeeautomat**: An jedem Kaffeeautomaten (Weltobjekt
  `prop_vend_coffe_01`) „Kaffee ziehen" per ox_target → kurze Ausgabe,
  dann trinken; stellt die Sprint-Ausdauer wieder her. Eigene Standorte
  über `WSSocial.CoffeeMachines` (Koordinaten), weitere Automaten-Modelle
  über `WSSocial.CoffeeProps`.

---

## 6c. Fahrzeug-HUD (`ws_hud`)

Tacho-Overlay für alle Fahrzeuge (fraktionsübergreifend), rechts unten:

- **Tacho**: Geschwindigkeit in km/h als Rundinstrument (grün → gelb → rot),
  Skala über `WSHud.MaxSpeedKmh`.
- **Motorstatus**: grüne/rote Anzeige; **Taste M** schaltet den Motor an/aus
  (nur als Fahrer). Bei leerem Tank springt er nicht an.
- **Blaulichtstatus**: eigene Anzeige, aktiv wenn `IsVehicleSirenOn` – nur bei
  Einsatzfahrzeugen (Klasse 18) sichtbar; blinkt bei aktivem Blaulicht.
- **Tanksystem** (optional, `WSHud.Fuel.enabled`): Füllstandsbalken; Verbrauch
  skaliert mit der Drehzahl, bei leerem Tank geht der Motor aus. Betankt wird an
  **jeder Zapfsäule** der Map (ox_target auf die Weltobjekte, keine Koordinaten
  nötig) – Fahrzeug in die Nähe stellen, Zapfsäule anvisieren → „Fahrzeug
  betanken". Sprit ist nicht persistent (frisch gespawnt = voll).

---

## 7. Tasten & Befehle

| Taste | Funktion |
|---|---|
| **Alt** | ox_target-Interaktion (halten + zielen) |
| **Y** | Einsatz/Notfall annehmen (job-abhängig) |
| **F5** | Tablet |
| **F6** | Polizei: Ausrüstungsmenü |
| **F7** | Polizei: Verstärkung rufen/wegschicken |
| **U** | Polizei: Anhaltezeichen |
| **L / K** | Blaulicht / Sirene |
| **X** | Eskorte/Patient loslassen |
| **M** | Fahrzeug: Motor an/aus |
| **F3** | Emote-Menü |
| **1 / 2** | Fraktionswahl im Auswahlbildschirm |

Alle Tasten umbelegbar: GTA-Einstellungen → Tastenbelegung → FiveM.

Befehle: `/dienst` (Fraktion wechseln), `/charinfo`, `/annehmen`,
`/abbrechen`, `/loslassen`, `/blaulicht`, `/sirene`, `/anhalten`,
`/ausruestung`, `/verstaerkung`, `/tablet`, `/patient_loslassen`,
`/notfall_annehmen`, `/notfallabbruch`, `/aufgeben` (am Boden aufgeben),
`/emotes`, `/stopemote`, `/me <Text>`, `/do <Text>`, `/dienstzeit`,
`/ox_lib` (Notification-Position).

Konsole/Admin: `/callout [id]` (Polizei), `/notfall [id]` (EMS).

---

## 8. Koordinaten anpassen

Alle Orte sind Config-Werte (`vector4(x, y, z, heading)`):
- Polizei-Station: `ws_police/config.lua`
- Gefangenenübergabe: `ws_dispatch/config.lua` (`JailDropoff`)
- Einsatzorte Polizei: `ws_dispatch/shared/callout_data.lua`
- Auswahl-Lobby (Maze Bank Tower): `ws_core/shared/config.lua`
  (`JobSelectLobby`, auf `nil` = Auswahl am normalen Spawn)
- EMS-Station/Notaufnahme: `ws_ems/config.lua`
- Notfallorte EMS: `ws_ems/shared/emergencies.lua`
- Job-Spawns/Krankenhaus-Roller: `ws_core/shared/config.lua`

---

## 9. Roadmap-Ideen

MDT/Akten, Spieler-Wiederbelebung durch Sanitäter, Trage-Prop,
Großschadenslage (mehrere Patienten), Feuerwehr als dritte Fraktion,
K9/Lufteinheit, Custom-Fahrzeuge/EUP (Addons + Lizenzen nötig).

# Whestone EMS Roleplay

Deutscher **FiveM PvE-Roleplay-Server** (txAdmin) für **Polizei + Rettungsdienst** –
kein PvP, keine Economy. Eigenes Standalone-Framework auf ox_lib-Basis (bewusst
kein Qbox/ESX/FivePD).

Vollständige Doku: **[SETUP.md](SETUP.md)**

## Überblick

| Ressource | Zweck |
|---|---|
| `ws_core` | Framework-Kern: Charaktere, Duty, Ränge, per-Job-Skills, PvE-Regeln, Downed-System, Fraktionsauswahl |
| `ws_police` | LSPD: Umkleide, Waffenkammer, Garage, Blaulicht, Anhaltezeichen, Verstärkung, Abschleppen |
| `ws_dispatch` | KI-Callout-Engine (5 Szenarien) + Festnahme-/Transport-Loop |
| `ws_traffic` | Verkehrskontrollen mit Papieren, Alkoholtest, Flucht |
| `ws_ems` | Rettungsdienst: Behandlung, Reanimation, Transport, Helipad, EMS-Notrufe |
| `ws_tablet` | F5-Tablet für beide Fraktionen (Einsätze, Skills, Leitstelle, Admin) |
| `ws_social` | Emotes, /me & /do, Dienstzeit-Rangliste, Kaffeeautomat |

## Einrichtung

1. `server.cfg.example` → **`server.cfg`** kopieren und die `<...>`-Platzhalter
   ausfüllen (CFX-Key, DB-Zugang, Admin-Identifier). Die echte `server.cfg`
   ist bewusst **nicht** im Repo (Secrets).
2. MariaDB bereitstellen, Schema aus `sql/schema.sql` einspielen.
3. Abhängigkeiten liegen unter `resources/[ox]` (oxmysql, ox_lib, ox_target) –
   **`ox_lib` ist gepatcht** (Notification-Position + Dauer, siehe SETUP.md);
   nach einem ox_lib-Update erneut anwenden.
4. Server über txAdmin starten.

## Hinweise

- Sprache der UI: Deutsch (`locales/de.json` je Ressource, `en.json` als Fallback).
- Game-Build: `sv_enforceGameBuild 3717`.
- `resources/[cfx-default]` und `resources/[ox]` sind Drittanbieter-Ressourcen,
  hier zur Reproduzierbarkeit (inkl. ox_lib-Patches) mitversioniert.

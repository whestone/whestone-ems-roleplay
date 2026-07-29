# Whestone EMS → UGREEN NAS (Docker) – Umzugsanleitung

Ziel: den FiveM-Server vom Windows-PC auf die **UGREEN DXP480T Plus** umziehen.
Zwei Container: **MariaDB** (Datenbank) + **FXServer/txAdmin**. Spielstände
(Charaktere, XP, Ränge, Jobdata) werden **vollständig migriert**.

> **Wichtig – CFX-Key nur einfach:** Derselbe `sv_licenseKey` darf nur auf
> **einer** laufenden Instanz aktiv sein. Also entweder Windows **oder** NAS
> starten, nie beide gleichzeitig. Lass den Windows-Server als Fallback
> bestehen, bis der NAS nachweislich läuft, und **stoppe ihn** vor dem NAS-Start.

---

## 0) Voraussetzungen auf dem NAS (einmalig)

1. In **UGOS Pro** → App Center → **Docker** installieren.
2. **SSH** aktivieren (Systemsteuerung → Terminal/SSH), damit du `docker`-Befehle
   ausführen kannst. Danach vom PC aus: `ssh <user>@<nas-ip>`.
3. Prüfen: `docker version` und `docker compose version` liefern Ausgaben.
4. Eine feste IP für den NAS im Router vergeben (DHCP-Reservierung) – brauchst du
   später fürs Port-Forwarding.

---

## 1) Datenbank auf Windows sichern (Dump)

Auf dem Windows-PC in **PowerShell** (portable MariaDB unter `E:\MariaDB`):

```powershell
& "E:\MariaDB\bin\mysqldump.exe" -u root -p<DB_ROOT_PW> --single-transaction --routines --triggers --default-character-set=utf8mb4 whestone_ems | Out-File -Encoding utf8 E:\whestone_ems.sql
```

Ergebnis: `E:\whestone_ems.sql`. Diese Datei nach
**`/volume1/docker/FiveM/dumps/`** auf den NAS kopieren (per SMB-Freigabe oder
`scp`).

> `--single-transaction` sichert konsistent, ohne den laufenden Betrieb zu
> sperren. Der Dump enthält **kein** `CREATE DATABASE` – die DB legt der
> MariaDB-Container selbst an.

---

## 2) Ordnerstruktur & Repo auf den NAS klonen

Alle Projektdaten liegen unter **`/volume1/docker/FiveM`**:

```
/volume1/docker/FiveM/
├── server/   <- Git-Clone (Repo-Root = txData-Basis: resources/, server.cfg, deploy/)
├── db/       <- MariaDB-Datenbankdateien
├── txData/   <- txAdmin-Daten (Admins, Einstellungen)
└── dumps/    <- SQL-Dumps (Import & Backups)
```

Per SSH auf dem NAS anlegen und klonen:

```bash
mkdir -p /volume1/docker/FiveM/{db,txData,dumps}
cd /volume1/docker/FiveM
git clone https://github.com/whestone/whestone-ems-roleplay.git server
cd server/deploy
```

Der Clone bringt `resources/` (inkl. `[ox]` mit den ox_lib-Patches),
`sql/`, `server.cfg.example` und dieses `deploy/`-Set mit. Die Bind-Mounts in
`docker-compose.yml` zeigen über `${DATA_ROOT}` (aus `.env`) genau auf diese
Ordner – nichts landet in versteckten Docker-Volumes.

---

## 3) Secrets & server.cfg setzen

**a) `.env` anlegen** (im `deploy/`-Ordner):

```bash
cp .env.example .env
nano .env
```
- `DB_ROOT_PASSWORD` / `DB_PASSWORD`: am besten identisch zum Windows-Setup
  (`<DB_ROOT_PW>` / `<DB_PW>`) lassen – dann passt die server.cfg fast unverändert.
- `FX_URL`: siehe Schritt 4.

**b) `server.cfg` auf den NAS bringen.** Die echte `server.cfg` ist (zu Recht)
nicht im Git. Kopiere die Windows-Datei `E:\txData\whestoneEMS.base\server.cfg`
in den **Repo-Root** auf dem NAS (`whestone/server.cfg`) und ändere **nur den
DB-Host** von `localhost` auf den Container-Namen `mariadb`:

```
set mysql_connection_string "mysql://whestone:<DB_PW>@mariadb:3306/whestone_ems?charset=utf8mb4"
```

Alles andere (`sv_licenseKey`, `endpoint_add_*`, `sv_enforceGameBuild 3717`,
die `ensure`-Kette, Admin-ACE) bleibt gleich.
`onesync` wird weiterhin **in txAdmin** gesetzt, nicht in der cfg.

---

## 4) FXServer Linux-Artifact wählen

Auf <https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/> einen
**empfohlenen** (grün markierten), aktuellen Build öffnen, den Link zur
`fx.tar.xz` kopieren und in `.env` als `FX_URL` eintragen. Aktuell = besser;
er muss neu genug für `sv_enforceGameBuild 3717` sein.

---

## 5) Container bauen & DB importieren

Im `deploy/`-Ordner:

```bash
# 1. Nur die DB starten, damit sie initialisiert
docker compose up -d mariadb

# 2. Warten bis "healthy"
docker compose ps

# 3. Windows-Dump einspielen
docker exec -i ws_mariadb mariadb -u root -p<DB_ROOT_PW> whestone_ems < /volume1/docker/FiveM/dumps/whestone_ems.sql

# 4. Jetzt FXServer bauen & starten
docker compose up -d --build
```

Logs live ansehen:
```bash
docker compose logs -f fxserver
```

---

## 6) txAdmin-Erstsetup

1. `docker compose logs fxserver` zeigt beim ersten Start eine **PIN**.
2. Browser: `http://<nas-ip>:40120` → PIN eingeben, Admin-Konto anlegen.
3. Deployment: **„Existing server data"** (kein Rezept). Als Datenpfad
   `/server` angeben, als Config `server.cfg`.
4. In den txAdmin-**Settings**: `onesync` wie gewünscht setzen (wie auf Windows).
5. Server über txAdmin starten. In der Live-Konsole prüfen, dass `oxmysql`
   die DB verbindet und die Ressourcen ohne Fehler laden.

---

## 7) Router: Ports freigeben

Am Router **Port-Forwarding** auf die NAS-IP einrichten:
- **30120 TCP** und **30120 UDP** (Spiel-Traffic – beides nötig).
- **40120** (txAdmin) **nicht** ins Internet freigeben – nur lokal nutzen.

Danach ist der Server unter der öffentlichen IP erreichbar. Windows-Server jetzt
dauerhaft stoppen (CFX-Key-Regel).

---

## Betrieb

- **Start/Stop:** `docker compose up -d` / `docker compose stop` (im `deploy/`-Ordner).
- **Ressourcen-Updates:** im Repo-Root `git pull`, dann in txAdmin die
  betroffene Ressource `restart` (Kern-Ressourcen: ganze `ensure`-Kette).
- **FXServer-Update:** neue `FX_URL` in `.env`, dann `docker compose up -d --build fxserver`.
- **ox_lib-Patch:** die zwei Patches liegen im Repo (`[ox]/ox_lib`) und reisen mit.
  Nach einem ox_lib-**Update** erneut patchen (Notification-Position `top`, 8 s).
- **DB-Backup:** `docker exec ws_mariadb mariadb-dump -u root -p<DB_ROOT_PW> --single-transaction whestone_ems > /volume1/docker/FiveM/dumps/backup_$(date +%F).sql` (regelmäßig, z. B. per UGOS-Aufgabenplaner). Da alles unter `/volume1/docker/FiveM` liegt, sichert ein Backup dieses einen Ordners den kompletten Server.

## Troubleshooting

- **FXServer startet nicht / proot-Fehler:** `security_opt: seccomp:unconfined`
  ist gesetzt; wenn es weiter hakt, testweise `privileged: true` am fxserver-Service.
- **DB nicht erreichbar:** Host in `server.cfg` muss `mariadb` sein (nicht
  `localhost`); beide Container im selben `ws_net`.
- **MariaDB startet nicht (Permission auf `db/`):** Das offizielle Image chownt
  den Datenordner normalerweise selbst. Falls nicht (User-Namespace-Remapping),
  einmalig `chown -R 999:999 /volume1/docker/FiveM/db` und Container neu starten.
- **txAdmin-Port belegt/anders:** Port in `docker-compose.yml` (40120) und
  `+set txAdminPort` müssen übereinstimmen.
- **Zeichensatz/Umlaute:** DB läuft auf `utf8mb4`; der Import oben behält das bei.

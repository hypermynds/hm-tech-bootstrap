# HM Tech Bootstrap

Pacchetto macOS per completare automaticamente il modello **HM Tech** dopo
l'installazione del pacchetto ufficiale Homebrew.

## Software installato

- rig (`r-rig`) per installare e gestire R 4.6.1 dal pacchetto CRAN ufficiale
- RStudio tramite cask `rstudio`
- Visual Studio Code tramite cask `visual-studio-code`
- Docker Desktop tramite cask `docker-desktop`
- Cyberduck tramite cask `cyberduck`

Slack, Bitwarden e WireGuard non sono inclusi perché vengono distribuiti dal
modello HM People.

## Come funziona

Il pacchetto installa:

- `/Library/Hypermynds/HMTech/Brewfile`
- `/Library/Hypermynds/HMTech/bootstrap.sh`
- `/Library/LaunchDaemons/com.hypermynds.hmtech.bootstrap.plist`

Il LaunchDaemon viene avviato ogni cinque minuti finché:

1. esiste un utente collegato alla console;
2. Homebrew è disponibile;
3. `brew bundle` termina correttamente.

Homebrew viene eseguito come utente della console tramite il comando ufficiale
`brew as-console-user`, pensato per i flussi MDM. Dopo `brew bundle`, lo script
usa `rig` come root per installare R 4.6.1 dal pacchetto CRAN corretto per
l'architettura del Mac, impostarlo come predefinito e predisporre le librerie R
per utente. La versione è fissata intenzionalmente: Mac configurati in momenti
diversi ricevono la stessa baseline. Al
completamento viene creato `/Library/Hypermynds/HMTech/.completed` e i successivi
avvii terminano senza effettuare modifiche.

## Requisiti

- macOS 14 o successivo
- Mac Apple Silicon oppure Intel supportato da Homebrew
- certificato `Installer Certificate (Hypermynds)` presente nel Portachiavi
- profilo MDM `HM Package Signing 2026` installato sui Mac destinatari
- Homebrew distribuito tramite il pacchetto ufficiale
- utente della console amministratore locale durante il bootstrap iniziale

## Costruzione del pacchetto

Sul Mac che contiene l'identità `Installer Certificate (Hypermynds)`:

```bash
cd hm-tech-bootstrap
./build.sh 1.0.0
```

Il risultato sarà:

```text
dist/hm-tech-bootstrap-1.0.0.pkg
```

Lo script mostra anche firma e hash SHA-256.

## Registrazione in Apple Business

Il repository consigliato è pubblico, per esempio
`Hypermynds/hm-tech-bootstrap`. Il repository contiene solo sorgenti e non deve
mai contenere certificati privati o chiavi di firma.

Pubblicare il `.pkg` come asset di una release GitHub pubblica, con URL HTTPS
diretto e versionato:

```text
https://github.com/Hypermynds/hm-tech-bootstrap/releases/download/v1.0.0/hm-tech-bootstrap-1.0.0.pkg
```

Creare poi un pacchetto macOS con:

- Nome: `HM Tech Bootstrap`
- Bundle ID: `com.hypermynds.hmtech.bootstrap`
- Versione: `1.0.0`
- Hash: il valore mostrato da `build.sh`

Aggiungere il pacchetto al modello HM Tech. Il bootstrap può essere consegnato
prima di Homebrew: il LaunchDaemon attende e riprova automaticamente.

## Verifica sul Mac pilota

```bash
sudo tail -f /var/log/hypermynds-hmtech-bootstrap.log
```

Al termine:

```bash
rig list
R --version | head -1
test -d "/Applications/RStudio.app" && echo "RStudio OK"
test -d "/Applications/Visual Studio Code.app" && echo "VS Code OK"
test -d "/Applications/Docker.app" && echo "Docker OK"
test -d "/Applications/Cyberduck.app" && echo "Cyberduck OK"
```

Per verificare il receipt del pacchetto:

```bash
pkgutil --pkg-info com.hypermynds.hmtech.bootstrap
```

## Aggiornamenti

`brew bundle --no-upgrade` installa ciò che manca senza aggiornare
automaticamente le applicazioni già presenti. `rig` installa la versione R
indicata da `R_VERSION` nello script e permette in futuro di affiancare o
cambiare versione senza sostituire manualmente R.framework. Le dipendenze R dei
singoli progetti vanno versionate con `renv`, non aggiunte globalmente al
pacchetto. Per
modificare la dotazione:

1. aggiornare `payload/Library/Hypermynds/HMTech/Brewfile`;
2. incrementare la versione del pacchetto;
3. ricostruire, pubblicare con un nuovo URL e aggiornare Apple Business.

Il certificato Installer locale scade dopo un anno. Prima della scadenza va
rinnovato e questo pacchetto deve essere firmato nuovamente se è ancora in
distribuzione.

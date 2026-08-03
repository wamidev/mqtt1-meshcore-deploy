# Nasazení MeshCore MQTT uzlu

Tento repozitář obsahuje pouze soubory potřebné k nasazení jednoho MQTT uzlu.
Stejný postup použijte pro `mqtt1.meshcore.cz` i `mqtt2.meshcore.website`;
jednotlivé servery se liší pouze souborem `.env` a TLS certifikátem.

## Co se na server nainstaluje

Docker Compose spustí tři služby:

- `mosquitto` – lokální MQTT broker,
- `nginx` – veřejný HTTPS/WSS endpoint `/mqtt`,
- `dedup-worker` – čte raw data z obou brokerů a publikuje lokální
  `meshcore/feed/#`.

Z internetu jsou vystavené pouze porty `80` a `443`. MQTT porty `1883` a `9001`
zůstávají uvnitř Docker sítě.

## 1. Příprava před instalací

Připravte:

- čistý podporovaný Ubuntu Server,
- účet s oprávněním `sudo`,
- DNS záznam domény směřující na veřejnou IP serveru,
- povolené příchozí porty TCP `80` a `443`,
- TLS certifikát a privátní klíč pro danou doménu,
- hesla MQTT účtů pro oba brokery.

Pro první uzel použijte:

```text
mqtt1.meshcore.cz → veřejná IP Yomama serveru
```

Pro druhý uzel:

```text
mqtt2.meshcore.website → veřejná IP MirekOva serveru
```

Pokud používáte Cloudflare proxy, nastavte DNS záznam jako `Proxied` a režim
šifrování na `SSL/TLS → Full (strict)`. Nevystavujte přes Cloudflare porty
`1883` nebo `8883`; veřejné MQTT připojení používá WSS na portu `443`.

## 2. Stažení deployment repozitáře

Přihlaste se na server a spusťte:

```sh
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/mesh-cz/meshcore-mqtt-stack-deploy.git
cd meshcore-mqtt-stack-deploy
```

## 3. Instalace Dockeru

Instalační skript je určený pouze pro Ubuntu:

```sh
sudo ./scripts/install-docker-ubuntu.sh
```

Povolte přihlášenému uživateli spouštět Docker bez `sudo`:

```sh
sudo usermod -aG docker "$USER"
```

Potom se odhlaste ze SSH a znovu přihlaste. Ověřte instalaci:

```sh
docker --version
docker compose version
docker run --rm hello-world
```

## 4. Vytvoření konfigurace `.env`

Vytvořte lokální konfiguraci:

```sh
cp .env.example .env
nano .env
```

Soubor `.env` je ignorovaný Gitem a nesmí se commitovat.

### Nastavení uzlu `mqtt1`

```env
COMPOSE_PROJECT_NAME=meshcore-mqtt1
PUBLIC_DOMAIN=mqtt1.meshcore.cz
MQTT_CLIENT_ID_PREFIX=meshcore-dedup-mqtt1
```

### Nastavení uzlu `mqtt2`

```env
COMPOSE_PROJECT_NAME=meshcore-mqtt2
PUBLIC_DOMAIN=mqtt2.meshcore.website
MQTT_CLIENT_ID_PREFIX=meshcore-dedup-mqtt2
```

Na obou uzlech ponechte oba zdroje:

```env
MQTT_SOURCE_1_URL=wss://mqtt1.meshcore.cz/mqtt
MQTT_SOURCE_2_URL=wss://mqtt2.meshcore.website/mqtt
MQTT_INPUT_TOPIC=meshcore/raw/#
MQTT_OUTPUT_PREFIX=meshcore/feed
```

### Nastavení hesel

Nahraďte všechny hodnoty začínající `CHANGE_ME`. Pro generování hesel lze
použít například:

```sh
openssl rand -base64 32
```

Význam účtů:

| Účet | Oprávnění |
| --- | --- |
| `observer` | zápis do `meshcore/raw/#` |
| `dedup-reader` | čtení z `meshcore/raw/#` |
| `dedup-writer` | zápis do `meshcore/feed/#` |
| `corescope-ro` | čtení z `meshcore/feed/#` |
| `map-ro` | čtení z `meshcore/feed/#` |

Na každém serveru musí platit:

```text
MQTT_LOCAL_DEDUP_READER_PASSWORD = DEDUP_READER_PASSWORD
MQTT_TARGET_PASSWORD             = DEDUP_WRITER_PASSWORD
```

Přihlašovací údaje `MQTT_SOURCE_1_*` musí odpovídat účtu `dedup-reader` na
`mqtt1`; údaje `MQTT_SOURCE_2_*` musí odpovídat stejnému účtu na `mqtt2`.
Proto musí mít dedup-worker na obou serverech k dispozici hesla obou brokerů.

Doporučené oprávnění souboru:

```sh
chmod 600 .env
```

## 5. TLS certifikát

Vytvořte lokální adresář:

```sh
mkdir -p secrets/nginx
chmod 700 secrets secrets/nginx
```

Do něj vložte certifikát a privátní klíč pod přesnými názvy:

```text
secrets/nginx/fullchain.pem
secrets/nginx/privkey.pem
```

Při použití Cloudflare Origin Certificate vložte origin certifikát do
`fullchain.pem` a jeho privátní klíč do `privkey.pem`. Nastavte oprávnění:

```sh
chmod 644 secrets/nginx/fullchain.pem
chmod 600 secrets/nginx/privkey.pem
```

Tyto soubory jsou ignorované Gitem. Nikdy je neposílejte do repozitáře.

## 6. Vytvoření MQTT uživatelů

Po dokončení `.env` spusťte:

```sh
./scripts/create-mosquitto-users.sh
```

Skript vytvoří:

```text
mosquitto/config/passwd
```

a založí účty `observer`, `dedup-reader`, `dedup-writer`, `corescope-ro` a
`map-ro`. Existující soubor hesel skript z bezpečnostních důvodů nepřepíše.

## 7. Spuštění stacku

```sh
./scripts/start.sh
```

Skript před spuštěním ověří:

- existenci `.env`,
- odstranění všech hodnot `CHANGE_ME`,
- existenci MQTT password file,
- existenci TLS certifikátu a klíče,
- shodu hesel lokálního readeru a writeru,
- platnost Docker Compose konfigurace.

Potom stáhne image a spustí kontejnery. Zkontrolujte stav:

```sh
docker compose ps
```

Všechny služby by měly být `Up`; Mosquitto a Nginx následně také `healthy`.
Při prvním nasazení může dedup-worker dočasně restartovat, dokud nebude dostupný
druhý MQTT broker.

## 8. Ověření nasazení

Ověřte health endpoint:

```sh
curl -fsS https://mqtt1.meshcore.cz/health
```

Na druhém uzlu nahraďte doménu za `mqtt2.meshcore.website`.

Očekávaná odpověď:

```text
ok
```

Veřejný MQTT endpoint je:

```text
wss://<PUBLIC_DOMAIN>/mqtt
```

Pro kontrolu logů použijte:

```sh
docker compose logs --tail=100 mosquitto
docker compose logs --tail=100 nginx
docker compose logs --tail=100 dedup-worker
```

Živý výpis workeru:

```sh
docker compose logs -f dedup-worker
```

Každou minutu vypisuje počty přijatých, předaných a duplicitních zpráv.

## 9. Připojení klientů

Observer zapisuje přes veřejný WSS endpoint do:

```text
meshcore/raw/#
```

CoreScope nebo mapa ve stejné Docker síti používá:

```text
Broker:   ws://mosquitto:9001
Topic:    meshcore/feed/#
Username: corescope-ro nebo map-ro
```

Pokud CoreScope nebo mapa běží mimo tuto Docker síť, nepovolujte automaticky
veřejný port `1883`. Použijte veřejný WSS endpoint s read-only účtem nebo službu
připojte do stejné Docker sítě.

## 10. Aktualizace

Před aktualizací zálohujte lokální konfigurační soubory mimo klon repozitáře:

```sh
sudo install -m 600 .env /root/meshcore-mqtt.env.backup
sudo install -m 600 mosquitto/config/passwd /root/meshcore-mqtt.passwd.backup
```

Stáhněte změny a aktualizujte kontejnery:

```sh
git pull --ff-only
docker compose pull
docker compose up -d
docker compose ps
```

Zálohy uchovávejte zabezpečeně a nikdy je nekopírujte do deployment repozitáře.

## 11. Restart a zastavení

```sh
docker compose restart
docker compose stop
docker compose start
docker compose down
```

`docker compose down` odstraní kontejnery a síť, ale nesmaže bind-mounted data
Mosquitta. Nepoužívejte `down -v`, pokud přesně nevíte, jaká data odstraňujete.

## Řešení problémů

### Nginx se nespustí

Zkontrolujte názvy a oprávnění certifikátů:

```sh
ls -l secrets/nginx/fullchain.pem secrets/nginx/privkey.pem
docker compose logs nginx
```

### Mosquitto je `unhealthy`

Ověřte, že se shodují hodnoty `MQTT_LOCAL_DEDUP_READER_PASSWORD` a
`DEDUP_READER_PASSWORD`, a znovu vytvořte password file, pokud bylo heslo
změněno.

### Je potřeba změnit MQTT hesla

Nejdříve stack zastavte a původní password file bezpečně přesuňte mimo
deployment adresář. Upravte `.env`, znovu spusťte
`create-mosquitto-users.sh` a potom `start.sh`. Hesla zdrojových brokerů musíte
aktualizovat také v `.env` druhého uzlu.

### Dedup-worker se stále restartuje

```sh
docker compose logs --tail=200 dedup-worker
```

Zkontrolujte dostupnost obou URL `MQTT_SOURCE_1_URL` a `MQTT_SOURCE_2_URL`, DNS,
TLS certifikáty vzdálených brokerů a přihlašovací údaje `dedup-reader`.

### Cloudflare vrací chybu 502 nebo 525/526

- `502`: ověřte, že běží Nginx a port `443` je dostupný,
- `525/526`: ověřte origin certifikát, doménu certifikátu a režim
  `Full (strict)`,
- ověřte, že DNS záznam směřuje na správnou veřejnou IP.

## Bezpečnostní kontrola

Nikdy necommitujte ani neposílejte:

```text
.env
mosquitto/config/passwd
secrets/
*.pem
*.key
*.crt
produkční logy a data
```

Před každým commitem spusťte:

```sh
git status
```

V seznamu změn smějí být pouze veřejné deployment soubory a šablony.

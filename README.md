# Nasazení MeshCore MQTT serverů

Tento repozitář obsahuje deployment pro dva samostatné MQTT uzly. Každý uzel
používá Mosquitto, Nginx a dedup-worker, ale liší se způsobem připojení k
internetu:

| Uzel | Veřejná doména | Připojení |
| --- | --- | --- |
| `mqtt1` | `mqtt1.meshcore.cz` | veřejný nadřazený Nginx proxy před interní MQTT VM |
| `mqtt2` | `mqtt2.meshcore.website` | Cloudflare Tunnel, bez otevřených portů |

Veřejné MQTT endpointy jsou v obou případech stejného typu:

```text
wss://mqtt1.meshcore.cz/mqtt
wss://mqtt2.meshcore.website/mqtt
```

## Doporučený virtuální server

Pro každý uzel doporučujeme samostatnou VM:

```text
Operační systém: Ubuntu Server 24.04 LTS (64-bit / amd64)
RAM:             4 GB
Disk:            40 GB SSD nebo NVMe
```

Použijte serverovou variantu Ubuntu bez grafického prostředí. Konkrétní
uživatelská jména, hesla, IP adresy a tokeny do dokumentace ani Gitu nepatří.

## Společná příprava obou serverů

### 1. Aktualizace systému

```sh
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y git curl ca-certificates openssl
sudo timedatectl set-timezone Europe/Prague
```

Ověřte systém:

```sh
cat /etc/os-release
timedatectl
free -h
df -h /
```

### 2. Stažení deployment repozitáře

```sh
cd ~
git clone https://github.com/mesh-cz/meshcore-mqtt-stack-deploy.git
cd meshcore-mqtt-stack-deploy
```

### 3. Instalace Dockeru

```sh
sudo ./scripts/install-docker-ubuntu.sh
sudo usermod -aG docker "$USER"
```

Odhlaste se ze SSH a znovu se přihlaste. Potom ověřte:

```sh
docker --version
docker compose version
docker run --rm hello-world
```

## Varianta A: `mqtt1.meshcore.cz` za veřejným Nginx proxy

Datový tok:

```text
Internet → veřejný Nginx proxy → interní mqtt1 VM:80 → Nginx → Mosquitto:9001
```

### Síť a nadřazený reverse proxy

1. DNS záznam `mqtt1.meshcore.cz` směřuje na existující veřejný server s
   Nginx reverse proxy.
2. Veřejný Nginx ukončuje TLS a předává `/mqtt` i `/health` na interní IP
   MQTT VM, port `80`.
3. Veřejný proxy musí zachovat hlavičky `Upgrade` a `Connection`, aby fungoval
   WebSocket.
4. Přístup na port `80` interní MQTT VM povolte pouze z nadřazeného proxy a
   administrační sítě.
5. Porty `443`, `1883` a `9001` na MQTT VM nezveřejňujte.

Příklad částí konfigurace na veřejném Nginx proxy:

```nginx
location /mqtt {
    proxy_pass http://<MQTT1_INTERNAL_IP>:80;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;
}

location = /health {
    proxy_pass http://<MQTT1_INTERNAL_IP>:80/health;
    proxy_set_header Host $host;
}
```

Tento blok vložte do existujícího HTTPS `server` bloku pro
`mqtt1.meshcore.cz`. Hodnotu `<MQTT1_INTERNAL_IP>` nahraďte interní adresou VM.

### Konfigurace `.env`

```sh
cp .env.mqtt1.example .env
nano .env
chmod 600 .env
```

Šablona již obsahuje:

```env
DEPLOY_MODE=mqtt1-proxy
COMPOSE_PROJECT_NAME=meshcore-mqtt1
PUBLIC_DOMAIN=mqtt1.meshcore.cz
MQTT_CLIENT_ID_PREFIX=meshcore-dedup-mqtt1
```

Nahraďte všechny hodnoty `CHANGE_ME`. Význam a vazby hesel jsou popsané níže.
Na MQTT VM se neinstaluje TLS certifikát; HTTPS zajišťuje nadřazený veřejný
Nginx proxy.

## Varianta B: `mqtt2.meshcore.website` přes Cloudflare Tunnel

Datový tok:

```text
Internet → Cloudflare → odchozí Cloudflare Tunnel → Nginx:80 → Mosquitto:9001
```

Tato varianta nepotřebuje veřejnou IPv4, NAT, otevřené porty ani TLS certifikát
na serveru. Cloudflared běží jako součást Docker Compose a navazuje pouze
odchozí spojení do Cloudflare.

### Vytvoření tunelu

1. V Cloudflare dashboardu otevřete `Networking → Tunnels`.
2. Vytvořte remotely-managed tunnel, například `meshcore-mqtt2`.
3. Zvolte konektor Docker a z instalačního příkazu zkopírujte pouze hodnotu
   tokenu začínající typicky `eyJ...`.
4. Token nikam neposílejte a neukládejte do GitHubu.
5. V tunelu přidejte Published application:

```text
Subdomain: mqtt2
Domain:    meshcore.website
Type:      HTTP
Service:   http://nginx:80
```

Cloudflare automaticky zajistí veřejné HTTPS/WSS a odpovídající DNS trasu.

### Konfigurace `.env`

```sh
cp .env.mqtt2.example .env
nano .env
chmod 600 .env
```

Šablona již obsahuje:

```env
DEPLOY_MODE=mqtt2-tunnel
COMPOSE_PROJECT_NAME=meshcore-mqtt2
PUBLIC_DOMAIN=mqtt2.meshcore.website
MQTT_CLIENT_ID_PREFIX=meshcore-dedup-mqtt2
```

Vložte token tunelu a nahraďte všechny ostatní hodnoty `CHANGE_ME`:

```env
CLOUDFLARE_TUNNEL_TOKEN=PASTE_TUNNEL_TOKEN_HERE
```

Pro `mqtt2` nevytvářejte `secrets/nginx` a neotevírejte veřejné porty `80`,
`443`, `1883` ani `9001`.

## MQTT účty a hesla

Každý broker má tyto lokální účty:

| Účet | Oprávnění |
| --- | --- |
| `observer` | zápis do `meshcore/raw/#` |
| `dedup-reader` | čtení z `meshcore/raw/#` |
| `dedup-writer` | zápis do `meshcore/feed/#` |
| `corescope-ro` | čtení z `meshcore/feed/#` |
| `map-ro` | čtení z `meshcore/feed/#` |

Silná hesla můžete generovat příkazem:

```sh
openssl rand -base64 32
```

Na každém serveru musí platit:

```text
MQTT_LOCAL_DEDUP_READER_PASSWORD = DEDUP_READER_PASSWORD
MQTT_TARGET_PASSWORD             = DEDUP_WRITER_PASSWORD
```

Údaje `MQTT_SOURCE_1_*` musí odpovídat účtu `dedup-reader` na `mqtt1` a údaje
`MQTT_SOURCE_2_*` stejnému účtu na `mqtt2`. Oba dedup-workery proto potřebují
znát reader hesla obou brokerů.

Po dokončení `.env` vytvořte password file:

```sh
./scripts/create-mosquitto-users.sh
```

Skript založí `mosquitto/config/passwd` a z bezpečnostních důvodů nepřepíše již
existující soubor.

## Spuštění

Na obou serverech se používá stejný příkaz:

```sh
./scripts/start.sh
```

Skript načte `DEPLOY_MODE` a automaticky zvolí správné Compose soubory:

```text
mqtt1-proxy  → docker-compose.yml + docker-compose.mqtt1.yml
mqtt2-tunnel → docker-compose.yml + docker-compose.mqtt2.yml
```

U `mqtt2` navíc vyžaduje Cloudflare Tunnel token. Potom ověří konfiguraci,
stáhne image a spustí služby.

## Ověření

Stav služeb:

```sh
./scripts/compose.sh ps
```

Na `mqtt1` musí běžet:

```text
mosquitto, nginx, dedup-worker
```

Na `mqtt2` musí běžet:

```text
mosquitto, nginx, dedup-worker, cloudflared
```

Ověřte veřejné endpointy:

```sh
curl -fsS https://mqtt1.meshcore.cz/health
curl -fsS https://mqtt2.meshcore.website/health
```

Očekávaná odpověď je `ok`.

Logy:

```sh
./scripts/compose.sh logs --tail=100 mosquitto
./scripts/compose.sh logs --tail=100 nginx
./scripts/compose.sh logs --tail=100 dedup-worker
./scripts/compose.sh logs --tail=100 cloudflared
```

Poslední příkaz patří pouze na `mqtt2`.

## Připojení klientů

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

Pokud aplikace běží mimo Docker síť, použijte veřejný WSS endpoint s read-only
účtem. Nezveřejňujte kvůli tomu port `1883`.

## Aktualizace

Nejdříve bezpečně zálohujte `.env` a password file mimo repozitář. Potom:

```sh
git pull --ff-only
./scripts/compose.sh pull
./scripts/compose.sh up -d
./scripts/compose.sh ps
```

## Restart a zastavení

```sh
./scripts/compose.sh restart
./scripts/compose.sh stop
./scripts/compose.sh start
./scripts/compose.sh down
```

## Řešení problémů

### `mqtt1`: Nginx se nespustí

```sh
./scripts/compose.sh logs nginx
```

Ověřte, že port `80` není obsazený jinou službou. Pokud lokální Nginx běží, ale
veřejný endpoint nefunguje, zkontrolujte konfiguraci nadřazeného Nginx proxy,
interní IP adresu VM, firewall a WebSocket hlavičky.

### `mqtt2`: Cloudflare Tunnel nefunguje

```sh
./scripts/compose.sh logs cloudflared
./scripts/compose.sh logs nginx
```

Ověřte `CLOUDFLARE_TUNNEL_TOKEN` a Published application se službou přesně
`http://nginx:80`. Cloudflared a Nginx musí být ve stejné Docker síti.

### Mosquitto je `unhealthy`

Ověřte shodu `MQTT_LOCAL_DEDUP_READER_PASSWORD` a `DEDUP_READER_PASSWORD`.
Pokud jste heslo změnili, musíte bezpečně znovu vytvořit také password file.

### Dedup-worker se restartuje

```sh
./scripts/compose.sh logs --tail=200 dedup-worker
```

Zkontrolujte dostupnost obou veřejných WSS URL, DNS a přihlašovací údaje
`dedup-reader`. Při prvním nasazení může worker dočasně restartovat, dokud není
dostupný také druhý broker.

## Bezpečnost

Nikdy necommitujte ani neposílejte:

```text
.env
mosquitto/config/passwd
secrets/
Cloudflare Tunnel token
*.pem
*.key
*.crt
produkční logy a data
```

Před každým commitem spusťte `git status`. V repozitáři smějí být pouze veřejné
deployment soubory a šablony.

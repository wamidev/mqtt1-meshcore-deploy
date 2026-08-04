# Nasazení MeshCore MQTT serverů

Deployment je navržený pro dva nezávislé uzly. MQTT1 používá veřejný nadřazený
Nginx proxy, MQTT2 používá Cloudflare Tunnel.

| Uzel | Endpoint | Přístup | Token audience | Stav |
|---|---|---|---|---|
| MQTT1 | `wss://mqtt1.meshcore.cz/mqtt` | nadřazený Nginx | `mqtt1.meshcore.cz` | zatím nenasazený |
| MQTT2 | `wss://mqtt2.meshcore.website/mqtt` | Cloudflare Tunnel | `mqtt2.meshcore.website` | v provozu |

## Aktuální stav MQTT2

Stav k 4. 8. 2026:

- produkční deploy repozitář je naklonovaný přímo do
  `/opt/meshcore-mqtt-stack`;
- všechny kontejnery `public-broker`, `feed-broker`, `dedup-worker`, `nginx` a
  `cloudflared` běží;
- observeři se připojují tokenem na `wss://mqtt2.meshcore.website/mqtt` nebo na
  kořenovou WebSocket cestu `/`;
- CoreScope je připojený na `wss://mqtt2.meshcore.website/feed` jako
  `corescope-ro`, odebírá `meshcore/#` a regiony čte z nativních topiců;
- než bude nasazený nový MQTT1, používá worker jako `MQTT_SOURCE_1_URL`
  `ws://mapa.meshcore.cz:1884/`; druhým zdrojem je
  `wss://mqtt2.meshcore.website/mqtt`;
- stará data s chybným regionem `FEED` patří do databáze CoreScope, nikoli do
  Mosquitta; worker publikuje s `retain=false`.

Oba endpointy přijímají WebSocket na `/mqtt` i na `/`. Cesta `/` je nutná pro
MeshCore integraci v Home Assistantu, která ji nastavuje pevně.

Deduplikovaný read-only feed pro vzdálený CoreScope nebo mapu je dostupný na
`wss://<doména>/feed`. Vyžaduje účet `corescope-ro` nebo `map-ro` a dovoluje
odebírat pouze `meshcore/#`.

Běžný HTTP požadavek prohlížeče na `/` vrací místní identifikaci MQTT uzlu.
Nepřesměrovává na web upstream projektu. Cesty `/mqtt` a `/feed` bez WebSocket
upgrade vracejí HTTP `426`. Tyto textové odpovědi mají explicitní MIME typ
`text/plain`, aby je prohlížeč nestahoval jako soubor.

Nginx používá vlastní `default.conf`, skrývá přesnou verzi pomocí
`server_tokens off`, odmítá neočekávaný `Host` a neznámé cesty vracejí pouze
obecné `404 Not found`.

## Co na uzlu běží

- `public-broker`: veřejný WebSocket broker ověřující MeshCore Ed25519 tokeny;
- `feed-broker`: interní Mosquitto s deduplikovaným feedem;
- `dedup-worker`: čte oba veřejné brokery a zapisuje do lokálního feedu;
- `nginx`: HTTP/WebSocket proxy před `public-broker` a read-only cestou
  `/feed` interního brokeru;
- `cloudflared`: pouze na MQTT2.

Observer účet ani observer heslo se nevytváří. Každý klient podepisuje svůj
token vlastní MeshCore identitou. Statická hesla jsou pouze pro interní služby.

## Požadavky a adresáře

Doporučeno: Ubuntu Server 24.04 LTS, 4 GB RAM a 40 GB disk. Produkční deploy
repozitář, konfigurace i aplikační data jsou přímo v
`/opt/meshcore-mqtt-stack`:

```text
/opt/meshcore-mqtt-stack/.env
/opt/meshcore-mqtt-stack/public-broker/data/
/opt/meshcore-mqtt-stack/mosquitto/config/passwd
/opt/meshcore-mqtt-stack/mosquitto/data/
/opt/meshcore-mqtt-stack/mosquitto/log/
```

Interní úložiště Docker Enginu zůstává standardně v `/var/lib/docker`.

## Instalace MQTT2

```bash
cd /opt/meshcore-mqtt-stack
git pull --ff-only
cp .env.mqtt2.example .env
chmod 600 .env
```

V `.env` nastavte všechny hodnoty `CHANGE_ME`. Pevně ponechte:

```env
PUBLIC_DOMAIN=mqtt2.meshcore.website
AUTH_EXPECTED_AUDIENCE=mqtt2.meshcore.website
MQTT_INPUT_TOPIC=meshcore/#
MQTT_OUTPUT_PREFIX=meshcore
DEDUP_KEY_MODE=topic_raw
```

Cloudflare Tunnel nastavte na službu `http://nginx:80` a jeho token vložte do
`CLOUDFLARE_TUNNEL_TOKEN`.

Dočasné zapojení před nasazením MQTT1 používá:

```env
MQTT_SOURCE_1_URL=ws://mapa.meshcore.cz:1884/
MQTT_SOURCE_1_USERNAME=mapa
MQTT_SOURCE_2_URL=wss://mqtt2.meshcore.website/mqtt
MQTT_SOURCE_2_USERNAME=dedup-reader
```

Hesla zůstávají pouze v `.env`. Po spuštění MQTT1 se první URL a přihlašovací
údaje nahradí účtem `dedup-reader` nového MQTT1.

## Instalace MQTT1

```bash
cd /opt/meshcore-mqtt-stack
git pull --ff-only
cp .env.mqtt1.example .env
chmod 600 .env
```

V `.env` nastavte všechny hodnoty `CHANGE_ME`. Pevně ponechte:

```env
PUBLIC_DOMAIN=mqtt1.meshcore.cz
AUTH_EXPECTED_AUDIENCE=mqtt1.meshcore.cz
MQTT_INPUT_TOPIC=meshcore/#
MQTT_OUTPUT_PREFIX=meshcore
DEDUP_KEY_MODE=topic_raw
```

Lokální Nginx naslouchá na portu 80. Nadřazený veřejný Nginx musí proxyovat
`/mqtt` na `http://<MQTT1_INTERNAL_IP>:80/mqtt` včetně WebSocket hlaviček.
Port 80 MQTT VM povolte pouze z adresy nadřazeného proxy.

## Hesla služeb

Na obou serverech musí být známá hesla read-only účtu veřejného brokeru:

```text
MQTT_SOURCE_1_PASSWORD = heslo dedup-reader na MQTT1
MQTT_SOURCE_2_PASSWORD = heslo dedup-reader na MQTT2
```

Na MQTT1 musí navíc platit:

```text
PUBLIC_BROKER_READER_PASSWORD = MQTT_SOURCE_1_PASSWORD
```

Na MQTT2 musí platit:

```text
PUBLIC_BROKER_READER_PASSWORD = MQTT_SOURCE_2_PASSWORD
```

Pro interní feed musí platit:

```text
MQTT_LOCAL_DEDUP_READER_PASSWORD = FEED_HEALTH_PASSWORD
MQTT_TARGET_PASSWORD             = DEDUP_WRITER_PASSWORD
```

Hodnoty nesmí obsahovat dvojtečku, protože konfigurace subscriberu veřejného
brokeru používá dvojtečku jako oddělovač.

Vytvoření účtů interního Mosquitta:

```bash
./scripts/create-mosquitto-users.sh
```

Vytvoří se pouze účty `feed-health`, `dedup-writer`, `corescope-ro` a `map-ro`.
Password file musí vlastnit `root:root` s režimem `644`, protože kontejner po
startu přepne na neprivilegovaného uživatele `mosquitto`.

## Spuštění

```bash
./scripts/start.sh
./scripts/compose.sh ps
./scripts/compose.sh logs --tail=100 public-broker
./scripts/compose.sh logs --tail=100 feed-broker
./scripts/compose.sh logs --tail=100 dedup-worker
```

`start.sh` odmítne nesprávnou audience, nezměněné `CHANGE_ME` hodnoty a
neshodující se lokální hesla.

Healthcheck Nginxu posílá interně hlavičku `Host` odpovídající `PUBLIC_DOMAIN`,
aby požadavek `/health` neobsloužil výchozí server z image Nginxu.

## Nastavení observerů

Každý fyzický klient má dva aktivní observer profily:

```text
Profil MQTT1
server: mqtt1.meshcore.cz
port: 443
transport: websockets
TLS: ano
auth token: ano
token audience: mqtt1.meshcore.cz

Profil MQTT2
server: mqtt2.meshcore.website
port: 443
transport: websockets
TLS: ano
auth token: ano
token audience: mqtt2.meshcore.website
```

Oba profily mohou používat stejnou MeshCore identitu. Každý profil ale vytvoří
vlastní token s odpovídající hodnotou `aud`.

## MQTT témata a účty

```text
veřejný vstup:  meshcore/{lokace}/{public_key}/...
odběr workeru:  meshcore/#
interní výstup: meshcore/{lokace}/{public_key}/...
```

Worker zachovává původní strukturu tématu. Deduplikovaný feed je oddělený
samostatným brokerem a WebSocket cestou `/feed`, nikoli segmentem `feed` uvnitř
tématu. CoreScope tak správně vyhodnotí `{lokace}` jako region.

Režim `topic_raw` rozpoznává kopie packetu podle veřejného klíče observeru,
druhu zprávy a pole `raw`. Region a proměnlivá JSON metadata se ignorují; první
doručená kopie se předá do feedu a další se během `DEDUP_TTL_SECONDS` zahodí.
Zprávy bez platného `raw` se porovnávají přesně podle celého topicu a payloadu.

Minutové statistiky obsahují celkové hodnoty i počítadla pro `source1` a
`source2`. Pro krátkodobé hledání problému lze nastavit
`DEDUP_DIAGNOSTIC_PUBLIC_KEY` na celý veřejný klíč observeru. Za běžného provozu
ponechte tuto hodnotu prázdnou.

`dedup-reader` je read-only účet veřejných brokerů. `dedup-writer` smí zapisovat
jen `meshcore/#`; `corescope-ro` a `map-ro` jej smějí jen číst.

Příklad vzdáleného CoreScope:

```json
{
  "name": "mqtt2-deduplicated-feed",
  "broker": "wss://mqtt2.meshcore.website/feed",
  "username": "corescope-ro",
  "password": "HESLO_Z_CORESCOPE_RO_PASSWORD",
  "rejectUnauthorized": true,
  "topics": ["meshcore/#"]
}
```

## Image tokenového brokeru

Workflow `publish-meshcore-broker.yml` vytváří
`ghcr.io/mesh-cz/meshcore-mqtt-broker` z veřejného referenčního projektu
`michaelhart/meshcore-mqtt-broker`. Zdroj je v `broker-image/Dockerfile` připnutý
na konkrétní commit. Lokální patch navíc zabraňuje zapisování autentizačních
tokenů do logu. Před prvním startem musí workflow úspěšně proběhnout a
package musí být dostupný serverům.

## Záloha

Zálohujte minimálně:

```text
/opt/meshcore-mqtt-stack/.env
/opt/meshcore-mqtt-stack/mosquitto/config/passwd
/opt/meshcore-mqtt-stack/mosquitto/data/
/opt/meshcore-mqtt-stack/public-broker/data/
```

`.env` ani `passwd` neukládejte do Gitu.

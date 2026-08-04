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
- produkční verze stacku obsahuje kontejnery `public-broker`, `feed-broker`,
  `feed-proxy`, `dedup-worker`, `monitor`, `nginx` a `cloudflared`;
- monitor je dostupný na `https://monitor-mqtt2.meshcore.website` pouze přes
  Cloudflare Access; přístup vyžaduje povolený správcovský e-mail i zdrojovou
  IP adresu;
- po produkčním nasazení byly `feed-broker`, `monitor` a `nginx` ve stavu
  `healthy` a interní API potvrdilo připojení monitoru k feed-brokeru;
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
- `feed-proxy`: interní HAProxy, která předává veřejnou IP read-only WebSocket
  klienta Mosquittu pomocí PROXY protocol v2;
- `dedup-worker`: čte oba veřejné brokery a zapisuje do lokálního feedu;
- `mqtt-monitor`: ukládá agregované provozní statistiky a poskytuje interní
  administrační web;
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
/opt/meshcore-mqtt-stack/monitor/data/
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
MONITOR_DOMAIN=monitor-mqtt2.meshcore.website
MONITOR_EVENTS_ENABLED=true
MONITOR_TOPIC_PREFIX=meshcore-monitor
MONITOR_OBSERVER_IP_SOURCE=source2
MONITOR_RETENTION_DAYS=30
MONITOR_ACTIVE_WINDOW_SECONDS=180
```

Cloudflare Tunnel pro MQTT endpoint nastavte na službu `http://nginx:80` a jeho
token vložte do `CLOUDFLARE_TUNNEL_TOKEN`. Monitorovací hostname přidejte do
tunelu až po vytvoření Cloudflare Access aplikace podle části „Monitoring
MQTT2“.

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
MONITOR_MQTT_PASSWORD            = MONITOR_RO_PASSWORD
```

Hodnoty nesmí obsahovat dvojtečku, protože konfigurace subscriberu veřejného
brokeru používá dvojtečku jako oddělovač.

Vytvoření účtů interního Mosquitta:

```bash
./scripts/create-mosquitto-users.sh
```

Vytvoří se pouze účty `feed-health`, `dedup-writer`, `corescope-ro`, `map-ro` a
`monitor-ro`.
Password file musí vlastnit `root:root` s režimem `644`, protože kontejner po
startu přepne na neprivilegovaného uživatele `mosquitto`.

Na již běžícím serveru celý password file nevytvářejte znovu. Po doplnění
`MONITOR_RO_PASSWORD` do `.env` přidejte pouze nový účet:

```bash
./scripts/create-monitor-user.sh
```

## Spuštění

```bash
./scripts/start.sh
./scripts/compose.sh ps
./scripts/compose.sh logs --tail=100 public-broker
./scripts/compose.sh logs --tail=100 feed-broker
./scripts/compose.sh logs --tail=100 dedup-worker
./scripts/compose.sh logs --tail=100 monitor
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
do `meshcore/#` a interního `meshcore-monitor/#`; `corescope-ro` a `map-ro`
smějí číst pouze `meshcore/#`. Samostatný `monitor-ro` smí číst jen
`meshcore-monitor/#` a `$SYS/#`.

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

## Monitoring MQTT2

Monitorovací web běží v kontejneru `monitor` na interním portu `8080`. Port
není namapovaný na hostitele. Nginx jej zpřístupňuje pouze pod hostname:

```text
https://monitor-mqtt2.meshcore.website
```

Dashboard zobrazuje:

- spojení workeru ke `source1`, `source2` a internímu feedu;
- aktivní observery, jejich region, veřejný klíč a poslední aktivitu;
- poslední známou veřejnou IPv4/IPv6 observeru přihlášeného k lokálnímu
  tokenovému brokeru;
- počet přijatých, předaných a duplicitních zpráv po observerech a zdrojích;
- množství přenesených dat a druhy topiců;
- rozdělení duplicit na `same-source`, `cross-source` a starší neurčené záznamy;
- matici `source1/source2`, průměrnou a maximální prodlevu další kopie;
- přepínatelné statistiky přibližně za 5 minut, 1 hodinu, 24 hodin a celou
  historii; časové údaje vycházejí z pětiminutových agregací;
- značky restartů deduplikačního workeru v grafu;
- počet skutečných klientů feed-brokeru a známé relace `corescope-ro`, `map-ro`
  a interních služeb; krátké healthcheck relace účtu `feed-health` se skrývají;
- veřejnou IPv4/IPv6 klientů připojených přes read-only WebSocket `/feed`.

Připojené relace klientů zůstávají viditelné bez časového omezení. Odpojené
relace dashboard automaticky skryje 24 hodin po poslední události.

Monitor sleduje také generaci feed-brokeru podle `$SYS/broker/uptime`. Po
restartu Mosquitta označí relace z předchozího běhu jako odpojené a odstraní tak
falešně aktivní historické klienty. `dedup-worker` a veřejný read-only vstup se
při startu zpřístupní až po zdravém monitoru, který už odebírá `$SYS/#`.

Kliknutím na záhlaví observer tabulky lze řadit textové i číselné sloupce
vzestupně a sestupně, například zobrazit nejdříve observery s nejvyšším počtem
duplicit. Kliknutí na řádek otevře podrobný pohled na observer.

Význam klasifikace:

```text
same-source  první i další kopie přišly ze stejného source
cross-source první a další kopie přišly z různých source
neurčeno     záznam vznikl před nasazením klasifikace a nelze jej přesně určit
```

Read-only WebSocket provoz `/feed` vede z Nginxu přes interní `feed-proxy` na
samostatný Mosquitto listener `9002`. Nginx vždy přepíše interní hlavičku
`X-MeshCore-Client-IP`: na MQTT2 hodnotou `CF-Connecting-IP` od Cloudflare a na
MQTT1 přímo přijatou adresou `$remote_addr`. HAProxy tuto ověřenou IP nastaví
jako zdroj a předá Mosquittu pomocí PROXY protocol v2. Mosquitto ji proto zapíše
ke správnému MQTT client ID a účtu. Listener `9002` není publikovaný na hostiteli;
přímé interní služby nadále používají listener `9001` bez PROXY protocolu.
IP v dashboardu je veřejná adresa klienta bez technického portu interního proxy
spojení.

Na Cloudflare nesmí být pro MQTT2 zapnutý Managed Transform `Remove visitor IP
headers`, jinak nebude `CF-Connecting-IP` doručená Nginxu a `/feed` spojení bude
bezpečně odmítnuto. Klient musí po nasazení navázat nové spojení, aby se jeho
veřejná IP propsala do monitoru.

Veřejná IP observeru se získává odděleně přímo v tokenovém brokeru. MQTT2 Nginx
předává hlavičku `CF-Connecting-IP` jak pro `/mqtt`, tak pro kořenový WebSocket
`/`, který používá Home Assistant. Broker po úspěšném ověření tokenu vytvoří
privátní událost `$meshcore-monitor/observer/ip/{public_key}`. Číst ji smí jen
`dedup-reader`; worker na MQTT2 ji přijímá výhradně ze `source2` a lokálně ji
uloží pod `meshcore-monitor/observer/ip/{public_key}`. Údaj neprochází přes
`meshcore/#`, takže jej CoreScope, mapa ani jiné read-only služby neuvidí.

Volbu lokálního zdroje řídí `MONITOR_OBSERVER_IP_SOURCE`. MQTT2 override ji
nastavuje na `source2`, MQTT1 override na `source1`. Při změně pořadí zdrojů se
musí odpovídajícím způsobem změnit i tato hodnota.

U plánovaného MQTT1 bude `$remote_addr` bez další konfigurace představovat
adresu nadřazeného Nginxu. Až se MQTT1 nasadí, musí se důvěryhodné předání
skutečné klientské IP mezi oběma Nginx vrstvami navrhnout podle jejich síťového
zapojení; hlavička dodaná přímo veřejným klientem se nesmí slepě důvěřovat.

Monitor neukládá původní MQTT payloady, `raw` packet, tokeny, hesla ani privátní
klíče. SQLite databáze obsahuje agregované statistiky a poslední známou IP
observeru. Pětiminutové časové řady i IP neobnovené déle než 30 dnů se
standardně mažou.

Při prvním startu nové verze monitor automaticky doplní chybějící sloupce a
tabulky do existující SQLite databáze. Dosavadní celkové počty zůstanou
zachované. Starší duplicity se záměrně neodhadují a zobrazí se jako `neurčeno`.
Při prvním zpracování generace brokeru se dříve uložené aktivní relace bezpečně
uzavřou; aktuální klienti se při řízeném restartu Nginxu a workeru zaregistrují
znovu.

### Aktualizace monitoringu s existující databází

Před aktualizací je vhodné vytvořit konzistentní zálohu `monitor/data/` podle
části „Záloha“. Nová verze nevyžaduje změnu `.env` ani nové heslo:

```bash
cd /opt/meshcore-mqtt-stack
git pull --ff-only
./scripts/start.sh
./scripts/compose.sh ps -a
```

Aktualizují se image `meshcore-dedup-worker`, `meshcore-mqtt-monitor`, Mosquitto
2.1 a nová interní služba `feed-proxy`. Restart workeru vytvoří nový identifikátor
běhu a prázdnou deduplikační cache; dashboard tento okamžik označí v grafu.

Pro aktualizaci existujícího MQTT2 serveru zachovejte současnou `.env` a
doplňte do ní nové hodnoty podle `.env.mqtt2.example`. Pro
`MONITOR_MQTT_PASSWORD` a `MONITOR_RO_PASSWORD` použijte stejné nové silné
heslo. Potom:

```bash
cd /opt/meshcore-mqtt-stack
git pull --ff-only
./scripts/create-monitor-user.sh
./scripts/compose.sh config --quiet
./scripts/compose.sh restart feed-broker
./scripts/start.sh
```

Skript `create-monitor-user.sh` přidá nebo aktualizuje pouze účet `monitor-ro` a
zachová všechny existující účty. Restart feed-brokeru načte nový password file,
ACL, `$SYS` statistiky a connection log topics. Interní kontrola webu:

```bash
./scripts/compose.sh exec nginx wget -qO- \
  --header="Host: $MONITOR_DOMAIN" \
  http://127.0.0.1/api/health
```

Očekávaný výsledek je:

```json
{"status":"ok","feed_connected":true}
```

Před přidáním monitorovacího
hostname do tunelu nejprve vytvořte Cloudflare Access aplikaci. Access nesmí
chránit celý hostname `mqtt2.meshcore.website`, protože MQTT klienti neumějí
browserové přihlášení Cloudflare Access.

V Cloudflare Zero Trust zvolte `Access controls → Applications → Add an
application → Self-hosted and private → Public DNS`. Vytvořte aplikaci pouze
pro hostname `monitor-mqtt2.meshcore.website`, bez omezení na cestu.

Doporučená politika:

```text
Policy name: MQTT2 administrators
Action: Allow
Include: Emails -> konkrétní správcovské e-maily
Require: IP ranges -> povolené veřejné adresy
Session duration: 8 hours
```

IPv4 zapisujte jako `/32` a jednotlivou IPv6 jako `/128`. Pokud má být povoleno
více alternativních IPv4/IPv6 adres, vložte je jako hodnoty do stejného
pravidla `IP ranges`; nevytvářejte z nich několik samostatných `Require`
pravidel, která se vyhodnocují současně. Jako identity provider lze použít
Cloudflare One-time PIN nebo nakonfigurované SSO. `Cloudflare One Client` není
pro tento browserový dashboard potřeba.

Teprve potom v existujícím Cloudflare Tunnel přidejte další published
application route/public hostname:

```text
Hostname: monitor-mqtt2.meshcore.website
Service:  http://nginx:80
```

Pokud Cloudflare nabídne `Protect with Access`, zapněte jej, aby `cloudflared`
ověřoval Access token před předáním požadavku Nginxu.

Samostatný DNS záznam není při přidání public hostname přes dashboard obvykle
potřeba; Cloudflare jej vytvoří pro tunnel. Přístup ověřte jednou z povolené IP
a jednou například přes mobilní data, odkud musí být zamítnutý.

### Kontrola monitoringu

Po nasazení MQTT2 musí výpis obsahovat sedm běžících služeb; `feed-broker`,
`feed-proxy`, `monitor` a `nginx` mají být `healthy`:

```bash
./scripts/compose.sh ps -a
```

Příjem interních metrik a deduplikačních událostí ověříte bez výpisu hesel:

```bash
./scripts/compose.sh logs --since=5m monitor | tail -50
./scripts/compose.sh logs --since=5m feed-proxy | tail -30
./scripts/compose.sh logs --since=5m dedup-worker \
  | grep -E 'Connected|Subscribed|stats' \
  | tail -30
```

Po novém připojení CoreScope ověřte, že Mosquitto už neloguje Docker adresu
`172.18.x.x`, ale veřejnou IP klienta:

```bash
./scripts/compose.sh logs --since=5m feed-broker \
  | grep "u'corescope-ro'" \
  | tail -10
```

Dashboard nesmí zobrazovat účet `feed-health`; staré uložené healthcheck relace
jsou filtrovány automaticky a databázi není nutné mazat.

Pokud se dashboard otevře bez přihlášení, Access aplikace není správně
přiřazená k monitorovacímu hostname. HTTP `502` po úspěšném přihlášení obvykle
znamená, že neběží `monitor` nebo Nginx nemůže službu oslovit. Stav
`feed_connected:false` znamená problém spojení účtu `monitor-ro` s interním
feed-brokerem; zkontrolujte shodu `MONITOR_MQTT_PASSWORD` a
`MONITOR_RO_PASSWORD`, ACL a log služby `monitor`.

## Image tokenového brokeru

Workflow `publish-meshcore-broker.yml` vytváří
`ghcr.io/mesh-cz/meshcore-mqtt-broker` z veřejného referenčního projektu
`michaelhart/meshcore-mqtt-broker`. Zdroj je v `broker-image/Dockerfile` připnutý
na konkrétní commit. Lokální patch navíc zabraňuje zapisování autentizačních
tokenů do logu. Před prvním startem musí workflow úspěšně proběhnout a
package musí být dostupný serverům.

Workflow `publish-monitor.yml` vytváří
`ghcr.io/mesh-cz/meshcore-mqtt-monitor`. Také tento package musí být nastavený
jako veřejný, aby jej produkční server mohl stáhnout bez přihlášení do GHCR.

## Záloha

Zálohujte minimálně:

```text
/opt/meshcore-mqtt-stack/.env
/opt/meshcore-mqtt-stack/mosquitto/config/passwd
/opt/meshcore-mqtt-stack/mosquitto/data/
/opt/meshcore-mqtt-stack/public-broker/data/
/opt/meshcore-mqtt-stack/monitor/data/
```

Před kopírováním monitorovací databáze zastavte službu `monitor`, nebo použijte
SQLite online backup. Samotné kopírování souboru `monitor.db` za běhu nemusí
zahrnout data uložená ve WAL souboru.

`.env` ani `passwd` neukládejte do Gitu.

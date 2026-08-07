# Podrobná instalace a provoz MeshCore MQTT serverů

[← Zpět na stručný přehled](README.md)

Tento dokument je určený administrátorům. Obsahuje úplný postup instalace,
konfigurace, aktualizace, monitoringu, diagnostiky a zálohování MQTT1 a MQTT2.

Deployment je navržený pro dva nezávislé uzly na dvou samostatných serverech.
Oba jsou zveřejněné přes Cloudflare Tunnel.

| Uzel | Endpoint | Přístup | Token audience | Stav |
|---|---|---|---|---|
| MQTT1 | `wss://mqtt1-meshcore.node.cz/mqtt` | Cloudflare Tunnel | `mqtt1-meshcore.node.cz` | v nasazování |
| MQTT2 | `wss://mqtt2.meshcore.website/mqtt` | Cloudflare Tunnel | `mqtt2.meshcore.website` | v provozu |

## Rychlá instalace čerstvého serveru

Na čerstvém Ubuntu Serveru 24.04 LTS zvládne `scripts/bootstrap.sh` většinu
instalace sám: doinstaluje Docker, vygeneruje všechna interní servisní hesla,
zeptá se jen na to, co skutečně musí zadat člověk (Cloudflare Tunnel token,
heslo `dedup-reader` druhého uzlu, případné read-only feed účty), a stack
rovnou spustí:

```bash
git clone git@github.com:wamidev/mqtt1-meshcore-deploy.git /opt/meshcore-mqtt-stack
cd /opt/meshcore-mqtt-stack
sudo ./scripts/bootstrap.sh
```

(pro MQTT2 stejně, jen s `mqtt2-meshcore-deploy` — uzel pozná sám podle URL
remote repozitáře). Na konci vypíše veřejný SSH klíč a přesné odkazy pro dva
kroky, které musí proběhnout ručně na GitHubu: přidání read-only deploy key a
registraci self-hosted runneru (viz [Požadavky na uživatele
runneru](../README.md#požadavky-na-uživatele-runneru)). Skript je jen pro
prvotní instalaci — pokud `.env` už existuje, odmítne pokračovat, aby
nepřepsal fungující nasazení. Zbytek této kapitoly popisuje, co dělá krok za
krokem, pro ruční instalaci nebo diagnostiku.

## Aktuální stav MQTT1

Stav k 7. 8. 2026:

- server je čerstvá VM na Proxmoxu (Ubuntu Server 24.04 LTS, 4 GB RAM,
  20 GB disk), nasazená pomocí `scripts/bootstrap.sh`;
- doména je `mqtt1-meshcore.node.cz` (a monitor
  `monitor-mqtt1-meshcore.node.cz`) — původně plánovaná dvouúrovňová
  `mqtt1.meshcore.node.cz` nešla zprovoznit, protože Cloudflare Universal SSL
  zdarma pokrývá jen jednu úroveň wildcardu (`*.node.cz`), ne
  `*.meshcore.node.cz`; založení `meshcore.node.cz` jako vlastní Cloudflare
  zóny navíc není přes standardní "Add a Site" možné (přijímá jen kořenové
  domény), proto přejmenování na jednoúrovňový tvar s pomlčkou;
- stack (`public-broker`, `feed-broker`, `feed-proxy`, `dedup-worker`,
  `monitor`, `nginx`, `cloudflared`) je nasazený a běží;
- Cloudflare Access pro `monitor-mqtt1-meshcore.node.cz` je nastavený stejným
  postupem jako u MQTT2 (viz [Monitoring MQTT1 a MQTT2](#monitoring-mqtt1-a-mqtt2));
- přístup na server je kromě veřejného SSH i přes Tailscale;
- **zbývá dokončit**: registrace self-hosted GitHub Actions runneru na
  `mqtt1-meshcore-deploy` — SSH deploy key je už vygenerovaný
  (`/opt/github/.ssh/id_ed25519.pub`), čeká se na přidání do GitHubu
  (Settings → Deploy keys) a registraci runneru (Settings → Actions →
  Runners → New self-hosted runner). Do té doby se nasazuje/aktualizuje
  ručně přímo na serveru (`git pull --ff-only` + `sudo ./scripts/start.sh`).

## Aktuální stav MQTT2

Stav k 5. 8. 2026:

- produkční deploy repozitář (`mqtt2-meshcore-deploy`) je naklonovaný přímo do
  `/opt/meshcore-mqtt-stack`; nasazení nové verze na `main` provádí automaticky
  self-hosted GitHub Actions runner registrovaný na tomto repozitáři, viz
  [Publikace deploy repozitářů](../README.md#publikace-deploy-repozitářů);
- produkční verze stacku obsahuje kontejnery `public-broker`, `feed-broker`,
  `feed-proxy`, `dedup-worker`, `monitor`, `nginx` a `cloudflared`;
- monitor je dostupný na `https://monitor-mqtt2.meshcore.website` pouze přes
  Cloudflare Access; přístup vyžaduje povolený správcovský e-mail i zdrojovou
  IP adresu;
- po produkčním nasazení byly `feed-broker`, `monitor` a `nginx` ve stavu
  `healthy` a interní API potvrdilo připojení monitoru k feed-brokeru;
- observeři se připojují tokenem na `wss://mqtt2.meshcore.website/mqtt` nebo na
  kořenovou WebSocket cestu `/`;
- běžný HTTP požadavek na kořenovou cestu zobrazuje veřejnou informační stránku
  pro nastavení observerů;
- CoreScope je připojený na `wss://mqtt2.meshcore.website/feed` jako
  `corescope-ro`, odebírá `meshcore/#` a regiony čte z nativních topiců;
- než bude nasazený nový MQTT1, používá worker jako `MQTT_SOURCE_1_URL`
  `ws://mapa.meshcore.cz:1884/`; druhým zdrojem je
  `wss://mqtt2.meshcore.website/mqtt`;
- stará data s chybným regionem `FEED` patří do databáze CoreScope, nikoli do
  Mosquitta; worker publikuje s `retain=false`.

Stav k 7. 8. 2026:

- automatický deploy přes self-hosted runner na `mqtt2-meshcore-deploy` je
  plně funkční — po opravě oprávnění uživatele `gh-runner` (skupiny `mwalek` a
  `docker`, `safe.directory`, SSH deploy key namísto tokenu, `chmod 640 .env`,
  viz [Požadavky na uživatele runneru](../README.md#požadavky-na-uživatele-runneru))
  proběhl testovací `workflow_dispatch` běh `deploy.yml` úspěšně;
- monitorovací dashboard: popisky časové osy grafu „Provoz a duplicity" nyní
  zobrazují datum i čas (dřív jen `HH:MM`, což u 24hodinového okna
  přesahujícího půlnoc působilo jako obrácený čas), a najetím myší na graf se
  zobrazí tooltip s hodnotami nejbližšího bodu.

Oba endpointy přijímají WebSocket na `/mqtt` i na `/`. Cesta `/` je nutná pro
MeshCore integraci v Home Assistantu, která ji nastavuje pevně.

Deduplikovaný read-only feed pro vzdálený CoreScope nebo mapu je dostupný na
`wss://<doména>/feed`. Vyžaduje účet `corescope-ro` nebo `map-ro` a dovoluje
odebírat pouze `meshcore/#`.

Běžný HTTP požadavek prohlížeče na `https://mqtt2.meshcore.website/` vrací
veřejnou informační stránku s návodem pro připojení observeru k MQTT1 a MQTT2.
Statické soubory jsou v `nginx/site/` a Nginx je připojuje read-only do
`/usr/share/nginx/html/site`. WebSocket upgrade na kořenové cestě `/` se nadále
proxyuje do `public-broker` kvůli kompatibilitě s MeshCore integrací v Home
Assistantu; observer endpoint `/mqtt` se nemění. Součástí webu jsou také veřejné
`/robots.txt`, `/sitemap.xml` a `/llms.txt`.

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
- `cloudflared`: na obou uzlech.

Observer účet ani observer heslo se nevytváří. Každý klient podepisuje svůj
token vlastní MeshCore identitou. Statická hesla jsou pouze pro interní služby.

## Požadavky a adresáře

Doporučeno: Ubuntu Server 24.04 LTS, 4 GB RAM a 40 GB disk. Produkční deploy
repozitář, konfigurace i aplikační data jsou přímo v
`/opt/meshcore-mqtt-stack`:

```text
/opt/meshcore-mqtt-stack/.env
/opt/meshcore-mqtt-stack/feed-readers.env
/opt/meshcore-mqtt-stack/public-broker/data/
/opt/meshcore-mqtt-stack/mosquitto/config/passwd
/opt/meshcore-mqtt-stack/mosquitto/config/acl
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
chmod 640 .env
cp feed-readers.env.example feed-readers.env
chmod 640 feed-readers.env
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
chmod 640 .env
cp feed-readers.env.example feed-readers.env
chmod 640 feed-readers.env
```

V `.env` nastavte všechny hodnoty `CHANGE_ME`. Pevně ponechte:

```env
PUBLIC_DOMAIN=mqtt1-meshcore.node.cz
AUTH_EXPECTED_AUDIENCE=mqtt1-meshcore.node.cz
MQTT_INPUT_TOPIC=meshcore/#
MQTT_OUTPUT_PREFIX=meshcore
DEDUP_KEY_MODE=topic_raw
MONITOR_DOMAIN=monitor-mqtt1-meshcore.node.cz
MONITOR_EVENTS_ENABLED=true
MONITOR_TOPIC_PREFIX=meshcore-monitor
MONITOR_OBSERVER_IP_SOURCE=source1
MONITOR_RETENTION_DAYS=30
MONITOR_ACTIVE_WINDOW_SECONDS=180
```

Stejně jako na MQTT2 nastavte Cloudflare Tunnel pro MQTT endpoint na službu
`http://nginx:80` a jeho token vložte do `CLOUDFLARE_TUNNEL_TOKEN`. Monitorovací
hostname přidejte do tunelu až po vytvoření Cloudflare Access aplikace podle
části „Monitoring“ — postup je pro oba uzly stejný, jen s vlastním hostname
`monitor-mqtt1-meshcore.node.cz`.

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

Účty interního Mosquitta se dělí na dvě skupiny:

- tři pevné interní účty (`feed-health`, `dedup-writer`, `monitor-ro`) —
  hesla v `.env` (`FEED_HEALTH_PASSWORD`, `DEDUP_WRITER_PASSWORD`,
  `MONITOR_RO_PASSWORD`);
- libovolný počet read-only účtů pro deduplikovaný feed (`corescope-ro`,
  `map-ro` a další podle potřeby) v samostatném souboru `feed-readers.env`:

```bash
cp feed-readers.env.example feed-readers.env
chmod 640 feed-readers.env
```

`640` (ne `600`) je záměrně — self-hosted GitHub Actions runner běží pod
vlastním uživatelem (`gh-runner`), který čte tyto soubory jen díky členství
ve skupině vlastníka; `600` by mu čtení odepřel, viz [Požadavky na uživatele
runneru](../README.md#požadavky-na-uživatele-runneru).

Formát `feed-readers.env` je dvojice řádků na účet (jméno, pak heslo),
prázdný řádek mezi účty:

```text
corescope-ro
CHANGE_ME_CORESCOPE

map-ro
CHANGE_ME_MAP

sluzba1
mojetajneheslo
```

`./scripts/start.sh` z obou souborů při každém nasazení automaticky
přegeneruje `mosquitto/config/passwd` a `mosquitto/config/acl` (každý čtecí
účet dostane `topic read meshcore/#`) a `feed-broker` restartuje jen tehdy,
když se seznam účtů nebo některé z těch tří pevných hesel skutečně změnilo —
běžné nasazení bez změny účtů žádný restart nevyvolá. Přidání nebo odebrání
řádku ve `feed-readers.env` se tak projeví hned při dalším deploy. Password
file po přegenerování vlastní `root:root` s režimem `644`, protože kontejner
po startu přepne na neprivilegovaného uživatele `mosquitto`.

Regenerování lze i vyvolat samostatně bez celého `start.sh`:

```bash
./scripts/create-mosquitto-users.sh
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
server: mqtt1-meshcore.node.cz
port: 443
transport: websockets
TLS: ano
auth token: ano
token audience: mqtt1-meshcore.node.cz

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
do `meshcore/#` a interního `meshcore-monitor/#`; každý účet z
`feed-readers.env` (`corescope-ro`, `map-ro` a libovolné další) smí číst pouze
`meshcore/#`. Samostatný `monitor-ro` smí číst jen `meshcore-monitor/#` a
`$SYS/#`.

Příklad vzdáleného CoreScope:

```json
{
  "name": "mqtt2-deduplicated-feed",
  "broker": "wss://mqtt2.meshcore.website/feed",
  "username": "corescope-ro",
  "password": "HESLO_CORESCOPE_RO_Z_FEED_READERS_ENV",
  "rejectUnauthorized": true,
  "topics": ["meshcore/#"]
}
```

## Monitoring MQTT1 a MQTT2

Postup je pro oba uzly stejný, jen s vlastním hostname. Monitorovací web běží
v kontejneru `monitor` na interním portu `8080`. Port není namapovaný na
hostitele. Nginx jej zpřístupňuje pouze pod hostname:

```text
https://monitor-mqtt1-meshcore.node.cz  (MQTT1)
https://monitor-mqtt2.meshcore.website  (MQTT2)
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
Desktopové rozložení používá kompaktní sloupce bez vodorovného posuvníku.
Veřejný klíč je v tabulce zkrácený; celý klíč zůstává dostupný po najetí a v
detailu observeru. Na úzkých displejích zůstává vodorovné posouvání jako záloha.

Význam klasifikace:

```text
same-source  první i další kopie přišly ze stejného source
cross-source první a další kopie přišly z různých source
neurčeno     záznam vznikl před nasazením klasifikace a nelze jej přesně určit
```

Read-only WebSocket provoz `/feed` vede z Nginxu přes interní `feed-proxy` na
samostatný Mosquitto listener `9002`. Nginx na obou uzlech stejně přepíše
interní hlavičku `X-MeshCore-Client-IP` hodnotou `CF-Connecting-IP` od
Cloudflare. HAProxy tuto ověřenou IP nastaví jako zdroj a předá Mosquittu
pomocí PROXY protocol v2. Mosquitto ji proto zapíše ke správnému MQTT client ID
a účtu. Listener `9002` není publikovaný na hostiteli; přímé interní služby
nadále používají listener `9001` bez PROXY protocolu. IP v dashboardu je
veřejná adresa klienta bez technického portu interního proxy spojení.

Na Cloudflare nesmí být pro žádný z uzlů zapnutý Managed Transform `Remove
visitor IP headers`, jinak nebude `CF-Connecting-IP` doručená Nginxu a `/feed`
spojení bude bezpečně odmítnuto. Klient musí po nasazení navázat nové spojení,
aby se jeho veřejná IP propsala do monitoru.

Veřejná IP observeru se získává odděleně přímo v tokenovém brokeru. Nginx na
obou uzlech předává hlavičku `CF-Connecting-IP` jak pro `/mqtt`, tak pro
kořenový WebSocket `/`, který používá Home Assistant. Broker po úspěšném
ověření tokenu vytvoří privátní událost
`$meshcore-monitor/observer/ip/{public_key}`. Číst ji smí jen `dedup-reader`;
worker na daném uzlu ji přijímá výhradně ze svého lokálního zdroje (MQTT1:
`source1`, MQTT2: `source2`) a lokálně ji uloží pod
`meshcore-monitor/observer/ip/{public_key}`. Údaj neprochází přes `meshcore/#`,
takže jej CoreScope, mapa ani jiné read-only služby neuvidí.

Volbu lokálního zdroje řídí `MONITOR_OBSERVER_IP_SOURCE`. MQTT1 override ji
nastavuje na `source1`, MQTT2 override na `source2`. Při změně pořadí zdrojů se
musí odpovídajícím způsobem změnit i tato hodnota.

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

`./scripts/start.sh` udržuje `mosquitto/config/passwd` a `acl` automaticky
synchronizované s `.env` a `feed-readers.env` (viz [Hesla
služeb](#hesla-služeb)) a restartuje `feed-broker`, jen když se skutečně
něco změnilo — samostatný krok pro `monitor-ro` už není potřeba. Interní
kontrola webu:

```bash
./scripts/compose.sh exec nginx wget -qO- \
  --header="Host: $MONITOR_DOMAIN" \
  http://127.0.0.1/api/health
```

Očekávaný výsledek je:

```json
{"status":"ok","feed_connected":true}
```

Před přidáním monitorovacího hostname do tunelu nejprve vytvořte Cloudflare
Access aplikaci. Access nesmí chránit celý hostname veřejného MQTT endpointu
(`mqtt1-meshcore.node.cz` nebo `mqtt2.meshcore.website`), protože MQTT klienti
neumějí browserové přihlášení Cloudflare Access.

V Cloudflare Zero Trust zvolte `Access controls → Applications → Add an
application → Self-hosted and private → Public DNS`. Vytvořte aplikaci pouze
pro hostname monitoru daného uzlu (`monitor-mqtt1-meshcore.node.cz` nebo
`monitor-mqtt2.meshcore.website`), bez omezení na cestu.

Doporučená politika (příklad pro MQTT2, pro MQTT1 analogicky):

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

Teprve potom v Cloudflare Tunnelu daného uzlu přidejte published application
route/public hostname:

```text
Hostname: monitor-mqtt1-meshcore.node.cz nebo monitor-mqtt2.meshcore.website
Service:  http://nginx:80
```

Pokud Cloudflare nabídne `Protect with Access`, zapněte jej, aby `cloudflared`
ověřoval Access token před předáním požadavku Nginxu.

Samostatný DNS záznam není při přidání public hostname přes dashboard obvykle
potřeba; Cloudflare jej vytvoří pro tunnel. Přístup ověřte jednou z povolené IP
a jednou například přes mobilní data, odkud musí být zamítnutý.

### Kontrola monitoringu

Po nasazení uzlu musí výpis obsahovat sedm běžících služeb; `feed-broker`,
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
/opt/meshcore-mqtt-stack/feed-readers.env
/opt/meshcore-mqtt-stack/mosquitto/config/passwd
/opt/meshcore-mqtt-stack/mosquitto/data/
/opt/meshcore-mqtt-stack/public-broker/data/
/opt/meshcore-mqtt-stack/monitor/data/
```

`mosquitto/config/acl` nezálohujte samostatně — je to jen odvozený výstup
`.env` a `feed-readers.env`, `create-mosquitto-users.sh` ho po obnově zálohy
znovu vygeneruje.

Před kopírováním monitorovací databáze zastavte službu `monitor`, nebo použijte
SQLite online backup. Samotné kopírování souboru `monitor.db` za běhu nemusí
zahrnout data uložená ve WAL souboru.

`.env` ani `passwd` neukládejte do Gitu.

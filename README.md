# MeshCore MQTT deployment

Samostatný produkční balíček pro jeden uzel. Stejný obsah se nasazuje na oba
hostingy; liší se pouze lokální `.env` a TLS certifikáty.

## Požadavky

- Ubuntu server s Docker Engine a Compose pluginem
- DNS doména směřující na server
- TLS certifikát pro danou doménu
- veřejný image `ghcr.io/mesh-cz/meshcore-dedup-worker:latest`, nebo přihlášení
pomocí `docker login ghcr.io`, pokud je image privátní

Image publikuje workflow v hlavním repozitáři. Protože cílový package patří
organizaci `mesh-cz`, musí mít repozitář secret `GHCR_TOKEN` s oprávněním
publikovat balíčky do této organizace.

## Instalace

```sh
sudo ./scripts/install-docker-ubuntu.sh
cp .env.example .env
nano .env
mkdir -p secrets/nginx
# vlož secrets/nginx/fullchain.pem a secrets/nginx/privkey.pem
./scripts/create-mosquitto-users.sh
./scripts/start.sh
```

Na druhém uzlu změň zejména `COMPOSE_PROJECT_NAME`, `PUBLIC_DOMAIN` a
`MQTT_CLIENT_ID_PREFIX`. Hodnoty `MQTT_SOURCE_1_*` a `MQTT_SOURCE_2_*` mohou být
pro každý broker odlišné. `MQTT_LOCAL_DEDUP_READER_PASSWORD` musí odpovídat
`DEDUP_READER_PASSWORD`; obdobně target heslo musí odpovídat
`DEDUP_WRITER_PASSWORD`.

## Bezpečnost

Do Gitu nikdy nepatří `.env`, soubor `mosquitto/config/passwd`, obsah
`secrets/`, certifikáty, privátní klíče, data ani logy. Port 1883 je dostupný jen
uvnitř Docker sítě; z internetu jsou publikovány pouze HTTP/HTTPS porty Nginxu.

Cloudflare nastav na `Full (strict)`. Observer používá
`wss://<PUBLIC_DOMAIN>/mqtt`; CoreScope a mapa v téže Docker síti používají
`ws://mosquitto:9001` a topic `meshcore/feed/#`.

## Provoz

```sh
docker compose ps
docker compose logs -f dedup-worker
docker compose logs -f mosquitto
docker compose pull
docker compose up -d
```

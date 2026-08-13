# Ambiente de desenvolvimento 100% em Docker

Descreve como rodar Rails + Sidekiq + Vite + Postgres + Redis + Mailhog
inteiramente em containers, com hot reload, e como isso se conecta com os
outros serviços do projeto ChatMundi que vivem em outros repositórios:

- **chat-mundi** (FastAPI) — orquestra o fluxo, fala com o Chatwoot via API.
- **Evolution API** (WhatsApp) — outro compose, também fora deste repo.

Nada disso substitui `docker-compose.yaml` nem `docker-compose.production.yaml`.
Este setup usa `docker-compose.override.yml`, que o `docker compose` já
mescla automaticamente por cima do `docker-compose.yaml` — sem precisar de
flag `-f`. Tanto o override quanto este doc estão versionados no repo:
qualquer dev pode subir tudo via socket do Docker sem precisar recriar nada.
Cada dev ainda cria a rede externa e o `.env` localmente (passos abaixo).

## Isolamento de dados

O Postgres e o Redis deste projeto **nunca** devem ser reaproveitados por
outros serviços (Evolution, CRMundi/chat-mundi). Por isso, no
`docker-compose.override.yml`, só `rails`, `sidekiq` e `mailhog` são
anexados à rede externa compartilhada — `postgres`, `redis` e `vite`
continuam isolados na rede interna do projeto, inalcançáveis de fora.

## 1. Pré-requisitos (uma vez só)

Criar a rede externa compartilhada, usada também pelos composes do
chat-mundi e/ou da Evolution API:

```sh
docker network create chatmundi_dev
```

## 2. Configurar variáveis de ambiente

```sh
cp .env.example .env
```

Edite o `.env` e preencha pelo menos:

```sh
# Gere com: bundle exec rake secret (ou via um container temporário, ver abaixo)
SECRET_KEY_BASE=

# Senha do Redis dentro do compose (qualquer string forte, é só local)
REDIS_PASSWORD=

# Deixe em branco para trust auth local (como já é hoje no docker-compose.yaml)
POSTGRES_PASSWORD=
POSTGRES_USERNAME=postgres

# Necessário para o Vite servir os assets pro Rails dentro da rede do compose
SMTP_ADDRESS=
SMTP_PORT=1025
```

Se ainda não tem Ruby/Bundler instalados no host para gerar o
`SECRET_KEY_BASE`, gere de dentro de um container temporário:

```sh
docker run --rm ruby:3.4.4-alpine ruby -rsecurerandom -e "puts SecureRandom.hex(64)"
```

## 3. Subir os serviços

```sh
docker compose up -d
```

Isso builda as imagens de dev (`docker/dockerfiles/rails.Dockerfile`,
`vite.Dockerfile`) na primeira vez e sobe os 6 serviços. O código do repo
é montado via bind mount (`./:/app`), então mudanças em Ruby/Vue/JS têm
hot reload — não precisa rebuildar a imagem a cada alteração, só quando o
`Gemfile`/`package.json` mudar.

Acompanhe os logs até tudo ficar saudável:

```sh
docker compose ps
docker compose logs -f rails
```

## 4. Primeira preparação do banco

Como o volume do Postgres foi corrigido para persistir de verdade (veja
comentário no `docker-compose.override.yml`), o banco começa vazio:

```sh
docker compose exec rails bundle exec rails db:chatwoot_prepare
```

Depois disso, os dados persistem entre `docker compose down` / `up`
normalmente (a menos que rode `down -v`, que apaga os volumes).

## 5. Acessando os serviços

| Serviço  | Do host                         | De outro container na rede `chatmundi_dev` |
|----------|----------------------------------|---------------------------------------------|
| Rails    | http://localhost:3000            | `http://rails:3000`                          |
| Vite     | http://localhost:3036             | não exposto na rede compartilhada            |
| Mailhog  | http://localhost:8025 (UI)        | `mailhog:1025` (SMTP)                        |
| Postgres | localhost:5432                    | não exposto na rede compartilhada            |
| Redis    | localhost:6379                    | não exposto na rede compartilhada            |

## 6. Do lado do chat-mundi / Evolution API

No `docker-compose.yaml` desses outros repos, declare a mesma rede externa
e conecte só os serviços que precisam falar com o Chatwoot:

```yaml
services:
  chat-mundi-api:
    # ...
    networks:
      - default
      - chatmundi_dev

networks:
  chatmundi_dev:
    external: true
```

E aponte a integração para `http://rails:3000` (nome do serviço, resolvido
via DNS do Docker dentro da rede `chatmundi_dev`) em vez de `localhost`.
**Nunca** aponte `DATABASE_URL`/`REDIS_URL` desses outros serviços para o
`postgres`/`redis` deste projeto — eles não estão nem alcançáveis por essa
rede, de propósito.

## 7. Encerrando

```sh
docker compose down          # mantém os volumes (dados persistem)
docker compose down -v       # remove volumes também (apaga o banco de dev)
```

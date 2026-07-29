# ChatMundi local: instalacao e integracao com Evolution

Guia para executar o ChatMundi, fork do Chatwoot, na branch
upgrade/chatmundi-v4.6.0 e integrar uma Evolution API separada.

## 1. Arquitetura

| Componente | Execucao | Porta | Obrigatorio |
| --- | --- | --- | --- |
| ChatMundi/Rails | host/WSL ou Docker | 3000 | sim |
| Sidekiq | host/WSL ou Docker | sem HTTP | sim para jobs/webhooks |
| Vite | host/WSL ou Docker | 3036 | somente para a UI |
| PostgreSQL/pgvector | Docker ou local | 5432 | sim |
| Redis | Docker ou local | 6379 | sim |
| Evolution API | Docker separado | 8080 | sim para WhatsApp |

O docker-compose.yaml do ChatMundi nao sobe a Evolution. A Evolution tem
projeto, .env, containers e volumes proprios.

## 2. Clonar e atualizar

O fork atual usa o remoto timetamundi/chatwoot:

~~~
git clone https://github.com/timetamundi/chatwoot.git chatmundi
cd chatmundi
git fetch origin --prune
git checkout -B upgrade/chatmundi-v4.6.0 origin/upgrade/chatmundi-v4.6.0
~~~

Para atualizar uma copia existente:

~~~
git status --short
git fetch origin --prune
git pull --ff-only origin upgrade/chatmundi-v4.6.0
~~~

Nao use reset --hard para resolver alteracoes locais sem backup ou decisao
manual. Se o pull exigir merge, pare e revise antes.

## 3. Pre-requisitos

Versoes esperadas neste estado:

- Ruby 3.4.4, conforme .ruby-version;
- Node 24.x, conforme .nvmrc/package.json;
- pnpm 10.x;
- PostgreSQL com pgvector;
- Redis;
- Docker Desktop, se as dependencias forem executadas por Compose;
- Bundler compativel com Gemfile.lock.

Instale dependencias:

~~~
bundle install
pnpm install
~~~

No Windows/WSL, use Ruby, Bundler e Rails do mesmo ambiente. Nao misture
Bundler do Windows com Ruby do WSL.

## 4. Criar e preencher o .env

~~~
cp .env.example .env
~~~

Nunca publique .env, tokens, chaves ou screenshots com segredos.

### 4.1 Desenvolvimento fora do Docker

Use hosts locais:

~~~
RAILS_ENV=development
NODE_ENV=development
FRONTEND_URL=http://localhost:3000

POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot_development
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=<senha-do-postgres>

REDIS_URL=redis://:<senha-redis>@localhost:6379
SECRET_KEY_BASE=<chave-longa-gerada-localmente>
ACTIVE_STORAGE_SERVICE=local
~~~

Se o Redis nao usa senha, ajuste REDIS_URL conforme a configuracao real.
Gere uma chave local com:

~~~
bundle exec rails secret
~~~

### 4.2 Variaveis customizadas do ChatMundi

O ambiente atual usa estas familias:

~~~
BRAND_NAME=ChatMundi
INSTALLATION_NAME=ChatMundi

CHATMUNDI_PLATFORM_API_TOKEN=<token-da-platform-api>

SSO_JWKS_URL=<url-do-jwks>
SSO_JWT_ISS=<issuer>
SSO_JWT_AUD=<audience>
SSO_JWT_KID=<kid>

CRMUNDI_WEBHOOK_ENABLED=false
CRMUNDI_WEBHOOK_URL=<endpoint-do-crmundi>
CRMUNDI_WEBHOOK_TOKEN=<token-do-webhook>

CRMUNDI_INACTIVITY_WEBHOOK_ENABLED=false
CRMUNDI_INACTIVITY_MINUTES=30
~~~

Regras:

- CHATMUNDI_PLATFORM_API_TOKEN nunca vai para o frontend.
- O token das rotas /api/v1/accounts/... deve pertencer a usuario com acesso
  a account. Token de Platform API e token de Account API nao sao automaticamente
  intercambiaveis.
- Ative CRMUNDI_WEBHOOK_ENABLED somente quando URL e token estiverem testados.
- O scanner de inatividade permanece desligado por padrao.

## 5. Banco e Redis

### Dependencias no Docker, Rails fora do Docker

~~~
docker compose up -d postgres redis mailhog
bundle exec rails db:prepare
~~~

Neste caso o .env do Rails usa normalmente POSTGRES_HOST=localhost e REDIS_URL
com localhost.

### Toda a stack ChatMundi no Docker

~~~
docker compose build rails sidekiq vite
docker compose run --rm rails bundle exec rails db:prepare
docker compose up -d rails sidekiq vite
docker compose ps
~~~

Dentro do Compose, os hosts sao postgres e redis, conforme o docker-compose.yaml.
Nao reutilize automaticamente um .env de host no container.

## 6. Executar fora do Docker

Para API sem UI, Rails e Sidekiq sao os processos principais. Vite nao participa
das chamadas API nem da entrega de webhooks, mas e necessario para a interface
web e para assets de desenvolvimento.

Terminal 1:

~~~
bundle exec rails s -p 3000
~~~

Terminal 2:

~~~
bundle exec sidekiq -C config/sidekiq.yml
~~~

Terminal 3, somente para UI:

~~~
bin/vite dev
~~~

Ou todos os processos de desenvolvimento:

~~~
pnpm dev
~~~

Se aparecer "A server is already running", confira o PID:

~~~
cat tmp/pids/server.pid
ps -fp <pid>
curl -I http://localhost:3000
~~~

Se aparecer "Vite Ruby can't find entrypoints/dashboard.js":

~~~
bin/vite build --clear --mode=development
~~~

Se aparecer "lint-staged nao e reconhecido", rode pnpm install. Nao use
--no-verify como correcao permanente.

## 7. Executar no Docker

~~~
docker compose up -d postgres redis mailhog
docker compose up -d rails sidekiq vite
docker compose ps
docker compose logs -f rails sidekiq vite
~~~

O navegador acessa http://localhost:3000. Rails no container acessa PostgreSQL
por postgres e Redis por redis.

## 8. Evolution API

A Evolution fica em outro projeto. Confirme nela:

- API respondendo na porta 8080;
- chave global de autenticacao configurada;
- banco/Redis da Evolution, se usados;
- volume persistente da sessao;
- instancia criada;
- sessao WhatsApp conectada;
- webhook da instancia configurado;
- nome real do container/servico e network Docker.

As variaveis exatas mudam conforme a versao da Evolution. Nao copie um .env
de outra versao sem conferir a documentacao da imagem usada. Os nomes comuns
incluem AUTHENTICATION_API_KEY, SERVER_URL, banco, Redis e configuracao da
sessao, mas o projeto da Evolution e a fonte de verdade.

Teste a instancia:

~~~
curl -i http://localhost:8080
curl -i http://localhost:8080/instance/connectionState/<instancia> ^
  -H "apikey: <chave-da-evolution>"
~~~

No PowerShell, use a crase no lugar de ^ para continuacao, ou execute em uma
linha.

### Evolution em Docker e ChatMundi no host

Na configuracao Chatwoot/Evolution, use:

~~~
Chatwoot URL: http://host.docker.internal:3000
Account ID: <account-id>
Chatwoot token: <token-de-usuario-com-acesso-a-account>
~~~

O container Evolution usa host.docker.internal para chegar ao Rails no host.

Para o webhook da inbox Channel::Api, quando Rails esta no host e Evolution
esta em Docker, o Rails e o cliente que dispara o webhook. Use:

~~~
http://localhost:8080/chatwoot/webhook/<identificador>
~~~

Se Rails tambem estiver em Docker, use uma URL acessivel pelo container Rails,
como:

~~~
http://host.docker.internal:8080/chatwoot/webhook/<identificador>
~~~

### Ambos em Docker

Se os dois projetos compartilham uma network, prefira o nome real do servico:

~~~
http://evolution-api:8080/chatwoot/webhook/<identificador>
~~~

Esse nome so funciona se o container realmente se chamar evolution-api e estiver
na mesma network.

## 9. O que precisa estar ligado

Somente API:

- PostgreSQL;
- Redis;
- Rails;
- Sidekiq para jobs/webhooks;
- Evolution para WhatsApp.

Com UI:

- tudo acima;
- Vite.

Para webhook CRMundi:

- Sidekiq;
- CRMUNDI_WEBHOOK_ENABLED=true;
- CRMUNDI_WEBHOOK_URL acessivel pelo Sidekiq;
- CRMUNDI_WEBHOOK_TOKEN valido;
- inbox/canal elegivel.

O Vite nao e necessario para envio de mensagens ou webhooks.

## 10. Testes de conectividade

Rails:

~~~
curl -i http://localhost:3000
curl -i http://localhost:3000/health
~~~

Se /health nao existir nesta revisao, GET / com HTTP 200 confirma resposta.

Compose:

~~~
docker compose ps
docker compose logs --tail=100 postgres redis rails sidekiq
~~~

Rails/Redis:

~~~
bundle exec rails runner "puts ActiveRecord::Base.connection.select_value('SELECT 1')"
~~~

Account API usa normalmente o cabecalho api_access_token. O token deve
pertencer a usuario com acesso a account; nao use inbox_identifier como token
de usuario.

## 11. Teste ponta a ponta

1. Rails responde em 3000.
2. PostgreSQL e Redis estao saudaveis.
3. Sidekiq esta consumindo a fila.
4. Evolution responde em 8080.
5. A instancia Evolution esta open/connected.
6. Account ID e token estao corretos.
7. O usuario do token esta associado a account.
8. A inbox e Channel::Api e tem webhook correto.
9. Uma mensagem recebida aparece no ChatMundi.
10. Uma resposta enviada chega a Evolution/WhatsApp.
11. Logs Rails, Sidekiq e Evolution nao mostram erro de rede, token ou permissao.

## 12. Diagnostico rapido

### Rails nao inicia

Confira server.pid, bundle install, POSTGRES_HOST/porta, REDIS_URL e se as
portas 3000, 5432 e 6379 ja estao ocupadas.

### Mensagem entra, mas nao sai

Confira Sidekiq, estado da instancia, account ID, token, inbox Channel::Api,
webhook e os logs dos dois projetos.

### Hostname localhost has no public ip addresses

E o bloqueio SSRF de URL local. A customizacao do ChatMundi permite hosts locais
para webhook de API inbox apenas em development/test. Em staging/production a
protecao continua ativa: use URL acessivel e HTTPS.

### 401 na Account API

Causas mais comuns: token invalido, usuario sem account_user, account ID errado
ou uso de token Platform API em rota Account API.

### Anexos/imagens falham

A Evolution precisa baixar a URL do attachment. localhost dentro do container
aponta para o proprio container; use host.docker.internal ou hostname da
network Docker.

## 13. Operacao e validacao

~~~
docker compose ps
docker compose logs -f rails sidekiq redis postgres
docker compose restart rails sidekiq vite
docker compose stop

bundle exec rails console
bundle exec rails zeitwerk:check
bundle exec rspec
pnpm test
~~~

Nao use docker compose down -v em ambiente com dados importantes: -v remove
volumes, banco local e sessoes.

## 14. Checklist final

- [ ] Branch upgrade/chatmundi-v4.6.0.
- [ ] bundle install e pnpm install concluidos.
- [ ] .env criado fora do Git e sem segredos expostos.
- [ ] SECRET_KEY_BASE definido.
- [ ] PostgreSQL/pgvector acessivel.
- [ ] Redis acessivel.
- [ ] Rails respondendo em 3000.
- [ ] Sidekiq executando.
- [ ] Vite executando somente se UI for usada.
- [ ] Evolution respondendo em 8080.
- [ ] Instancia Evolution conectada.
- [ ] Account ID correto.
- [ ] Token com acesso a account.
- [ ] Webhook usa hostname correto para a topologia.
- [ ] CRMundi webhook ativado somente apos teste.
- [ ] Scanner de inatividade mantido desligado.

## 15. Limites deste repositorio

O docker-compose, .env e volumes da Evolution nao estao neste repositorio.
Para confirmar que tudo esta ligado, ainda e necessario verificar no projeto
Evolution a versao, container, chave, instancia, sessao, webhook, volumes e
network.


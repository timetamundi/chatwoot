# ChatMundi upgrade prep - v4.6.0

Data: 2026-06-10
Branch atual validada: upgrade/chatmundi-v4.6.0
Base original: feature/crmundi
HEAD base: 69d9f096a
Merge-base com upstream/master: b989ca639744573e00dd9c31acae7797aa7a141c
Alvo inicial: v4.6.0

## Estado validado antes dos artefatos

- `git status`: working tree limpo em `upgrade/chatmundi-v4.6.0`.
- `git diff --stat`: sem saida.
- `git branch --show-current`: `upgrade/chatmundi-v4.6.0`.
- `git log --oneline -5`: HEAD em `69d9f096a`.
- `origin`: https://github.com/timetamundi/chatwoot.git
- `upstream`: https://github.com/chatwoot/chatwoot.git
- Tag `v4.6.0`: presente localmente.

Depois da geracao, o working tree fica com arquivos nao rastreados apenas em `upgrade_artifacts/`.

## Divergencia

- Commits exclusivos ChatMundi: 19
- Commits exclusivos upstream/master: 870
- Primeiro alvo recomendado: `v4.6.0`
- Sequencia recomendada posterior: `v4.6.0 -> v4.8.0 -> v4.10.1 -> v4.12.1 -> v4.14.1`

## 19 commits exclusivos e classificacao

| Commit | Autor | Data | Bloco | Mensagem |
| --- | --- | --- | --- | --- |
| c20623e4a | CaioRocha | 2025-09-15 | A, B, I | feat(sso): SSO CRMundi -> ChatMundi (Chatwoot) com JWT+JWKS, bootstrap e cookie de sessao |
| d51bc3065 | CaioRocha | 2025-09-25 | A, G | Fix SSO multi-tenant + ajustes no User model e profiler |
| 55499a90a | CaioRocha | 2025-09-26 | A | Fix SSO redirect para Chatwoot dashboard |
| 650d61ae3 | CaioRocha | 2025-10-01 | A, B | Fix SSO tenant: remover downcase, preservar formato enviado pelo CRMundi |
| 0c562ec89 | CaioRocha | 2025-10-02 | E, J, I | Customizacao ChatMundi: branding logos/colors/sidebar/etc. |
| 8a4766f36 | CaioRocha | 2025-10-03 | J | Hide contact fields (city, bio, social profiles) in contact form |
| 91890be3f | TI Metamundi | 2025-12-19 | J | chore: esconde icones nao utilizados no chatmundi |
| 8ca5a7202 | TI Metamundi | 2026-05-22 | E, J, I, K | feat: salva modificacoes |
| 0040925fd | Caio Rocha | 2026-05-22 | C | feat: integrate CRMundi webhook on WhatsApp conversation resolved |
| b19292d60 | Caio Rocha | 2026-05-22 | C, I | fix: align CRMundi webhook payload with LLM standard and add tenant config |
| 41ae12b28 | Caio Rocha | 2026-05-22 | C, B, I | fix: use LLM roles and add CRMUNDI_TENANT_ID for webhook header |
| 1227e5dae | Caio Rocha | 2026-05-22 | A, C, B | feat(crmundi): webhook SSO-driven tenant resolution |
| bfc0f7a4f | Caio Rocha | 2026-05-23 | D, C, I | feat(crmundi): phase 2 - inactivity webhook scanner |
| aa3754dfe | Caio Rocha | 2026-05-23 | A | fix(sso): correct runtime error wrong number of arguments on SSO login |
| a58c7a982 | Caio Rocha | 2026-05-25 | C | fix(crmundi): trigger webhook on resolve for Channel::Api CRMundi accounts |
| 56f77b9c1 | Caio Rocha | 2026-05-25 | C | feat(crmundi): inclui anexos no payload do webhook e atualiza last_message para [arquivo/imagem enviado(a)] |
| f54bf94b6 | Caio Rocha | 2026-05-25 | D, C | fix(crmundi): corrige scanner de inatividade para aceitar mensagens so com anexos |
| 1fd5c5edd | Caio Rocha | 2026-05-26 | C, D, I | fix(crmundi): corrige backlog de jobs, timeout HTTP, idempotencia, N+1 e desabilita scanner do cron |
| 69d9f096a | Caio Rocha | 2026-05-26 | C, D, I | fix(sidekiq,crmundi): throttle inactivity scanner, harden webhook retries, and align db pool/concurrency |

## Patches gerados

Pasta: `upgrade_artifacts/patches/`

| Patch | Bloco | Observacao |
| --- | --- | --- |
| 01_sso_crmundi.patch | A - SSO CRMundi | Controller, settings, bootstrap, JWKS client |
| 02_tenant_account_mapping.patch | B - Tenant/account mapping | External id e ajustes de Account/AccountUser |
| 03_webhook_crmundi.patch | C - Webhook CRMundi | Job, listener, eligibility, dispatcher/helper |
| 04_scanner_inatividade.patch | D - Scanner de inatividade | Job do scanner |
| 05_branding.patch | E - Branding | Logos, icones, cores, nomes, config visual |
| 06_realtime_actioncable.patch | F - Realtime/ActionCable | Vazio; nao ha diff proprio nesses paths contra o merge-base |
| 07_models_centrais.patch | G - Models centrais | User e canais afetados localmente |
| 08_migrations_locais.patch | H - Migrations locais | Migrations locais e migration oficial alterada |
| 09_config_env_schedule.patch | I - Config/env/schedule | Env, routes, schedule, Sidekiq, db/schema, deps |
| 10_frontend_customizado.patch | J - Frontend customizado | Contact form, sidebar, Button |

Regra aplicada: `vendor/bundle` foi excluido de todos os patches logicos.

## Arquivos excluidos do patchset

- `vendor/bundle/ruby/3.4.0/...`: ruido de instalacao local de gems e artefatos compilados.
- Recomendacao: remover/revisar fora do upgrade funcional; nao preservar como customizacao ChatMundi.

## Arquivos novos ChatMundi

| Arquivo | Bloco | Risco | Recomendacao v4.6.0 |
| --- | --- | --- | --- |
| app/controllers/sso_controller.rb | A | Alto | Preservar ChatMundi e revisar rotas/manual auth |
| app/services/chatwoot/sso_settings.rb | A | Medio | Preservar ChatMundi |
| app/views/sso/bootstrap.html.erb | A | Medio | Preservar ChatMundi |
| public/sso_bootstrap.js | A | Medio | Preservar ChatMundi |
| lib/jwks_client.rb | A | Medio | Preservar ChatMundi |
| app/jobs/crmundi_webhook_job.rb | C | Alto | Preservar ChatMundi, revisar contratos de Message/Conversation |
| app/listeners/crmundi_webhook_listener.rb | C | Alto | Preservar ChatMundi, revisar eventos oficiais |
| app/services/crmundi/conversation_eligibility.rb | C | Medio | Preservar ChatMundi |
| app/jobs/crmundi_inactive_conversations_scanner_job.rb | D | Medio | Preservar, manter cron desabilitado ate validar |
| db/migrate/20250915161433_add_external_id_to_accounts.rb | B/H | Alto | Preservar, validar ordem com migrations oficiais |
| db/migrate/20250926122500_add_unique_index_on_tenant_to_accounts.rb | B/H | Alto | Preservar, validar dados antes de migrar |
| db/migrate/20250926122536_add_unique_index_to_account_users.rb | B/H | Alto | Preservar, validar duplicados antes de migrar |
| chatwoot.json | E/I | Baixo | Revisar se ainda e usado; manter se for deploy metadata |
| public/brand-assets/logo_metamundi.jpeg | E | Baixo | Preservar branding |
| .devcontainer/udo systemctl cat chatmundi-sidekiq.service | K/I | Alto | Provavel arquivo acidental; excluir do patchset funcional |

## Arquivos oficiais alterados localmente

| Arquivo | Bloco | Risco | Recomendacao v4.6.0 |
| --- | --- | --- | --- |
| config/routes.rb | A/I | Alto | Revisar manualmente; preservar rotas SSO e aceitar upstream no restante |
| config/schedule.yml | D/I | Medio | Revisar manualmente; manter scanner CRMundi desabilitado |
| config/sidekiq.yml | C/D/I | Medio | Revisar manualmente; preservar filas necessarias |
| config/database.yml | I | Alto | Preferir upstream e reaplicar pool/concurrency se necessario |
| config/application.rb | A/I | Medio | Revisar manualmente |
| config/initializers/session_store.rb | A/I | Alto | Revisar manualmente por impacto em login/session |
| .env.example | A/C/I | Medio | Reaplicar variaveis CRMundi/SSO no arquivo upstream |
| Gemfile.lock | I | Alto | Preferir upstream v4.6.0, depois rodar bundle install no Ruby correto |
| package.json | I | Alto | Preferir upstream v4.6.0, reaplicar somente scripts/deps locais justificadas |
| pnpm-lock.yaml | I | Alto | Preferir upstream v4.6.0, regenerar com pnpm correto |
| db/schema.rb | H/I | Alto | Nao resolver manualmente como fonte de verdade; regenerar via migrations em teste |
| db/seeds.rb | I | Medio | Revisar manualmente |
| app/models/account.rb | B/G | Alto | Revisar manualmente; preservar tenant/external_id |
| app/models/account_user.rb | B/G | Alto | Revisar manualmente; preservar unicidade/tenant se aplicavel |
| app/models/user.rb | A/G | Alto | Revisar manualmente; area de auth/tenant |
| app/models/channel/telegram.rb | G | Medio | Revisar alteracao local; preferir upstream se nao for CRMundi |
| app/dispatchers/async_dispatcher.rb | C | Alto | Revisar eventos e compatibilidade com listener oficial |
| app/helpers/message_format_helper.rb | C | Medio | Reaplicar ajuste de anexos se necessario |
| lib/base_markdown_renderer.rb | G/I | Medio | Revisar se e branding/ruido; preferir upstream se nao essencial |
| lib/chatwoot_markdown_renderer.rb | G/I | Medio | Revisar se e branding/ruido; preferir upstream se nao essencial |
| lib/custom_markdown_renderer.rb | G/I | Medio | Revisar se e branding/ruido; preferir upstream se nao essencial |
| app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue | J | Medio | Reaplicar customizacao apos aceitar upstream |
| app/javascript/dashboard/components-next/sidebar/Sidebar.vue | J/E | Medio | Reaplicar ocultacao/branding apos aceitar upstream |
| app/javascript/shared/components/Button.vue | J/E | Medio | Preferir upstream e reaplicar apenas cor/comportamento necessario |
| app/javascript/dashboard/assets/scss/_next-colors.scss | E | Medio | Reaplicar branding; observar guideline Tailwind para novas mudancas |
| public/brand-assets/logo.svg | E | Baixo | Preservar branding se ainda for usado |
| public/brand-assets/logo_dark.svg | E | Baixo | Preservar branding se ainda for usado |
| public/brand-assets/logo_thumbnail.svg | E | Baixo | Preservar branding se ainda for usado |
| public/*icon*.png, public/favicon*.png, public/manifest.json | E | Baixo | Preservar branding ou regenerar de forma limpa |
| enterprise/config/premium_installation_config.yml | E/I | Medio | Revisar junto com config OSS |
| enterprise/lib/tasks.rb | I | Medio | Revisar compatibilidade Enterprise |
| app.json | E/I | Baixo | Revisar deploy metadata |

## Arquivos mais arriscados para merge v4.6.0

- `config/routes.rb`
- `config/initializers/session_store.rb`
- `app/models/user.rb`
- `app/models/account.rb`
- `app/models/account_user.rb`
- `app/dispatchers/async_dispatcher.rb`
- `app/jobs/crmundi_webhook_job.rb`
- `app/listeners/crmundi_webhook_listener.rb`
- `config/database.yml`
- `Gemfile.lock`
- `package.json`
- `pnpm-lock.yaml`
- `db/schema.rb`
- `db/migrate/20231211010807_add_cached_labels_list.rb`

## Plano de merge ate v4.6.0

Nao executar ainda sem autorizacao explicita.

1. Confirmar branch e limpeza:

```powershell
git branch --show-current
git status --short
git diff --stat
```

2. Confirmar alvo:

```powershell
git tag --list "v4.6.0"
git show --no-patch --oneline v4.6.0
```

3. Iniciar merge controlado:

```powershell
git merge --no-ff --no-commit v4.6.0
```

4. Listar conflitos:

```powershell
git diff --name-only --diff-filter=U
git status --short
```

5. Ordem recomendada de resolucao:

- Dependencias e lockfiles: `Gemfile.lock`, `package.json`, `pnpm-lock.yaml`.
- Config base: `.env.example`, `config/application.rb`, `config/database.yml`, `config/sidekiq.yml`.
- Rotas e sessao: `config/routes.rb`, `config/initializers/session_store.rb`.
- Models centrais: `app/models/user.rb`, `app/models/account.rb`, `app/models/account_user.rb`.
- Webhook/dispatcher: `app/dispatchers/async_dispatcher.rb`, listener/job CRMundi.
- Migrations/schema: migrations primeiro; `db/schema.rb` so depois de migrar em banco de teste.
- Frontend/branding: componentes, logos, manifest, cores.

6. Preferir upstream nestes arquivos e reaplicar ajustes minimos:

- `Gemfile.lock`
- `package.json`
- `pnpm-lock.yaml`
- `db/schema.rb`
- `config/database.yml`
- `lib/*markdown_renderer.rb` se nao houver requisito funcional local claro

7. Preservar ChatMundi nestes pontos:

- SSO CRMundi: controller, service settings, JWKS, bootstrap.
- Tenant/account mapping: migrations e campos usados pelo SSO/webhook.
- Webhook CRMundi: job/listener/eligibility e payload com anexos.
- Scanner de inatividade, mas manter cron desabilitado ate validacao.
- Branding essencial: logos/nome/paleta, reaplicado sobre estrutura upstream.

8. Validacao depois de resolver conflitos e antes de commit:

```powershell
git diff --name-only --diff-filter=U
git status --short
bundle install
pnpm install
bundle exec rails db:migrate RAILS_ENV=test
bundle exec rspec spec/models/user_spec.rb spec/models/account_spec.rb
pnpm test
pnpm build
```

Ajustar a selecao de specs conforme conflitos reais; nao rodar migrations em banco produtivo.

9. Finalizar merge apenas apos validacao:

```powershell
git add <arquivos_resolvidos>
git commit
```

## Checklist pos-merge v4.6.0

- Ruby 3.4.4 ativo.
- Node 20.5.1 ativo.
- `pnpm` instalado.
- `bundle install` concluido.
- `pnpm install` concluido.
- `rails db:migrate` em banco de teste/staging restaurado.
- RSpec minimo para auth/account/user/webhook.
- Build frontend concluido.
- Login normal funciona.
- SSO CRMundi funciona.
- `tenant_id` salvo corretamente.
- `crmundi_tenant_name` salvo corretamente.
- Conversas antigas abrem.
- Envio de mensagem funciona.
- Recebimento de mensagem funciona.
- ActionCable entrega atualizacoes.
- Sidekiq processa filas necessarias.
- Webhook CRMundi dispara ao resolver conversa.
- Payload inclui anexos quando houver.
- Scanner CRMundi segue desabilitado ate teste dedicado.
- Branding basico visivel: nome, logos, cores principais.

## Pendencias e riscos

- Ambiente local visto antes nao estava alinhado: Ruby 3.3.3 vs `.ruby-version` 3.4.4; Node v22.15.0 vs `.nvmrc` 20.5.1; `pnpm` ausente. Corrigir antes do merge real.
- `vendor/bundle` entrou historicamente nos commits locais e deve ser tratado como ruido.
- `.devcontainer/udo systemctl cat chatmundi-sidekiq.service` parece arquivo acidental e nao deve entrar no patch funcional.
- Migrations oficiais entre v4.6.0 e v4.14.1 incluem mudancas sensiveis em source_id/webhooks/companies/calls; tratar depois, por etapa.
- `db/migrate/20231211010807_add_cached_labels_list.rb` diverge de upstream e precisa comparacao manual.
- Upgrade direto para `upstream/master` continua nao recomendado.

#!/usr/bin/env bash
# Создаёт issue по оставшимся этапам M3 Enot Messenger от имени того, кто
# вошёл в gh (`gh auth status`). Номера зависимостей подставляются сами.
# Повторный запуск безопасен: открытое issue с тем же заголовком не
# создаётся заново, а переиспользуется.
#
#   bash create-m3-issues.sh            # создать
#   DRY_RUN=1 bash create-m3-issues.sh  # только показать, ничего не создавая
#
# Нужен GitHub CLI с выполненным `gh auth login`. В Windows — Git Bash.
set -euo pipefail

org="enot-messenger"
dry_run="${DRY_RUN:-}"
fake=900

declare -A num=()

# issue <ключ> <репозиторий> <метки через запятую> <заголовок>; текст — из stdin.
# В тексте @КЛЮЧ@ заменяется номером ранее созданного issue.
issue() {
	local key="$1" repo="$2" labels="$3" title="$4" body existing url
	body="$(cat)"

	for ref in "${!num[@]}"; do
		body="${body//@$ref@/${num[$ref]}}"
	done

	if [[ "$body" == *@[A-Z]*@* ]]; then
		echo "Ошибка: в тексте «$title» осталась неподставленная ссылка" >&2
		exit 1
	fi

	existing="$(gh issue list -R "$org/$repo" --state open --limit 100 --search "in:title $title" \
		--json number,title --jq ".[] | select(.title == \"${title//\"/\\\"}\") | .number" | head -1)"

	if [ -n "$existing" ]; then
		num[$key]="$existing"
		echo "= $repo#$existing — уже есть: $title"
		return
	fi

	if [ -n "$dry_run" ]; then
		fake=$((fake + 1))
		num[$key]="$fake"
		printf -- '--- %s#(%s) [%s]\n%s\n\n%s\n\n' "$repo" "$fake" "$labels" "$title" "$body"
		return
	fi

	url="$(gh issue create -R "$org/$repo" --title "$title" --label "$labels" --body "$body")"
	num[$key]="${url##*/}"
	echo "+ $url"
}

if [ -z "$dry_run" ]; then
	echo "Issue будут созданы от имени: $(gh api user --jq .login)"
fi

# --- Решения (ADR), без них код не начать -----------------------------------

issue KEYADR enot-docs "type:docs,area:backend,priority:p1" \
	"ADR: как ключ подписи лицензий LICENSE_SIGNING_KEY попадает в Core" <<'EOF'
Этап M3. Без этого решения Core не может выпускать ключи подписки.

## Контекст

- ADR-0005: приватный ключ живёт только в секрете `LICENSE_SIGNING_KEY` репозитория `enot-backend`. Пара создана 2026-10-25, `kid` `a250222ae2b479d2` (журнал, «Заметки о площадке»).
- Деплой (`.github/.github/workflows/reusable-deploy.yml`) секреты репозитория на сервер не передаёт, а `enot-infra/docs/vps-setup.md` §8 говорит, что секреты площадки в GitHub Secrets не хранятся. Сейчас Core ключ получить не может.

## Что решить

- Путь ключа в Core: шаг деплоя пишет секрет в файл на сервере (права 0400, монтирование в `core-gateway` как secret) или владелец кладёт файл на площадку сам. Что из этого меняет ADR-0005 п. 2.
- Кто читает ключ: только модуль `licensing`; ключ не попадает в журнал, ответы и дампы.
- Проверка после деплоя без раскрытия ключа: Core при старте пишет `kid` и отпечаток публичной части.
- Ротация и утечка: новая пара, `retired_at` в `licensing.signing_keys`, новый файл ключа в образе Community Server.

## Готово, когда

ADR принят, ADR-0005 уточнён, шаг описан в `enot-infra/docs/vps-setup.md`.
EOF

issue ADDRADR enot-docs "type:docs,area:infra,area:community-server,priority:p1" \
	"ADR: адрес сообщества <адрес>.enot.space — DNS-запись на VPS владельца и TLS" <<'EOF'
Этап M3. Нужен до выдачи первого адреса и до Caddy в комплекте сообщества.

## Контекст

- ТЗ §3.3: адрес выдаётся при создании и меняется владельцем; сообщество живёт на VPS владельца.
- Сейчас в Cloudflare `*.enot.space` указывает на площадку (`vps-setup.md`, шаг 1), Caddy площадки держит wildcard-сертификат.
- Служебные адреса уже закрыты: `communities.reserved_slugs` (enot-messenger/enot-backend#91).

## Что решить

- Кто создаёт A/AAAA-запись адреса на IP VPS владельца: Core через API Cloudflare после `activate` (токен только с DNS:Edit на зону — где он хранится) или вручную.
- Когда запись меняется и удаляется: смена адреса, закрытие сообщества, 90 дней после окончания подписки (§5.3 ТЗ).
- Как сервер владельца получает сертификат: HTTP-01 через Caddy комплекта, без наших токенов у владельца.
- Защита от захвата чужого адреса: запись меняется только после `activate` с привязкой к ключу и fingerprint.
- Локальный режим — без записи. Что происходит со старым адресом после смены.

## Готово, когда

ADR принят; задачи реестра сообществ и Caddy в комплекте уточнены по нему.
EOF

issue PROTOADR enot-docs "type:docs,area:community-server,priority:p1" \
	"ADR: протокол Community Server — вход через Core, клиент и сервер сообщества, события" <<'EOF'
Этап M3. Основа для всех функций сообщества в сервере и в клиенте.

## Контекст

- ТЗ §3.3, §5.3: вход через SSO Core (OIDC), сервер сообщества паролей не хранит; сообщения и файлы — только на VPS владельца.
- `docs/protocol.md` описывает только Core. Открытый вопрос 3 (поток событий для Community Dashboard) ждёт этого решения.
- Сервер сообщества владелец обновляет вручную: клиенту придётся работать с серверами разных версий.

## Что решить

- Доступ клиента к серверу сообщества: поток OIDC, токен и срок, офлайн-проверка подписи ключами Core, отзыв при бане.
- Транспорт: тот же конверт protobuf и WebSocket, что у Core (ADR-0006, ADR-0009), или свой контракт.
- Версия протокола сообщества и совместимость клиентов с серверами разных версий.
- Методы и события: категории, каналы, сообщения, роли, приглашения, голос (выдача токена LiveKit).
- Community Dashboard: тот же протокол с правами владельца или отдельный.
- Лимиты из ключа подписки (ADR-0005, «Формат ключа») и ответы при их превышении.

## Готово, когда

ADR принят, раздел протокола сообщества — в `docs/protocol.md`, контракт — в `proto/`.
EOF

# --- Core ---------------------------------------------------------------------

issue LICCORE enot-backend "type:feature,area:backend,priority:p1" \
	"Лицензирование в Core: схема, ключ подписи и выпуск ключей подписки" <<'EOF'
Этап M3. Зависит от enot-messenger/enot-docs#@KEYADR@ (как ключ попадает в Core).

## Что сделать

- Миграция схемы `licensing`: тарифы и версии тарифов со стартовой сеткой §5.3 ТЗ, подписки, `signing_keys`, `license_keys` (схема — `enot-docs/docs/db-schema.md`, план миграций 31–33; строка в `TestEmbeddedMigrationsAreValid`, откат — в PR).
- Регистрация публичного ключа `kid` `a250222ae2b479d2` (отпечаток — журнал, «Заметки о площадке»).
- Выпуск ключа подписки строго по ADR-0005, «Уточнение 2026-10-25: формат ключа»: `enot_` + base62(нагрузка ‖ подпись), подпись над `enot-license-v1\n` ‖ нагрузка, лимиты из `tariff_versions.limits`, `null` — без ограничения.
- До биллинга (M5) — выпуск командой оператора с записью в аудит; оплата не нужна.
- Тест совместимости: ключ, выпущенный Core, проходит проверку `enot-community-server/internal/license`; эталон base62 — `TestBase62KnownValues` там же.

Тесты обязательны: лицензирование (AGENTS.md).
EOF

issue REGISTRY enot-backend "type:feature,area:backend,priority:p1" \
	"Реестр сообществ: создание, выдача и смена адреса" <<'EOF'
Этап M3. Зависит от #@LICCORE@ и enot-messenger/enot-docs#@ADDRADR@ (DNS и TLS адреса).

## Что сделать

- `licensing.communities` (миграция по `docs/db-schema.md`).
- Создание сообщества владельцем подписки; выдача и смена `address_slug`: проверка `licensing.AddressPolicy.CheckAddressAllowed` (#91, ошибка `communities.address.reserved`) и уникальности (`conflict`), формат адреса — символы и длина из настроек.
- DNS-запись адреса — по ADR.
- Закрытие: `status = closed`, `purge_after` = +90 дней, фоновая задача освобождает адрес.
- Методы и ошибки — в `docs/protocol.md`; строки ru/en — в задаче клиента.

Тесты: права владельца, служебный и занятый адрес, освобождение после закрытия.
EOF

issue ACTIVATE enot-backend "type:feature,area:backend,priority:p1" \
	"activate и heartbeat сервера сообщества в Core" <<'EOF'
Этап M3. Зависит от #@LICCORE@ и #@REGISTRY@.

## Что сделать (ADR-0005, п. 3–5)

- `activate`: проверка ключа, привязка к fingerprint VPS и адресу, запись в `license_activations`. Другой fingerprint — `fingerprint_mismatch`: перенос в MVP только через поддержку.
- `heartbeat` раз в 15 минут: статус, версия, число участников — в `communities` и `license_checks`; в ответе — состояние ключа (действует, истёк, отозван).
- Аутентификация сервера сообщества (не токен пользователя), rate limit.
- Методы — в `docs/protocol.md`.

Тесты обязательны: лицензирование и права.
EOF

issue SSO enot-backend "type:feature,area:backend,priority:p1" \
	"Вход в сообщества через Core (SSO)" <<'EOF'
Этап M3. Зависит от enot-messenger/enot-docs#@PROTOADR@ (протокол Community Server).

## Что сделать

- Core выдаёт токен доступа к конкретному сообществу (аудитория — адрес сообщества) и публикует ключи проверки; сервер сообщества проверяет токен офлайн.
- Отзыв: блокировка аккаунта и бан в сообществе.
- Методы — в `docs/protocol.md`.

Тесты обязательны: права доступа.
EOF

# --- Сервер сообщества --------------------------------------------------------

issue CSACTIVATE enot-community-server "type:feat,area:community-server,priority:p1" \
	"activate и heartbeat в community-api" <<'EOF'
Этап M3. Зависит от enot-messenger/enot-backend#@ACTIVATE@.

## Что сделать

- Fingerprint VPS: что в него входит, устойчивость к перезагрузке и обновлению образа.
- `activate` при старте в `mode: public`; `heartbeat` раз в 15 минут.
- Без связи с Core до 72 часов — обычная работа, дольше — только чтение (§5.3 ТЗ, ADR-0005).
- Отзыв и окончание подписки — на ближайшем heartbeat.
- `mode: local` — без `activate` (§5.4 ТЗ).
- Состояние — в журнале и в `/healthz`.

Тесты обязательны (лицензирование): часы, ответы Core, переходы состояний.
EOF

issue STRUCTURE enot-community-server "type:feat,area:community-server,priority:p1" \
	"Категории, каналы, роли и права в сообществе" <<'EOF'
Этап M3. Зависит от enot-messenger/enot-docs#@PROTOADR@ и enot-messenger/enot-backend#@SSO@.

## Что сделать (ТЗ §3.3, §5.4)

- PostgreSQL сообщества и миграции (данные владельца: откат описывать); PostgreSQL и Redis — в compose комплекта (образы `community-postgres`, `community-redis` уже опубликованы).
- Категории, текстовые и голосовые каналы; тредов нет. Текстовые сообщения.
- Роли с иерархией; права битовой маской на уровне сообщества, категории и канала.
- Лимиты участников, каналов, категорий и ролей — из ключа подписки, не из кода.
- Локальный режим: доступ владельца и до 10 тестировщиков из `testers.yaml`, перечитывание без перезапуска.

Тесты обязательны: права доступа.
EOF

issue INVITES enot-community-server "type:feat,area:community-server,priority:p2" \
	"Приглашения, бан-лист и аудит-лог сообщества" <<'EOF'
Этап M3. Зависит от #@STRUCTURE@.

## Что сделать (ТЗ §3.3)

- Ссылки-приглашения с лимитом использований и сроком.
- Бан-лист.
- Аудит-лог действий модерации; срок хранения — `audit_retention_days` из ключа подписки.

Тесты обязательны: права доступа.
EOF

issue VOICE enot-community-server "type:feat,area:community-server,area:media,priority:p1" \
	"Голосовые каналы: LiveKit, coturn и Caddy в комплекте" <<'EOF'
Этап M3. Зависит от #@STRUCTURE@ и enot-messenger/enot-docs#@ADDRADR@ (TLS адреса).

## Что сделать

- LiveKit (`community-livekit`), coturn (`community-coturn`), Caddy (`community-caddy`) в compose комплекта: health-check, лимиты ресурсов, порты (7881/tcp, 50000–60000/udp — как в `enot-infra/docs/vps-setup.md` §5).
- Токен LiveKit выдаёт `community-api` с проверкой прав «подключение к голосу», «говорить», «демонстрация экрана».
- Лимит одновременных участников голоса — из ключа подписки.
- Постоянное предупреждение при ретрансляции (AGENTS.md).
- Публичный адрес Garage для браузера через Caddy; правило CORS — строчные заголовки («Грабли» 2026-10-25).
EOF

issue ENOTCTL enot-community-server "type:feat,area:community-server,priority:p2" \
	"enotctl и первый выпуск сервера сообщества" <<'EOF'
Этап M3. Зависит от #@CSACTIVATE@.

## Что сделать

- `enotctl init` (`config.yaml`, `.env`, секреты Garage), `upgrade` (проверка подписи `community-bundle` и образов, бэкап перед обновлением), `backup`, `doctor`, `load` (архив образов с проверкой digest и подписи, ADR-0021 п. 5).
- Первый выпуск кнопкой Release; пакеты `community-api` и `community-bundle` — переключить в Public.
- README, «Установка» — через `enotctl`.
EOF

# --- Клиент и админка ---------------------------------------------------------

issue CLIENT enot-clients "type:feature,area:client,priority:p1" \
	"Сообщества в клиенте" <<'EOF'
Этап M3. Зависит от enot-messenger/enot-docs#@PROTOADR@, enot-messenger/enot-community-server#@STRUCTURE@ и enot-messenger/enot-community-server#@VOICE@.

## Что сделать

- Создание сообщества и выбор адреса; ошибки `communities.address.reserved` и `conflict` — строки ru/en.
- Список сообществ, категории и каналы, текстовые каналы.
- Роли и права в интерфейсе владельца; приглашения.
- Голосовые каналы через SFU (`CALL_TRANSPORT_SFU`), предупреждение о ретрансляции.
- Community Dashboard (§3.4 ТЗ) — по ADR протокола.
- Бюджеты памяти в CI не превышать.

Разбивка на подзадачи — при старте.
EOF

issue ADMINSLUGS enot-admin "type:feat,area:admin,priority:p2" \
	"Служебные адреса сообществ в Enot Admin" <<'EOF'
Отложено решением владельца 2026-10-25, не раньше M5.

Сейчас список `communities.reserved_slugs` правится запросом в `platform.settings` на площадке (журнал, «Заметки о площадке»). В §3.4 ТЗ такого раздела нет: сначала дополнить ТЗ.

- Просмотр, добавление и удаление имён; сравнение без учёта регистра — как в Core.
- Изменения — в аудит-лог действий администраторов.
EOF

echo
echo "Готово. Номера:"
for key in KEYADR ADDRADR PROTOADR LICCORE REGISTRY ACTIVATE SSO CSACTIVATE STRUCTURE INVITES VOICE ENOTCTL CLIENT ADMINSLUGS; do
	echo "  $key ${num[$key]}"
done

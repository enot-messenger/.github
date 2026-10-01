# .github

Общие политики, шаблоны и процессы организации Enot Messenger.

| Путь | Назначение |
| --- | --- |
| `profile/README.md` | Публичная страница организации на GitHub. GitHub читает только этот путь |
| `SECURITY.md` | Порядок сообщения об уязвимостях, сроки реакции |
| `CONTRIBUTING.md` | Процесс разработки: ветки, коммиты, PR, обязательные проверки |
| `CODE_OF_CONDUCT.md` | Правила общения в организации |
| `.github/PULL_REQUEST_TEMPLATE.md` | Шаблон PR с чеклистом |
| `.github/ISSUE_TEMPLATE/` | Формы issue: баг, задача или идея |
| `.github/workflows/reusable-*.yml` | Переиспользуемые workflow для Go, Node и деплоя |

## Документация проекта

- Требования: [`enot-docs/docs/spec.md`](https://github.com/enot-messenger/enot-docs/blob/main/docs/spec.md)
- Правила работы: [`enot-docs/AGENTS.md`](https://github.com/enot-messenger/enot-docs/blob/main/AGENTS.md)
- Журнал проекта: [`enot-docs/docs/journal.md`](https://github.com/enot-messenger/enot-docs/blob/main/docs/journal.md)

## Использование workflow

```yaml
jobs:
  go:
    uses: enot-messenger/.github/.github/workflows/reusable-go.yml@main
    with:
      go-version: "1.26"
```

`reusable-go.yml` выбирает версию golangci-lint по конфигу репозитория: `.golangci.yml` с `version: "2"` проверяется golangci-lint v2 (обязателен для Go 1.25+), конфиг без этой строки — прежним v1.

# Clash Verge Rev — Полный гайд по правилам и конфигурации

> Версия актуальна для **v2.4.7** (апрель 2026)  
> Ядро: **Mihomo** (Clash.Meta)  
> Официальный репозиторий: https://github.com/clash-verge-rev/clash-verge-rev  
> Документация Mihomo: https://wiki.metacubex.one/en/config/rules/

---

## Содержание

1. [Как работают профили](#1-как-работают-профили)
2. [Global Extend (Merge и Script)](#2-global-extend-merge-и-script)
3. [Синтаксис Merge конфига](#3-синтаксис-merge-конфига)
4. [Все типы правил](#4-все-типы-правил)
5. [Bypass by default (как в Throne/sing-box)](#5-bypass-by-default-как-в-thronesing-box)
6. [Правила для процессов (PROCESS-NAME)](#6-правила-для-процессов-process-name)
7. [Готовый конфиг](#7-готовый-конфиг)
8. [Важные замечания](#8-важные-замечания)

---

## 1. Как работают профили

В Clash Verge Rev есть два слоя конфигурации:

**Основной профиль (Remote / Local)** — подписка от сервера или локальный YAML.  
Содержит прокси-серверы, группы и правила маршрутизации.

**Global Extend** — глобальные модификаторы поверх основного профиля:
- **Global Merge** — добавляет/переопределяет правила и настройки через YAML
- **Global Script** — трансформирует конфиг через JavaScript (quickjs)

Global Extend применяется ко **всем** профилям одновременно, независимо от того, какой активен.

---

## 2. Global Extend (Merge и Script)

### Где находится

Страница **Профили** → правый верхний угол → иконка 🔥 (или кнопки `Global Extend Merge` / `Global Extend Script`).

В v2.4.7 при нажатии **Новый** в диалоге доступны только **Remote** и **Local**.  
Merge и Script — это отдельная глобальная секция, не создаётся через кнопку "Новый".

### Активация

После редактирования Merge-конфига обязательно нажать **disable → enable** (или кнопку 🔥), иначе изменения не применятся.

---

## 3. Синтаксис Merge конфига

```yaml
# Добавить правила ПЕРЕД правилами подписки (высший приоритет)
prepend-rules:
  - RULE_TYPE,value,TARGET

# Добавить правила ПОСЛЕ правил подписки (низший приоритет — бесполезно если есть MATCH)
append-rules:
  - RULE_TYPE,value,TARGET

# Добавить прокси-серверы
prepend-proxies: []
append-proxies: []

# Добавить группы прокси
prepend-proxy-groups: []
append-proxy-groups: []

# Переопределить любую секцию оригинального конфига
rules:
  - MATCH,DIRECT
```

> **Важно:** `prepend-rules` вставляет правила **до** `MATCH` из подписки.  
> `append-rules` вставляет **после** `MATCH` — такие правила никогда не сработают.  
> Для bypass by default нужно переопределить `rules: - MATCH,DIRECT` напрямую.

> **Нельзя переопределить:** `mixed-port`, `log-level`, `external-controller`, `dns.enable` в TUN-режиме — эти параметры контролирует сам Clash Verge Rev.

---

## 4. Все типы правил

Формат: `ТИП,значение,ЦЕЛЬ[,опции]`

Цель: имя прокси-группы из подписки (например `Proxy`, `🚀 Узел выбора`) или `DIRECT` / `REJECT`.

### Доменные правила

| Тип | Пример | Описание |
|---|---|---|
| `DOMAIN` | `DOMAIN,api.openai.com,Proxy` | Точное совпадение домена |
| `DOMAIN-SUFFIX` | `DOMAIN-SUFFIX,google.com,Proxy` | Домен и все поддомены |
| `DOMAIN-KEYWORD` | `DOMAIN-KEYWORD,youtube,Proxy` | Содержит ключевое слово |
| `DOMAIN-WILDCARD` | `DOMAIN-WILDCARD,*.google.*,Proxy` | Wildcard-паттерн |
| `DOMAIN-REGEX` | `DOMAIN-REGEX,^ads\.,REJECT` | Регулярное выражение |
| `GEOSITE` | `GEOSITE,youtube,Proxy` | Встроенный список сайтов |

### IP-правила

| Тип | Пример | Описание |
|---|---|---|
| `IP-CIDR` | `IP-CIDR,192.168.0.0/16,DIRECT,no-resolve` | Диапазон IPv4 |
| `IP-CIDR6` | `IP-CIDR6,::1/128,DIRECT,no-resolve` | Диапазон IPv6 |
| `GEOIP` | `GEOIP,private,DIRECT,no-resolve` | Страна или категория IP |
| `IP-ASN` | `IP-ASN,13335,DIRECT` | Автономная система |

> `no-resolve` — не резолвить домен для IP-правил (рекомендуется всегда добавлять к GEOIP/IP-CIDR).

### Правила для процессов (только Windows/macOS/Linux десктоп)

| Тип | Пример | Описание |
|---|---|---|
| `PROCESS-NAME` | `PROCESS-NAME,telegram.exe,DIRECT` | По имени процесса |
| `PROCESS-NAME-WILDCARD` | `PROCESS-NAME-WILDCARD,steam*,DIRECT` | Wildcard по имени |
| `PROCESS-PATH` | `PROCESS-PATH,C:\Program Files\...,DIRECT` | По полному пути |

> Для работы PROCESS-NAME нужно включить в **Настройках**: `Find Process Mode` → `always` или `strict`.  
> В System Proxy режиме правила процессов не работают — только в TUN-режиме.

### Портовые правила

| Тип | Пример | Описание |
|---|---|---|
| `DST-PORT` | `DST-PORT,443,Proxy` | Порт назначения |
| `SRC-PORT` | `SRC-PORT,7777,DIRECT` | Порт источника |

### Итоговое правило

| Тип | Пример | Описание |
|---|---|---|
| `MATCH` | `MATCH,DIRECT` | Всё что не попало в правила выше |

### Полезные GEOSITE категории

| Категория | Описание |
|---|---|
| `youtube` | YouTube |
| `google` | Google сервисы |
| `telegram` | Telegram |
| `twitter` | Twitter/X |
| `openai` | ChatGPT, OpenAI |
| `gfw` | Общий список заблокированных (для Китая, частично РФ) |
| `private` | Локальные адреса (127.x, 192.168.x и т.д.) |
| `category-ads-all` | Рекламные домены |

### Полезные GEOIP категории

| Категория | Описание |
|---|---|
| `private` | Приватные IP-диапазоны |
| `telegram` | IP-диапазоны Telegram |
| `IL` | Израиль |
| `RU` | Россия |
| `CN` | Китай |

---

## 5. Bypass by default (как в Throne/sing-box)

Логика: всё идёт напрямую, кроме явно указанных заблокированных сайтов.

В Throne (sing-box) это поведение по умолчанию — `direct` как финальное правило.  
В Clash это реализуется через переопределение `MATCH` на `DIRECT`.

```yaml
profile:
  store-selected: true  # запоминать выбранный узел между перезапусками

prepend-rules:
  # Локальные адреса — всегда напрямую
  - GEOIP,private,DIRECT,no-resolve

  # Заблокированные ресурсы — через прокси
  - GEOSITE,youtube,Proxy
  - GEOSITE,google,Proxy
  - GEOSITE,telegram,Proxy
  - GEOSITE,twitter,Proxy
  - GEOSITE,openai,Proxy
  - GEOSITE,gfw,Proxy

# Переопределяем финальное правило подписки
rules:
  - MATCH,DIRECT
```

> Замени `Proxy` на точное название группы из твоей подписки.  
> Название видно на странице **Прокси** — например `🚀 Узел выбора` или просто `Proxy`.

---

## 6. Правила для процессов (PROCESS-NAME)

### Требования

1. Режим **TUN** должен быть включён (System Proxy не перехватывает трафик процессов).
2. В **Настройки** → найти `Find Process Mode` → поставить `always` или `strict`.

### Пример

```yaml
prepend-rules:
  # Игры — напрямую
  - PROCESS-NAME,steam.exe,DIRECT
  - PROCESS-NAME,steamwebhelper.exe,DIRECT
  - PROCESS-NAME-WILDCARD,division*,DIRECT

  # Мессенджеры — через прокси
  - PROCESS-NAME,Telegram.exe,Proxy

  # Остальные правила...
  - GEOIP,private,DIRECT,no-resolve
  - GEOSITE,youtube,Proxy
  - GEOSITE,gfw,Proxy

rules:
  - MATCH,DIRECT
```

> На Windows имена процессов **без учёта регистра** (telegram.exe = Telegram.exe).  
> На macOS/Linux — с учётом регистра.

---

## 7. Готовый конфиг

Минимальный рабочий Merge конфиг с bypass by default:

```yaml
profile:
  store-selected: true

prepend-rules:
  # === Кастомные правила (правь под себя) ===
  # - DOMAIN-SUFFIX,example.com,DIRECT
  # - PROCESS-NAME,telegram.exe,Proxy

  # === Локальная сеть ===
  - GEOIP,private,DIRECT,no-resolve

  # === Заблокированные → прокси ===
  - GEOSITE,youtube,Proxy
  - GEOSITE,google,Proxy
  - GEOSITE,telegram,Proxy
  - GEOSITE,twitter,Proxy
  - GEOSITE,openai,Proxy
  - GEOSITE,gfw,Proxy

# Bypass by default — всё остальное напрямую
rules:
  - MATCH,DIRECT
```

---

## 8. Важные замечания

**После любого изменения Merge конфига** → нажми disable затем enable (или кнопку 🔥) на странице Профили. Без этого изменения не применятся.

**Название прокси-группы** должно совпадать **точно** с тем, что в подписке, включая эмодзи. Проверяй на странице Прокси.

**`prepend-rule-providers` и `append-rule-providers`** были убраны в версии v1.6.2. Вместо них используется просто `rule-providers` (работает как append).

**`rules: - MATCH,DIRECT`** переопределяет только секцию `rules` целиком. Если в подписке был `MATCH,Proxy` — он заменится на `MATCH,DIRECT`.

**PROCESS-NAME работает только в TUN-режиме.** В System Proxy трафик перехватывается на уровне HTTP/SOCKS — процессы не различаются.

**GEOSITE и GEOIP** используют файлы геоданных из `MetaCubeX/meta-rules-dat`. Обновляются автоматически. Если правило не срабатывает — проверь что файлы скачались (Настройки → Обновить геоданные).

---

*Источники: [clashvergerev.com/en/guide/merge](https://clashvergerev.com/en/guide/merge) · [wiki.metacubex.one/en/config/rules](https://wiki.metacubex.one/en/config/rules/) · [github.com/clash-verge-rev/clash-verge-rev](https://github.com/clash-verge-rev/clash-verge-rev)*

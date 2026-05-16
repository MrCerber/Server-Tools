<div align="center">

# 🖥️ Server Tools

**Интерактивный bootstrap-скрипт для свежего сервера Ubuntu / Debian**

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420?style=flat-square&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-Personal-blue?style=flat-square)](#)
[![Root](https://img.shields.io/badge/Requires-root-critical?style=flat-square)](#)

</div>

---

## О проекте

Один скрипт — полная начальная настройка сервера. Устанавливает базовые пакеты, настраивает файрвол, Fail2ban, кастомный MOTD и shell-алиасы. Всё через интерактивное меню с цветным выводом и логированием.

- 📦 Обновляет пакеты и устанавливает базовый набор утилит
- 🔄 Настраивает автоматические security-обновления
- 👤 Создаёт sudo-пользователя с SSH-ключом
- 💾 Настраивает swap-файл с persist в fstab
- 🛡️ Управляет UFW и Fail2ban через интерактивные подменю
- 🔑 Подменю SSH: смена порта, отключение парольной аутентификации, ограничение root-входа
- 🔒 Хардение ядра через sysctl: защита от SYN-флуда, IP-спуфинга, ICMP-редиректов
- 🐳 Устанавливает Docker через официальный скрипт
- 🖥️ Устанавливает кастомный MOTD с системной информацией и запущенными контейнерами
- 🗂️ Запускает утилиты из папки `scripts/` через отдельное подменю
- 🌐 Устанавливает 1Panel через встроенный установщик
- ⏰ Настраивает cron для автоматической перезагрузки при обновлении ядра
- ⚡ Добавляет полезные алиасы в `.bashrc`
- 🧹 Очищает APT-кэш и удаляет неиспользуемые пакеты
- 📝 Логирует все действия и создаёт резервные копии

---

## Быстрый старт

```bash
bash <(curl -Ls https://raw.githubusercontent.com/MrCerber/Server-Tools/refs/heads/main/install.sh)
```

> [!IMPORTANT]
> Скрипт запускается **от root**. SSH-ключи должны быть установлены заранее.

---

## Требования

| Требование | |
|---|---|
| **ОС** | Ubuntu / Debian *(другие дистрибутивы — на свой страх и риск)* |
| **Права** | root |
| **Интернет** | нужен для установки пакетов и загрузки MOTD |

---

## Скриншот

![Server Tools](image.png)

---

## Меню

При запуске открывается интерактивное цветное меню со статусом сервисов в реальном времени.

<details>
<summary><b>📋 Показать структуру меню</b></summary>
<br>

```
  MrCerber — New Server Bootstrap
  UFW: active        Fail2ban: active
  ────────────────────────────────────────────────────

  System
    1)  Full base setup          update + packages + auto-updates
    2)  Update / upgrade only    apt-get update && upgrade
    3)  Install base packages    curl, git, htop, btop, jq, ufw...
    4)  Enable auto-updates      unattended-upgrades
    5)  Create sudo user         add non-root user with sudo + SSH key
    6)  Setup swap               create /swapfile + persist in fstab

  MOTD & SSH
    7)  Install custom MOTD      disable default + install 99-mrcerber
    8)  Restore default MOTD     re-enable system MOTD scripts
    9)  Preview MOTD             run-parts /etc/update-motd.d
   10)  SSH submenu              port, password auth, root login hardening

  Security
   11)  UFW submenu              firewall rules & management
   12)  Fail2ban submenu         SSH brute-force protection
   13)  Kernel hardening         sysctl: SYN cookies, anti-spoof, redirects

  Panels
   14)  Install Docker           official get.docker.com installer
   15)  Install 1Panel           web-based server management panel

  Extras
   16)  Install aliases          bench, geoip  ->  /root/.bashrc
   17)  APT cleanup              autoremove + clean apt cache
   18)  Auto-reboot cron         install/manage Cron/Restart.sh
   19)  Show action log          last 20 entries from bootstrap log

  Scripts
   20)  Scripts submenu          run utility scripts (DNS, BBR...)

    0)  Exit
```

</details>

---

## Функции

<details>
<summary><b>📦 Full base setup</b></summary>
<br>

Запускает три шага последовательно и выводит итоговый summary:

1. `apt-get update && apt-get upgrade`
2. Установка базовых пакетов
3. Включение `unattended-upgrades`

**Устанавливаемые пакеты:**

```
ca-certificates  curl        wget       gnupg        lsb-release
unzip            zip         tar        nano         vim
htop             btop        net-tools  iproute2     dnsutils
jq               git         ufw        fail2ban
unattended-upgrades          apt-listchanges          openssh-server
```

</details>

<details>
<summary><b>👤 Create sudo user</b></summary>
<br>

Создаёт нового пользователя с правами sudo — для работы без прямого входа под root.

1. Запрашивает имя пользователя и создаёт его через `adduser`
2. Добавляет в группу `sudo`
3. Опционально устанавливает SSH-публичный ключ в `~/.ssh/authorized_keys`

</details>

<details>
<summary><b>💾 Setup swap</b></summary>
<br>

Настраивает swap-файл — полезно для VPS с небольшим объёмом RAM (1–2 ГБ).

1. Проверяет, не настроен ли swap уже (с предложением заменить)
2. Запрашивает размер файла (например: `1G`, `2G`, `512M`)
3. Создаёт `/swapfile` через `fallocate` (fallback на `dd`)
4. Прописывает в `/etc/fstab` для автомонтирования при перезагрузке
5. Устанавливает `vm.swappiness=10` и `vm.vfs_cache_pressure=50` через sysctl

</details>

<details>
<summary><b>🖥️ Кастомный MOTD</b></summary>
<br>

При SSH-входе вместо стандартного MOTD отображается:

```
  System
  ────────────────────────────────────────────────────
    Host          server01
    IP            1.2.3.4
    OS            Ubuntu 22.04.3 LTS
    Kernel        5.15.0-91-generic
    Uptime        up 3 days, 2 hours, 15 minutes
    CPU           Intel Xeon E5-2680  (8 cores / 16 threads)
    Load          0.12 / 0.08 / 0.05  (1m/5m/15m)
    Load%         1%  (normalized: 0.01 per thread)
    RAM           1.2G / 8.0G
    Last Login    root from 10.0.0.1 at Mon Jan 6 12:00:00 2025

  Storage
  ────────────────────────────────────────────────────
    Disk /        [████████░░░░░░░░░░░░░░░░]  33%  (16G/48G)

  Services
  ────────────────────────────────────────────────────
    docker: ● active   fail2ban: ● active   ufw: ● active

  Containers
  ────────────────────────────────────────────────────
    nginx-proxy          Up 2 days             nginx:latest
    app                  Up 5 hours            myapp:v1.2

  Updates
  ────────────────────────────────────────────────────
    Status        System is up to date
```

Секция **Containers** отображается только если Docker установлен и запущен.
Файлы `99-mrcerber` и `logo.txt` берутся из папки рядом со скриптом.
Если не найдены — скачиваются автоматически с GitHub.

</details>

<details>
<summary><b>🔑 SSH submenu — хардение SSH</b></summary>
<br>

| Пункт | Действие |
|---|---|
| Status | показать текущие настройки sshd_config (порт, auth, root login) |
| Disable password auth | `PasswordAuthentication no` — только ключи |
| Restrict root login | `PermitRootLogin prohibit-password` — root только по ключу |
| Change SSH port | сменить порт в sshd_config |

Все операции делают бэкап файла, проверяют конфиг через `sshd -t` перед перезагрузкой и автоматически восстанавливают бэкап при ошибке.

> [!WARNING]
> Отключение парольной аутентификации заблокирует SSH-вход по паролю. Убедитесь, что SSH-ключ установлен перед применением.

</details>

<details>
<summary><b>🔒 Kernel hardening — хардение ядра</b></summary>
<br>

Записывает параметры безопасности в `/etc/sysctl.d/99-mrcerber-hardening.conf` и применяет через `sysctl --system`.

| Параметр | Назначение |
|---|---|
| `tcp_syncookies = 1` | Защита от SYN-флуда |
| `accept_source_route = 0` | Запрет IP source routing |
| `accept_redirects = 0` | Запрет входящих ICMP-редиректов |
| `send_redirects = 0` | Запрет исходящих ICMP-редиректов |
| `rp_filter = 1` | Reverse path filtering (защита от IP-спуфинга) |
| `log_martians = 1` | Логирование подозрительных пакетов |
| `ipv6 forwarding = 0` | Отключение IPv6-форвардинга |

Операция идемпотентна: повторный запуск покажет предупреждение и запросит подтверждение перезаписи.

</details>

<details>
<summary><b>🛡️ UFW — управление файрволом</b></summary>
<br>

| Пункт | Действие |
|---|---|
| Status | `ufw status verbose` |
| Apply defaults | `deny incoming` / `allow outgoing` |
| Allow SSH | открыть `22/tcp` |
| Allow HTTP+HTTPS | открыть `80` + `443` |
| Allow custom port | ввести порт и протокол (tcp / udp / both) |
| Allow from IP/CIDR | открыть порт только для конкретного IP или подсети |
| Delete rule | удалить правило по номеру |
| Enable / Disable | включить / выключить UFW |
| Reset | сбросить все правила *(с подтверждением)* |

</details>

<details>
<summary><b>🚫 Fail2ban — защита SSH</b></summary>
<br>

| Пункт | Действие |
|---|---|
| Install + enable | установить и запустить сервис |
| Configure SSH jail | записать `/etc/fail2ban/jail.local` |
| Status | статус сервиса + sshd jail |
| Unban IP | разбанить IP из sshd jail |

Конфигурация `jail.local` — VPS-уровень защиты:

```ini
[DEFAULT]
# Прогрессивные баны: каждый повтор × 24
bantime.increment  = true
bantime.multiplier = 24
bantime.maxtime    = 720h    ; максимум 30 дней
bantime            = 1h      ; первый бан
findtime           = 10m
maxretry           = 3
backend            = systemd
banaction          = ufw
ignoreip           = 127.0.0.1/8 ::1

[sshd]
enabled = true
mode    = aggressive         ; ловит pre-auth флуд

[recidive]
enabled  = true
bantime  = 720h              ; 30 дней для рецидивистов
findtime = 1d
maxretry = 5
```

</details>

<details>
<summary><b>🐳 Panels — Docker и 1Panel</b></summary>
<br>

**Docker** — устанавливается через официальный скрипт `get.docker.com`. Перед запуском показывает URL источника и запрашивает подтверждение. Если Docker уже установлен — предлагает переустановку.

**1Panel** — современная веб-панель управления сервером с поддержкой Docker, сайтов, баз данных и мониторинга. Устанавливается через официальный инсталлятор.

</details>

<details>
<summary><b>⏰ Auto-reboot cron</b></summary>
<br>

Устанавливает скрипт `Cron/Restart.sh` как cron-задачу для автоматической перезагрузки при наличии ожидающих обновлений ядра.

- Скрипт копируется в `/usr/local/sbin/mrcerber-auto-reboot.sh`
- Cron-файл создаётся в `/etc/cron.d/mrcerber-auto-reboot` (запуск каждый час)
- Лог пишется в `/var/log/mrcerber-auto-reboot.log`
- Перезагружает только при наличии файла `/var/run/reboot-required`

Через тот же пункт меню можно отключить cron или переустановить.

</details>

<details>
<summary><b>⚡ Scripts — утилиты</b></summary>
<br>

Подменю запускает скрипты из папки `scripts/` рядом со скриптом.

| Скрипт | Описание |
|---|---|
| **Cloudflare DNS Manager** | Интерактивный менеджер A-записей Cloudflare (просмотр, добавление, редактирование, удаление) |
| **Enable BBR** | Включает TCP BBR + fq на уровне ядра для оптимизации пропускной способности |

Скрипты также можно запустить напрямую из папки `scripts/`. Подробности — в [`scripts/README.md`](scripts/README.md).

</details>

<details>
<summary><b>🧹 APT cleanup</b></summary>
<br>

Освобождает место на диске:

1. `apt-get autoremove` — удаляет неиспользуемые зависимости
2. `apt-get clean` — очищает кэш загруженных пакетов

Выводит размер кэша до и после очистки.

</details>

<details>
<summary><b>⚡ Алиасы</b></summary>
<br>

Добавляет в `/root/.bashrc` (только если алиас ещё не существует):

```bash
# Быстрый тест производительности сервера
alias bench='wget -qO- bench.sh | bash'

# Геолокация текущего IP
alias geoip='bash <(wget -qO- https://github.com/vernette/ipregion/raw/master/ipregion.sh)'
```

После установки применить в текущей сессии:

```bash
source ~/.bashrc
```

</details>

---

## Безопасность и надёжность

| Механизм | Детали |
|---|---|
| **Резервные копии** | Каждый изменяемый файл бэкапится в `/root/.mrcerber-bootstrap-backups/` с timestamp |
| **Логирование** | Все действия пишутся в `/root/.mrcerber-bootstrap.log` |
| **Подтверждение** | Деструктивные операции требуют явного `[y/N]` |
| **Проверка OS** | Предупреждение при запуске не на Ubuntu / Debian |
| **Проверка сети** | Ping-тест перед загрузкой файлов |
| **Идемпотентность** | Большинство операций безопасно запускать повторно |
| **Блокировка параллельного запуска** | `flock` предотвращает одновременный запуск двух копий скрипта |
| **Валидация SSH-конфига** | `sshd -t` проверяет конфиг перед перезагрузкой; при ошибке бэкап восстанавливается автоматически |
| **Таймаут загрузки** | `curl --max-time 30` предотвращает зависание при медленном соединении |

<details>
<summary><b>📄 Пример лога</b></summary>
<br>

```
[2025-01-06 12:00:01] OS check passed: Ubuntu 22.04.3 LTS
[2025-01-06 12:00:05] full_base_setup START
[2025-01-06 12:00:05] apt-get update
[2025-01-06 12:01:30] apt-get upgrade
[2025-01-06 12:02:10] install_base_packages
[2025-01-06 12:03:45] enable_auto_updates
[2025-01-06 12:03:46] full_base_setup END (221s)
[2025-01-06 12:05:10] install_custom_motd
[2025-01-06 12:05:11] disable_last_login
[2025-01-06 12:05:30] ufw allow 22/tcp
[2025-01-06 12:05:35] ufw enable
[2025-01-06 12:06:00] create_sudo_user deploy
[2025-01-06 12:06:01] ssh key added for deploy
[2025-01-06 12:06:30] setup_swap 2G
[2025-01-06 12:07:00] apply_sysctl_hardening
[2025-01-06 12:07:05] ssh_disable_password_auth
[2025-01-06 12:07:10] install_docker START
[2025-01-06 12:08:45] install_docker END
[2025-01-06 12:09:00] setup_auto_reboot_cron ENABLED
```

</details>

---

## Структура проекта

```
Server-Tools/
├── install.sh        # Главный скрипт с интерактивным меню
├── 99-mrcerber       # Скрипт кастомного MOTD
├── logo.txt          # ASCII-арт логотип для MOTD
├── README.md         # Документация
├── Cron/
│   └── Restart.sh    # Скрипт автоматической перезагрузки (cron)
└── scripts/
    ├── cf_dns_manager.sh   # Менеджер DNS-записей Cloudflare
    ├── enable_bbr.sh       # Включение TCP BBR
    └── README.md           # Документация скриптов
```

---

<div align="center">

Сделано с ❤️ **MrCerber**

</div>

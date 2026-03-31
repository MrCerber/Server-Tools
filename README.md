<div align="center">

```
              ___          _
  /\/\  _ __ / __\___ _ __| |__   ___ _ __
 /    \| '__/ /  / _ \ '__| '_ \ / _ \ '__|
/ /\/\ \ | / /__|  __/ |  | |_) |  __/ |
\/    \/_| \____/\___|_|  |_.__/ \___|_|

     __     _                      _
  /\ \ \___| |___      _____  _ __| | __
 /  \/ / _ \ __\ \ /\ / / _ \| '__| |/ /
/ /\  /  __/ |_ \ V  V / (_) | |  |   <
\_\ \/ \___|\__| \_/\_/ \___/|_|  |_|\_\
```

# Server Tools

**Интерактивный bootstrap-скрипт для свежего сервера Ubuntu / Debian**

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![License](https://img.shields.io/badge/License-Personal-blue?style=flat-square)
![Root](https://img.shields.io/badge/Requires-root-red?style=flat-square)

</div>

---

## О проекте

Один скрипт — полная начальная настройка сервера. Устанавливает базовые пакеты, настраивает файрвол, Fail2ban, кастомный MOTD и shell-алиасы. Всё через интерактивное меню с цветным выводом и логированием.

**Что делает скрипт:**

- 📦 Обновляет пакеты и устанавливает базовый набор утилит
- 🔄 Настраивает автоматические security-обновления
- 🛡️ Управляет UFW и Fail2ban через удобные подменю
- 🖥️ Устанавливает кастомный MOTD с системной информацией
- ⚡ Добавляет полезные алиасы в `.bashrc`
- 📝 Логирует все действия и создаёт резервные копии

---

## Быстрый старт

```bash
git clone https://github.com/MrCerber/Server-Tools.git
cd Server-Tools
bash install.sh
```

> [!IMPORTANT]
> Скрипт должен запускаться **от root**. SSH-ключи должны быть установлены заранее.

---

## Требования

| | |
|---|---|
| **ОС** | Ubuntu / Debian *(другие дистрибутивы — на свой страх и риск)* |
| **Права** | root |
| **Интернет** | нужен для установки пакетов и загрузки MOTD |

---

## Меню

При запуске открывается интерактивное цветное меню со статусом сервисов в реальном времени:

```
  MrCerber — New Server Bootstrap
  --------------------------------------------------
  UFW: active        Fail2ban: active

  System
    1)  Full base setup          update + packages + auto-updates
    2)  Update / upgrade only    apt-get update && upgrade
    3)  Install base packages    curl, git, htop, btop, jq, ufw...
    4)  Enable auto-updates      unattended-upgrades

  MOTD & SSH
    5)  Install custom MOTD      disable default + install 99-mrcerber
    6)  Restore default MOTD     re-enable system MOTD scripts
    7)  Preview MOTD             run-parts /etc/update-motd.d

  Security
    8)  UFW submenu              firewall rules & management
    9)  Fail2ban submenu         SSH brute-force protection

  Extras
   10)  Install aliases          bench, geoip  ->  /root/.bashrc
   11)  Show action log          last 20 entries from bootstrap log

    0)  Exit
```

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
<summary><b>🖥️ Кастомный MOTD</b></summary>
<br>

При SSH-входе вместо стандартного MOTD отображается:

```
              ___          _
  /\/\  _ __ / __\___ _ __| |__   ___ _ __
 /    \| '__/ /  / _ \ '__| '_ \ / _ \ '__|
...

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
    docker: ○ inactive   fail2ban: ● active   ufw: ● active

  Updates
  ────────────────────────────────────────────────────
    Status        System is up to date
```

Файлы `99-mrcerber` и `logo.txt` берутся из папки рядом со скриптом.
Если не найдены — скачиваются автоматически с GitHub.

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

Конфигурация `jail.local` по умолчанию:

```ini
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
banaction = ufw

[sshd]
enabled = true
mode    = normal
```

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
| **Проверка OS** | Предупреждение при запуске не на Ubuntu/Debian |
| **Проверка сети** | Ping-тест перед загрузкой файлов |
| **Идемпотентность** | Большинство операций безопасно запускать повторно |

**Пример лога:**
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
```

---

## Структура проекта

```
Server-Tools/
├── install.sh        # Главный скрипт с интерактивным меню
├── 99-mrcerber       # Скрипт кастомного MOTD
├── logo.txt          # ASCII-арт логотип для MOTD
├── CLAUDE.md         # Контекст проекта для Claude Code
└── README.md         # Документация
```

---

<div align="center">

Сделано с ❤️ **MrCerber**

</div>

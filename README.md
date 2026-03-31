# MrCerber — Server Tools

Интерактивный bash-инструмент для первоначальной настройки свежего сервера Ubuntu/Debian.
Запускается один раз после деплоя — приводит сервер в рабочее состояние за несколько минут.

---

## Возможности

- Обновление пакетов и установка базового набора утилит
- Настройка автоматических security-обновлений (`unattended-upgrades`)
- Управление файрволом UFW через интерактивное меню
- Защита SSH от брутфорса через Fail2ban
- Установка кастомного MOTD с системной информацией при входе
- Установка полезных shell-алиасов (`bench`, `geoip`)
- Логирование всех действий
- Резервное копирование всех изменяемых файлов

---

## Требования

| Требование | Детали |
|---|---|
| ОС | Ubuntu / Debian (другие — на свой страх и риск) |
| Права | Запуск **только от root** |
| SSH-ключи | Должны быть установлены до запуска |

---

## Быстрый старт

```bash
# Клонировать репозиторий
git clone https://github.com/MrCerber/Server-Tools.git
cd Server-Tools

# Запустить
bash install.sh
```

Скрипт проверит ОС и откроет интерактивное меню.

---

## Структура файлов

```
Server-Tools/
├── install.sh       # Главный скрипт с интерактивным меню
├── 99-mrcerber      # Скрипт кастомного MOTD
├── logo.txt         # ASCII-арт логотип для MOTD
├── CLAUDE.md        # Контекст для Claude Code
└── README.md        # Этот файл
```

---

## Меню

```
MrCerber — New Server Bootstrap
──────────────────────────────────────────────────
UFW: active   Fail2ban: active

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

## Детали функций

### 1. Full base setup

Выполняет три шага за один раз:
1. `apt-get update && apt-get upgrade`
2. Установка базовых пакетов
3. Включение автоматических обновлений

По завершении выводит summary с временем выполнения.

**Устанавливаемые пакеты:**
`ca-certificates` `curl` `wget` `gnupg` `lsb-release` `unzip` `zip` `tar`
`nano` `vim` `htop` `btop` `net-tools` `iproute2` `dnsutils` `jq` `git`
`ufw` `fail2ban` `unattended-upgrades` `apt-listchanges` `openssh-server`

---

### 4. Автообновления

Настраивает `unattended-upgrades` для автоматической установки security-патчей.
Конфигурация — консервативная: только security и important updates, **без автоматической перезагрузки**.

---

### 5. Кастомный MOTD

При SSH-входе отображает:

```
              ___          _
  /\/\  _ __ / __\___ _ __| |__   ___ _ __
 /    \| '__/ /  / _ \ '__| '_ \ / _ \ '__|
...

  System
  ────────────────────────────────────────────────
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
  ────────────────────────────────────────────────
    Disk /        [████████░░░░░░░░░░░░░░░░]  33%  (16G/48G)

  Services
  ────────────────────────────────────────────────
    docker: ○ inactive   fail2ban: ● active   ufw: ● active

  Updates
  ────────────────────────────────────────────────
    Status        System is up to date
```

Если файлы `99-mrcerber` и `logo.txt` не найдены рядом со скриптом — они автоматически скачиваются с GitHub.

---

### 8. UFW Submenu

| Пункт | Действие |
|---|---|
| Status | `ufw status verbose` |
| Apply defaults | `deny incoming` / `allow outgoing` |
| Allow SSH | открыть `22/tcp` |
| Allow HTTP+HTTPS | открыть `80` + `443` |
| Allow custom port | ввести порт и протокол (tcp/udp/both) |
| Delete rule | удалить правило по номеру |
| Enable / Disable | включить/выключить UFW |
| Reset | сбросить все правила (с подтверждением) |

---

### 9. Fail2ban Submenu

| Пункт | Действие |
|---|---|
| Install + enable | установить и запустить сервис |
| Configure SSH jail | записать `/etc/fail2ban/jail.local` |
| Status | статус сервиса + sshd jail |
| Unban IP | разбанить IP из sshd jail |

**jail.local по умолчанию:**
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

---

### 10. Алиасы

Добавляет в `/root/.bashrc` (только если алиас ещё не существует):

```bash
alias bench='wget -qO- bench.sh | bash'
alias geoip='bash <(wget -qO- https://github.com/vernette/ipregion/raw/master/ipregion.sh)'
```

После установки применить в текущей сессии:
```bash
source ~/.bashrc
```

---

## Безопасность

- Перед каждым изменением системного файла создаётся резервная копия в `/root/.mrcerber-bootstrap-backups/`
- Все деструктивные операции требуют явного подтверждения `[y/N]`
- Все действия логируются в `/root/.mrcerber-bootstrap.log`
- Проверка интернет-соединения перед попыткой скачивания

---

## Логирование

Каждое действие пишется в `/root/.mrcerber-bootstrap.log`:

```
[2025-01-06 12:00:01] OS check passed: Ubuntu 22.04.3 LTS
[2025-01-06 12:00:05] full_base_setup START
[2025-01-06 12:00:05] apt-get update
[2025-01-06 12:01:30] apt-get upgrade
[2025-01-06 12:02:10] install_base_packages
[2025-01-06 12:03:45] enable_auto_updates
[2025-01-06 12:03:46] full_base_setup END (221s)
```

Просмотр последних 20 записей — пункт `11` в главном меню.

---

## Резервные копии

Все бэкапы хранятся в `/root/.mrcerber-bootstrap-backups/` с временными метками:

```
/root/.mrcerber-bootstrap-backups/
├── etc__ssh__sshd_config.20250106-120001.bak
├── etc__update-motd.d.20250106-120010.tar.gz
└── etc__apt__apt.conf.d__20auto-upgrades.20250106-120045.bak
```

---

## Автор

**MrCerber** — [github.com/MrCerber](https://github.com/MrCerber)

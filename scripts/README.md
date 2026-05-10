<div align="center">

# 🖥️ Server Scripts

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square\&logo=gnubash\&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-E95420?style=flat-square\&logo=ubuntu\&logoColor=white)](https://ubuntu.com/)
[![Root](https://img.shields.io/badge/Requires-root-critical?style=flat-square)](#)

Набор полезных bash-скриптов для управления сервером.

</div>

---

# 📂 Скрипты

## 🌐 Cloudflare DNS Manager

Интерактивный менеджер DNS-записей Cloudflare.

### Возможности

* Просмотр всех доменов и A-записей
* Добавление новых A-записей
* Редактирование существующих записей
* Удаление записей
* Поддержка:

  * API Token
  * Global API Key

### Установка и запуск

```bash
wget -O cf_dns_manager.sh https://raw.githubusercontent.com/MrCerber/Server-Tools/main/scripts/cf_dns_manager.sh && \
chmod +x cf_dns_manager.sh && \
nano cf_dns_manager.sh
```

Заполните данные Cloudflare в начале файла:

```bash
# Use Email with Global API Key 
# Or Use DNS Zone API Token
CF_EMAIL=""
CF_API_KEY="" # Global API Key
#OR
CF_API_TOKEN=""
```

Запуск:

```bash
./cf_dns_manager.sh
```

---

## 🚀 Enable BBR

Скрипт для быстрого включения TCP BBR на Ubuntu/Debian.

### Что делает

* Загружает модуль `tcp_bbr`
* Настраивает `fq`
* Создаёт конфиг в `/etc/sysctl.d/99-bbr.conf`
* Применяет настройки автоматически

### Установка и запуск

```bash
wget -O enable_bbr.sh https://raw.githubusercontent.com/MrCerber/Server-Tools/main/scripts/enable_bbr.sh && \
chmod +x enable_bbr.sh && \
sudo ./enable_bbr.sh
```

### Требования

* Linux kernel 4.9+
* Root доступ

---

# ⚡ Требования

Установленные пакеты:

```bash
apt install curl jq -y
```

---

<div align="center">

Сделано с ❤️ **MrCerber**

</div>

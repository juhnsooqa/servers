#!/bin/bash

# === ЦВЕТА ДЛЯ ВЫВОДА ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Установка roscom.dat для Remnawave ===${NC}"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

# === ПОИСК ДИРЕКТОРИИ REMNAWAVE ===
echo -e "${BLUE}Поиск директории Remnawave...${NC}"

# Ищем docker-compose.yml с контейнером remnanode
FOUND_COMPOSE=$(find / -name "docker-compose.yml" -type f 2>/dev/null | while read -r file; do
    if grep -q "remnanode\|remnawave" "$file" 2>/dev/null; then
        echo "$file"
        break
    fi
done)

if [ -z "$FOUND_COMPOSE" ]; then
    echo -e "${YELLOW}Не удалось автоматически найти docker-compose.yml для Remnawave.${NC}"
    echo -e "${YELLOW}Пожалуйста, укажите путь к директории с docker-compose.yml:${NC}"
    echo -e "${BLUE}Примеры: /root/remnawave, /opt/remnawave, /etc/remnawave${NC}"
    read -p "Путь к директории: " WORK_DIR
else
    WORK_DIR=$(dirname "$FOUND_COMPOSE")
    echo -e "${GREEN}✓ Найдена директория: $WORK_DIR${NC}"
    echo -e "${YELLOW}Это правильная директория? (y/n)${NC}"
    read -p "Ответ: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Укажите правильный путь к директории с docker-compose.yml:${NC}"
        read -p "Путь к директории: " WORK_DIR
    fi
fi

# Проверка существования директории
if [ ! -d "$WORK_DIR" ]; then
    echo -e "${YELLOW}Директория $WORK_DIR не существует. Создать? (y/n)${NC}"
    read -p "Ответ: " create_dir
    if [[ "$create_dir" =~ ^[Yy]$ ]]; then
        mkdir -p "$WORK_DIR"
    else
        echo -e "${RED}Установка отменена${NC}"
        exit 1
    fi
fi

# === НАСТРОЙКИ ===
DOWNLOAD_URL="https://github.com/hydraponique/roscomvpn-geosite/releases/latest/download/geosite.dat"
ROSCOM_FILE="$WORK_DIR/roscom.dat"
COMPOSE_FILE="$WORK_DIR/docker-compose.yml"
UPDATE_SCRIPT="$WORK_DIR/update_roscom.sh"
LOG_FILE="/var/log/roscom_update.log"
CONTAINER_NAME="remnanode"

echo ""
echo -e "${GREEN}Рабочая директория: $WORK_DIR${NC}"
echo ""

# === ШАГ 1: СКАЧИВАНИЕ ФАЙЛА ===
echo -e "${GREEN}[1/4] Скачивание roscom.dat...${NC}"
if [ -f "$ROSCOM_FILE" ]; then
    echo -e "${YELLOW}Файл roscom.dat уже существует. Обновляю...${NC}"
fi

wget -q --show-progress -O "$ROSCOM_FILE" "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка: Не удалось скачать файл${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Файл скачан: $ROSCOM_FILE${NC}"
echo ""

# === ШАГ 2: ПРОВЕРКА DOCKER-COMPOSE ===
echo -e "${GREEN}[2/4] Настройка docker-compose.yml...${NC}"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${YELLOW}docker-compose.yml не найден в $WORK_DIR${NC}"
    echo -e "${YELLOW}Проверьте правильность указанного пути или создайте файл вручную${NC}"
    echo -e "${RED}Установка прервана${NC}"
    exit 1
fi

# Проверяем, есть ли уже монтирование roscom.dat
if grep -q "roscom.dat" "$COMPOSE_FILE"; then
    echo -e "${YELLOW}Монтирование roscom.dat уже настроено${NC}"
else
    echo -e "${YELLOW}Добавляю монтирование roscom.dat в docker-compose.yml...${NC}"
    
    # Создаем резервную копию
    BACKUP_FILE="$COMPOSE_FILE.backup.$(date +%s)"
    cp "$COMPOSE_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓ Создана резервная копия: $BACKUP_FILE${NC}"
    
    # Используем Python для безопасной модификации YAML
    python3 << PYEOF
import yaml
import sys

compose_file = "$COMPOSE_FILE"

try:
    with open(compose_file, 'r') as f:
        compose_data = yaml.safe_load(f)
    
    if 'services' not in compose_data:
        print("ОШИБКА: Секция 'services' не найдена в docker-compose.yml")
        sys.exit(1)
    
    # Ищем сервис remnanode или remnawave
    service_name = None
    for name in compose_data['services']:
        if 'remnanode' in name or 'remnawave' in name:
            service_name = name
            break
    
    if not service_name:
        print("ОШИБКА: Сервис remnanode/remnawave не найден в docker-compose.yml")
        sys.exit(1)
    
    service = compose_data['services'][service_name]
    
    if 'volumes' not in service:
        service['volumes'] = []
    
    # Проверяем, есть ли уже roscom.dat
    roscom_mount = './roscom.dat:/usr/local/share/xray/roscom.dat'
    if not any('roscom.dat' in str(vol) for vol in service['volumes']):
        service['volumes'].append(roscom_mount)
        print("Монтирование добавлено")
        
        # Сохраняем изменения
        with open(compose_file, 'w') as f:
            yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
        print("Файл сохранен")
    else:
        print("Уже есть")
        
except Exception as e:
    print(f"ОШИБКА: {e}")
    sys.exit(1)
PYEOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Монтирование добавлено в docker-compose.yml${NC}"
    else
        echo -e "${RED}Ошибка при модификации docker-compose.yml${NC}"
        echo -e "${YELLOW}Восстановлена резервная копия${NC}"
        mv "$BACKUP_FILE" "$COMPOSE_FILE"
        echo -e "${YELLOW}Добавьте вручную в секцию volumes сервиса remnanode:${NC}"
        echo "      - './roscom.dat:/usr/local/share/xray/roscom.dat'"
    fi
fi
echo ""

# === ШАГ 3: СОЗДАНИЕ СКРИПТА АВТООБНОВЛЕНИЯ ===
echo -e "${GREEN}[3/4] Создание скрипта автообновления...${NC}"

cat > "$UPDATE_SCRIPT" << EOF
#!/bin/bash

# === НАСТРОЙКИ ===
DOWNLOAD_URL="https://github.com/hydraponique/roscomvpn-geosite/releases/latest/download/geosite.dat"
TARGET_FILE="$WORK_DIR/roscom.dat"
COMPOSE_DIR="$WORK_DIR"
CONTAINER_NAME="$CONTAINER_NAME"
LOG_FILE="/var/log/roscom_update.log"

exec >> "\$LOG_FILE" 2>&1

echo "--- \$(date '+%Y-%m-%d %H:%M:%S') ---"
echo "Начало проверки обновлений roscom.dat..."

TEMP_FILE="/tmp/roscom_temp_\$(date +%s).dat"

wget -q -O "\$TEMP_FILE" "\$DOWNLOAD_URL"
if [ \$? -ne 0 ]; then
    echo "ОШИБКА: Не удалось скачать файл с GitHub."
    rm -f "\$TEMP_FILE"
    exit 1
fi

if [ -f "\$TARGET_FILE" ]; then
    OLD_HASH=\$(md5sum "\$TARGET_FILE" | awk '{print \$1}')
    NEW_HASH=\$(md5sum "\$TEMP_FILE" | awk '{print \$1}')

    if [ "\$OLD_HASH" == "\$NEW_HASH" ]; then
        echo "Файл не изменился. Обновление не требуется."
        rm -f "\$TEMP_FILE"
        exit 0
    fi
    echo "Обнаружена новая версия файла."
else
    echo "Файл roscom.dat не найден, будет скачан впервые."
fi

mv -f "\$TEMP_FILE" "\$TARGET_FILE"
echo "Файл успешно обновлен. Перезапуск контейнера Xray..."

cd "\$COMPOSE_DIR" || exit

docker compose restart "\$CONTAINER_NAME"

if [ \$? -eq 0 ]; then
    echo "Контейнер '\$CONTAINER_NAME' успешно перезапущен."
else
    echo "ОШИБКА: Не удалось перезапустить контейнер."
fi
EOF

chmod +x "$UPDATE_SCRIPT"
echo -e "${GREEN}✓ Скрипт автообновления создан: $UPDATE_SCRIPT${NC}"
echo ""

# === ШАГ 4: ДОБАВЛЕНИЕ В CRON ===
echo -e "${GREEN}[4/4] Настройка автозапуска через cron...${NC}"

# Проверяем, есть ли уже задача в cron
if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
    echo -e "${YELLOW}Задача уже есть в cron${NC}"
else
    # Добавляем задачу (каждый день в 03:00)
    (crontab -l 2>/dev/null; echo "0 3 * * * $UPDATE_SCRIPT") | crontab -
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Задача добавлена в cron (запуск каждый день в 03:00)${NC}"
    else
        echo -e "${RED}Ошибка при добавлении в cron${NC}"
        echo -e "${YELLOW}Добавьте вручную: crontab -e${NC}"
        echo "0 3 * * * $UPDATE_SCRIPT"
    fi
fi
echo ""

# === ПЕРЕЗАПУСК КОНТЕЙНЕРОВ ===
echo -e "${GREEN}Перезапуск контейнеров...${NC}"
cd "$WORK_DIR" || exit

if command -v docker &> /dev/null; then
    docker compose down
    docker compose up -d
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Контейнеры перезапущены${NC}"
    else
        echo -e "${RED}Ошибка при перезапуске контейнеров${NC}"
    fi
else
    echo -e "${YELLOW}Docker не найден. Перезапустите контейнеры вручную:${NC}"
    echo "cd $WORK_DIR && docker compose down && docker compose up -d"
fi

echo ""
echo -e "${GREEN}=== Установка завершена ===${NC}"
echo ""
echo -e "${YELLOW}Важная информация:${NC}"
echo "1. Рабочая директория: $WORK_DIR"
echo "2. Файл roscom.dat: $ROSCOM_FILE"
echo "3. Скрипт автообновления: $UPDATE_SCRIPT"
echo "4. Лог обновлений: $LOG_FILE"
echo "5. Автообновление: каждый день в 03:00"
echo ""
echo -e "${YELLOW}Для использования в правилах маршрутизации:${NC}"
echo '  "ext:roscom.dat:category-ru"'
echo '  "ext:roscom.dat:youtube"'
echo '  "ext:roscom.dat:telegram"'
echo ""
echo -e "${YELLOW}Проверить работу скрипта вручную:${NC}"
echo "$UPDATE_SCRIPT"
echo ""
echo -e "${YELLOW}Посмотреть лог:${NC}"
echo "cat $LOG_FILE"
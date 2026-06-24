#!/bin/bash

# Установка и настройка fail2ban
# Запуск: chmod +x install_fail2ban.sh && sudo ./install_fail2ban.sh

set -e  # Остановка скрипта при ошибке

echo "=== Установка fail2ban ==="
sudo apt update
sudo apt install fail2ban -y

echo "=== Включение автозапуска ==="
sudo systemctl enable fail2ban

echo "=== Запуск fail2ban ==="
sudo systemctl start fail2ban

# Небольшая пауза для запуска сервиса
sleep 2

echo "=== Создание конфигурации jail.local ==="
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
# Белый список (свои IP добавьте обязательно!)
ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24 95.25.145.250

# Время блокировки (3 часа)
bantime = 3h

# Интервал подсчёта ошибок (10 минут)
findtime = 10m

# Максимум ошибок до блокировки
maxretry = 5

# Действие при блокировке (с отправкой email)
#action = %(action_mwl)s

# Кому отправлять уведомления
#destemail = juhnsooqa@gmail.com
#sender = fail2ban@noclip.network

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 2h
EOF

echo "=== Проверка синтаксиса конфигурации ==="
sudo fail2ban-client -d

echo "=== Перезапуск fail2ban для применения настроек ==="
sudo systemctl restart fail2ban

# Ждём запуска сервиса
sleep 3

echo "=== Проверка статуса сервиса ==="
if sudo systemctl is-active --quiet fail2ban; then
    echo "✓ fail2ban успешно запущен"
else
    echo "✗ Ошибка: fail2ban не запущен"
    sudo systemctl status fail2ban --no-pager
    exit 1
fi

echo "=== Статус SSH защиты ==="
sudo fail2ban-client status sshd 2>/dev/null || echo "Ожидание активации jail sshd..."

echo ""
echo "=== Дополнительные команды ==="
echo "Проверить статус сервиса: sudo systemctl status fail2ban"
echo "Просмотр статуса всех jail: sudo fail2ban-client status"
echo "Просмотр заблокированных IP: sudo fail2ban-client banned"
echo "Разблокировать IP: sudo fail2ban-client unban <IP>"
echo "Логи: sudo tail -f /var/log/fail2ban.log"
echo "Проверить логи ошибок: sudo journalctl -u fail2ban -n 50"

# Если ошибка с сокетом всё ещё есть, показываем решение
if [ ! -S /var/run/fail2ban/fail2ban.sock ]; then
    echo ""
    echo "=== ВНИМАНИЕ: Сокет-файл не найден ==="
    echo "Возможные решения:"
    echo "1. Проверьте статус: sudo systemctl status fail2ban"
    echo "2. Посмотрите ошибки: sudo journalctl -u fail2ban -n 50"
    echo "3. Переустановите: sudo apt install --reinstall fail2ban"
    echo "4. Ручной запуск: sudo fail2ban-client start"
fi
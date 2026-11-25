# ЛР6. Continuous Delivery

После `Publish scanned image` на ветках `л6` и `л7` задача `Exercise deployment and rollback in disposable staging` поднимает независимое окружение, скачивает образ по SHA из GHCR и проверяет его. Для демонстрации отказа тестовый registry отдаёт последний рабочий образ под чужим тегом. Проверка метки версии отклоняет выпуск, возвращает ранее принятый образ и сверяет `/version`.

Постоянный staging подключается отдельной задачей `Deploy verified release to staging`. Эта задача работает по SSH с выделенной учётной записью. Выпуск считается принятым после проверки контейнеров, миграции, `/health/ready`, версии обоих экземпляров и сквозного сценария «вход → чтение каталога → выход». Контрольная учётная запись удаляется после проверки. На сервере используются только образы из registry. База данных хранится в отдельном volume.

## Настройка постоянного staging

1. Подготовьте отдельный Ubuntu 24.04 с Docker Engine, Compose v2.24.4+, Python 3, SSH и `sudo`. Воспроизводимая настройка сервера реализована в ЛР7.
2. Под root создайте `/opt/music-store/infra/nginx`. Поместите `docker-compose.yml` в `/opt/music-store`, `infra/nginx/default.conf` в его подкаталог `infra/nginx`, а `compose.release.yml` и `smoke.py` из `infra/release` в корень каталога. Создайте там `release.env` по примеру с собственным паролем БД. Владелец файлов root, каталог и конфигурация среды закрыты от пользователя деплоя. Оставьте HTTP на loopback.
3. Установите `infra/release/release.sh` как `/usr/local/sbin/music-store-release`, `ssh-command` как `/usr/local/sbin/music-store-ssh` с правами 0755 и `music-store.sudoers` в `/etc/sudoers.d/music-store` с правами 0440. Проверьте через `visudo -cf /etc/sudoers.d/music-store`.
4. Добавьте отдельного пользователя `music-deploy` с домашним каталогом и shell Bash. Запишите его публичный ключ в `authorized_keys` с префиксом `restrict,command="/usr/local/sbin/music-store-ssh"`. Права каталога `.ssh` 0700, файла 0600. Доступ к Docker-группе пользователю не нужен.
5. Для приватного пакета выполните под root `docker login ghcr.io` с токеном только на чтение пакета. В GitHub настройте repository variable `STAGING_SSH_ENABLED=true`, в environment `staging` настройте `STAGING_HOST` и при необходимости `STAGING_PORT`, а также секреты `STAGING_SSH_KEY` и `STAGING_KNOWN_HOSTS`. Запись known_hosts берите из доверенного источника. Сетевой доступ к SSH нужен с адреса runner.

## Ручной выпуск и откат

```sh
ssh music-deploy@HOST "deploy ПОЛНЫЙ_SHA_ОБРАЗА"
ssh music-deploy@HOST rollback
```

На staging GitHub сериализует задачи, а сервер удерживает `flock` на время операций. После двух успешных выпусков `rollback` восстанавливает предыдущую принятую версию. При ошибке скачивания работающие контейнеры продолжают обслуживать запросы. Если проверка после старта упала, скрипт возвращает последнюю принятую версию и завершает выпуск ошибкой. Для защиты используйте отсутствующий тег, отсутствие обязательной переменной, неисправный healthcheck и демонстрационный образ со сломанным сценарием каталога. Откат образа рассчитан на обратно совместимые миграции, восстановление данных выполняется отдельно из бэкапа.

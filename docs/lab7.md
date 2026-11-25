# ЛР7. Воспроизводимая инфраструктура

Ansible настраивает чистый Ubuntu 24.04. Отдельные inventory задают staging (порт 8080) и QA (порт 18080). Общие настройки лежат в `infra/ansible/group_vars`, параметры окружений в `inventories/<окружение>/group_vars`, адреса и SSH-параметры узлов в `host_vars`. Пароль БД и токен registry передаются из защищённого окружения, шаблон с паролем на сервере доступен только root.

Роль `host` управляет подписанным APT-репозиторием Docker, пакетами, сервисом Docker, отдельным SSH-пользователем выпуска и UFW. SSH разрешён с управляющей сети. База и приложение находятся во внутренней сети Docker. Nginx публикуется только на loopback, чтобы открытый Docker-порт не обходил политику UFW. Роль `music_store` раскладывает конфигурацию, выставляет права, устанавливает systemd unit и проверяет готовность и SHA через HTTP.

## Локальное применение

На управляющей машине с Python 3.12 создайте виртуальное окружение, активируйте его и выполните:

```sh
make infra-check
cd infra/ansible
ansible-playbook -i inventories/staging/hosts.yml --private-key PATH_TO_ADMIN_KEY site.yml
```

Передайте в окружение команды `MUSIC_ANSIBLE_HOST`, `MUSIC_ANSIBLE_USER` (администратор с sudo), `MUSIC_MANAGEMENT_CIDR` (сеть, из которой приходит это SSH-соединение), `MUSIC_DEPLOY_PUBLIC_KEY`, `MUSIC_DB_PASSWORD` (например, результат `openssl rand -hex 32`) и `MUSIC_RELEASE_SHA` (опубликованный SHA из ЛР6 или ЛР7). Для частного пакета нужны `MUSIC_REGISTRY_USER` и `MUSIC_REGISTRY_TOKEN`. Проверьте ключ хоста и добавьте его в known_hosts. Для QA используйте `inventories/qa/hosts.yml` и данные отдельной машины. Существующую БД используйте с тем же паролем, пока не проведена отдельная ротация её учётных данных.

Для удалённого сервера GitHub задайте repository variable `INFRA_ENABLED=true` и параметры окружения `staging`. Нужны переменные `STAGING_HOST`, `INFRA_USER`, `INFRA_MANAGEMENT_CIDR`, `STAGING_DEPLOY_PUBLIC_KEY`, при необходимости `STAGING_PORT` и `INFRA_REGISTRY_USER`. Секреты `INFRA_SSH_KEY`, `INFRA_DB_PASSWORD`, `STAGING_KNOWN_HOSTS` и для частного GHCR `INFRA_REGISTRY_TOKEN`. У runner должен быть доступ в управляющую сеть. Процесс CD передаёт Ansible SHA проверенного и опубликованного образа.

На `л7` задача `Exercise Ansible convergence on disposable Ubuntu` применяет QA-конфигурацию в отдельной Ubuntu VM GitHub Actions. Она повторяет запуск, требует `changed=0`, исправляет временно ослабленные права управляемого файла и проверяет, что SSH-аккаунт выпуска отклоняет постороннюю команду.

## Демонстрация на защите

1. Выполните playbook на чистой машине и покажите `PLAY RECAP`, Docker, статус UFW, `/health/ready` и `/version`. По SSH на staging доступ к HTTP можно перенаправить через административную учётную запись.
2. Повторите запуск с теми же параметрами и проверьте `changed=0`. Штатное обновление кэша пакетов выполняется по интервалу. Для отдельного выпуска передайте `MUSIC_RELEASE_SHA` и добавьте `-e '{"music_store_update_release":true}'`.
3. На учебном сервере измените права `sudo chmod 0644 /opt/music-store/release.env` и повторите playbook. Проверьте, что права вернулись к 0600. Отдельно измените `server_tokens off;` на `server_tokens on;` в управляемом файле Nginx, повторите запуск и покажите восстановленное значение. При смене конфигурации её хеш заставляет Compose обновить контейнер Nginx.
4. В PR с изменением роли или шаблона проверьте согласование Code Owner по правилу из ЛР5. Секреты не вводите в аргументы Git. Проверки синтаксиса обоих inventory и сканирование секретов выполняются в CI.

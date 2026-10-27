# Как выпустить версию

```bash
git tag v1.2.3
git push origin v1.2.3
```

Workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) сам:

1. скачивает Godot 4.7.2 и шаблоны экспорта (они кэшируются между запусками);
2. собирает Windows, Linux и Web; версия из тега попадает в свойства `Ylem.exe`;
3. выкладывает сборки на [itch.io](https://vinteam.itch.io/ylem) через [butler](https://itch.io/docs/butler/) в каналы `windows`, `linux` и `html5`;
4. выкладывает веб-версию на https://ylem.live: на Mac Mini self-hosted runner собирает Docker-образ ([`Dockerfile`](Dockerfile), [`docker-compose.yml`](docker-compose.yml)) и запускает его за Traefik, так же как battle_city;
5. создаёт GitHub Release с архивами `Ylem-<версия>-windows.zip`, `-linux.tar.gz` и `-web.zip`.

Во вкладке Actions можно запустить workflow вручную (Run workflow). Тогда он только соберёт игру и сохранит архивы как артефакт, ничего не публикуя.

## Секрет (Settings → Secrets and variables → Actions → Repository secrets)

`BUTLER_API_KEY`: ключ с https://itch.io/user/settings/api-keys. Без него шаг itch пропускается.

## Раннер на Mac Mini (один раз)

1. Settings → Actions → Runners → New self-hosted runner → macOS. Выполнить на Mac Mini показанные команды; при `./config.sh` добавить метку: `--labels mac-mini`.
2. Запустить как службу: `./svc.sh install && ./svc.sh start`. Пользователю раннера нужен доступ к `docker`.
3. **Репозиторий публичный**, поэтому: Settings → Actions → General → «Fork pull request workflows from outside collaborators» → **Require approval for all outside collaborators**. Иначе чужой pull request мог бы запустить свой код на Mac Mini.
4. DNS: A-записи `ylem.live` и `www.ylem.live` на Mac Mini. Сертификат выпустит Traefik.

## Один раз на itch.io

- После первого push от butler загрузку `html5` нужно отметить на странице игры как «This file will be played in the browser».
- Файлы, загруженные раньше вручную, butler не трогает. Их нужно удалить на странице игры самому.
- В Embed options **включить SharedArrayBuffer support**: веб-сборка с потоками (звук смешивается в отдельном потоке и не рвётся, когда кадр тормозит), без этой галочки она не запустится.

## Веб-сервер

nginx в контейнере ([`docker/nginx.conf`](docker/nginx.conf)) сжимает `.wasm`/`.pck` и ставит `Cache-Control: no-cache`, чтобы после релиза браузер сразу брал новую версию. Ещё он отдаёт заголовки COOP/COEP: без них браузер не даст сборке с потоками SharedArrayBuffer.

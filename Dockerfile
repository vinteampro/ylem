# Веб-версия Ylem для ylem.live: Godot экспортирует пресет "Web", nginx его отдаёт.
# Собирается на раннере mac-mini (docker compose build), см. .github/workflows/release.yml.
# Контекст — корень репозитория (рядом с project.godot).

FROM debian:bookworm-slim AS export

ARG GODOT_VER=4.7.2-stable

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
      libfontconfig1 libx11-6 libxcursor1 libxinerama1 libxext6 libxrandr2 libxi6 libgl1 \
 && case "$(uname -m)" in \
      x86_64) B=linux.x86_64 ;; \
      aarch64) B=linux.arm64 ;; \
      *) echo "unsupported arch $(uname -m)"; exit 1 ;; \
    esac \
 && curl -fL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_${B}.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv "/tmp/godot/Godot_v${GODOT_VER}_${B}" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && TEMPLATES_VER="$(echo "$GODOT_VER" | sed 's/-stable/.stable/')" \
 && mkdir -p "/root/.local/share/godot/export_templates/${TEMPLATES_VER}" \
 && curl -fL -o /tmp/templates.tpz "https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_export_templates.tpz" \
 && unzip -q /tmp/templates.tpz -d /tmp/templates \
 && mv /tmp/templates/templates/* "/root/.local/share/godot/export_templates/${TEMPLATES_VER}/" \
 && rm -rf /tmp/godot /tmp/godot.zip /tmp/templates /tmp/templates.tpz \
 && apt-get purge -y curl unzip && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src
RUN mkdir -p /out/web \
 && godot --headless --path /src --import \
 && godot --headless --path /src --export-release "Web" /out/web/index.html \
 && test -s /out/web/index.html \
 && test -s /out/web/index.wasm

FROM nginx:1.27-alpine AS web

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=export /out/web/ /usr/share/nginx/html/
HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1

#!/usr/bin/env bash
#
# listrr-dots — установщик конфигов Hyprland + Waybar
# https://github.com/listrrise/listrr-dots
#
# Использование:
#   ./install.sh              скопировать конфиги в ~/.config (с бэкапом)
#   ./install.sh --link       сделать симлинки на репозиторий
#   ./install.sh --no-backup  не бэкапить существующие конфиги
#   ./install.sh --uninstall  удалить конфиги и вернуть последний бэкап
#

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGETS=(hypr waybar)

# Путь автора конфигов: подставляется $HOME при установке.
SOURCE_HOME="/home/listrise"

MODE="copy"          # copy | link
DO_BACKUP=1
ACTION="install"
BACKUP_DIR=""

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi

info() { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
err()  { printf '%s✘%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }

usage() {
  cat <<'EOF'
listrr-dots — установщик конфигов Hyprland + Waybar

Использование:
  ./install.sh              скопировать конфиги в ~/.config (с бэкапом)
  ./install.sh --link       сделать симлинки на репозиторий
  ./install.sh --no-backup  не бэкапить существующие конфиги
  ./install.sh --uninstall  удалить конфиги и вернуть последний бэкап
  ./install.sh --help       эта справка
EOF
  exit 0
}

# ---------------------------------------------------------------- аргументы
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--link)      MODE="link" ;;
    -c|--copy)      MODE="copy" ;;
    -n|--no-backup) DO_BACKUP=0 ;;
    -u|--uninstall) ACTION="uninstall" ;;
    -h|--help)      usage ;;
    *) err "Неизвестный аргумент: $1"; usage ;;
  esac
  shift
done

# ------------------------------------------------------------ зависимости
REQUIRED_CMDS=(hyprland waybar)
OPTIONAL_CMDS=(
  kitty firefox nautilus fuzzel mako hyprlock hyprshot swaybg
  swayosd-server wl-clip-persist fcitx5 playerctl jq python3
  btop nvim yazi lazygit lazydocker alacritty
)

check_dependencies() {
  local missing_req=() missing_opt=()

  for c in "${REQUIRED_CMDS[@]}"; do
    command -v "$c" >/dev/null 2>&1 || missing_req+=("$c")
  done
  for c in "${OPTIONAL_CMDS[@]}"; do
    command -v "$c" >/dev/null 2>&1 || missing_opt+=("$c")
  done

  if [ ${#missing_req[@]} -gt 0 ]; then
    warn "Не найдено обязательное: ${missing_req[*]}"
    warn "Без этого конфиг работать не будет — установи, потом запусти скрипт снова."
  else
    ok "Hyprland и Waybar на месте"
  fi

  if [ ${#missing_opt[@]} -gt 0 ]; then
    info  "${C_DIM}Нет в PATH (не критично, просто часть фич не будет работать):${C_OFF}"
    info  "  ${missing_opt[*]}"
  fi

  if command -v fc-list >/dev/null 2>&1; then
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
      ok "Шрифт JetBrainsMono Nerd Font найден"
    else
      warn "Шрифт JetBrainsMono Nerd Font не найден — иконки Waybar будут «квадратиками»"
    fi
  fi
}

# ------------------------------------------------------------------- бэкап
make_backup() {
  local items=()
  for t in "${TARGETS[@]}"; do
    if [ -e "$CONFIG_DIR/$t" ] || [ -L "$CONFIG_DIR/$t" ]; then
      items+=("$t")
    fi
  done
  if [ ${#items[@]} -eq 0 ]; then
    return 0
  fi

  BACKUP_DIR="$CONFIG_DIR/dots-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  for t in "${items[@]}"; do
    # cp -a для симлинка скопирует сам симлинк, для папки — папку
    cp -a "$CONFIG_DIR/$t" "$BACKUP_DIR/" 2>/dev/null || true
  done
  ok "Бэкап: $BACKUP_DIR"
}

# ------------------------------------------------- переписать пути автора
rewrite_paths() {
  local root="$1" files=()
  while IFS= read -r -d '' f; do
    if grep -Iq . "$f" 2>/dev/null && grep -q "$SOURCE_HOME" "$f" 2>/dev/null; then
      files+=("$f")
    fi
  done < <(find "$root" -type f -print0 2>/dev/null)

  if [ ${#files[@]} -eq 0 ]; then
    return 0
  fi

  for f in "${files[@]}"; do
    sed -i "s|${SOURCE_HOME}|${HOME}|g" "$f"
  done
  info "${C_DIM}Пути ${SOURCE_HOME} → ${HOME} поправлены в ${#files[@]} файл(ах)${C_OFF}"
}

# ------------------------------------------------------------ omarchy-заглушка
setup_omarchy() {
  local omarchy="$CONFIG_DIR/omarchy"
  local theme_conf="$omarchy/current/theme/hyprland.conf"

  if [ ! -e "$omarchy" ]; then
    mkdir -p "$omarchy/current/theme"
    : > "$theme_conf"
    ok "Создана заглушка $theme_conf (hyprland.conf подключает тему omarchy)"
  elif [ ! -e "$theme_conf" ]; then
    warn "omarchy установлен, но $theme_conf отсутствует —"
    warn "Hyprland напишет ошибку на строку source. Убери её из hypr/hyprland.conf или создай файл."
  fi

  if [ ! -e "$omarchy/current/background" ]; then
    warn "Нет обоев omarchy ($omarchy/current/background) — swaybg не запустится."
    warn "Поставь свой фон и поправь путь в hypr/autostart.conf."
  fi
}

# -------------------------------------------------------------- установка
do_install() {
  info ""
  info "Конфиги из: $REPO_DIR"
  info "Устанавливаю в: $CONFIG_DIR  (режим: $MODE)"
  info ""

  mkdir -p "$CONFIG_DIR"

  if [ "$DO_BACKUP" -eq 1 ]; then
    make_backup
  else
    warn "Бэкап отключён (--no-backup)"
  fi

  for t in "${TARGETS[@]}"; do
    if [ ! -e "$REPO_DIR/$t" ]; then
      warn "В репозитории нет папки $t — пропускаю"
      continue
    fi

    rm -rf "$CONFIG_DIR/$t"

    if [ "$MODE" = "link" ]; then
      rewrite_paths "$REPO_DIR/$t"
      ln -sfn "$REPO_DIR/$t" "$CONFIG_DIR/$t"
      ok "$t → $CONFIG_DIR/$t (симлинк)"
    else
      cp -a "$REPO_DIR/$t" "$CONFIG_DIR/$t"
      rewrite_paths "$CONFIG_DIR/$t"
      ok "$t → $CONFIG_DIR/$t"
    fi
  done

  setup_omarchy

  info ""
  ok "Готово. Перезапусти Hyprland: Super+Esc → Reload (или перелогинься)."
  info "${C_DIM}Панель без перелогина можно перезапустить так: pkill waybar && waybar &${C_OFF}"
}

# ---------------------------------------------------------------- удаление
do_uninstall() {
  local latest=""
  latest="$(find "$CONFIG_DIR" -maxdepth 1 -type d -name 'dots-backup-*' 2>/dev/null | sort | tail -n1)"

  for t in "${TARGETS[@]}"; do
    if [ -e "$CONFIG_DIR/$t" ] || [ -L "$CONFIG_DIR/$t" ]; then
      rm -rf "$CONFIG_DIR/$t"
      ok "Удалено: $CONFIG_DIR/$t"
    fi
  done

  if [ -n "$latest" ]; then
    for t in "${TARGETS[@]}"; do
      if [ -e "$latest/$t" ] || [ -L "$latest/$t" ]; then
        cp -a "$latest/$t" "$CONFIG_DIR/$t"
        ok "Возвращено из бэкапа: $t"
      fi
    done
    info ""
    info "Использован бэкап: $latest"
  else
    warn "Бэкапов в $CONFIG_DIR не найдено — конфиги просто удалены."
  fi
}

# ------------------------------------------------------------------- main
case "$ACTION" in
  install)
    check_dependencies
    do_install
    ;;
  uninstall)
    do_uninstall
    ;;
esac

#!/usr/bin/env bash
#
# install.sh — instalador do ambiente Victorias-Mangowm
# Repo: https://github.com/kohagizpk/Victorias-Mangowm
#
# Instala o compositor MangoWM + todo o ambiente (waybar, kitty, fish,
# rofi, fuzzel, wlogout, swayosd, dunst, portais, etc.) e aplica as
# dotfiles deste repo, corrigindo pontos que não funcionavam como estavam.
# Lista completa de correções no resumo final do script.
#
# Uso: rode de dentro do repo clonado (./install.sh) ou solto (baixa sozinho).

set -euo pipefail

REPO_URL="https://github.com/kohagizpk/Victorias-Mangowm.git"
CONFIG_DIR="$HOME/.config/mango"

# ---------- helpers ----------
c_reset='\033[0m'; c_bold='\033[1m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_blue='\033[1;34m'

step()  { printf "\n${c_blue}==>${c_reset} ${c_bold}%s${c_reset}\n" "$1"; }
info()  { printf "    %s\n" "$1"; }
ok()    { printf "${c_green}[ok]${c_reset} %s\n" "$1"; }
warn()  { printf "${c_yellow}[aviso]${c_reset} %s\n" "$1"; }
err()   { printf "${c_red}[erro]${c_reset} %s\n" "$1"; }

confirm() {
    local reply
    read -rp "$1 [s/N] " reply
    [[ "$reply" =~ ^[sSyY]$ ]]
}

ADAPTACOES=()
log_adapt() { ADAPTACOES+=("$1"); }

# ---------- checagens iniciais ----------
if [[ "${EUID}" -eq 0 ]]; then
    err "Não rode como root. Rode como seu usuário normal (pede sudo quando precisar)."
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    err "pacman não encontrado. Este script é para Arch/Artix/CachyOS."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/config.conf" && -f "$SCRIPT_DIR/autostart.sh" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
else
    step "Clonando o repositório"
    TMP_CLONE="$(mktemp -d)"
    git clone --depth 1 "$REPO_URL" "$TMP_CLONE/repo"
    SOURCE_DIR="$TMP_CLONE/repo"
fi

echo -e "${c_bold}Instalador Victorias-Mangowm${c_reset}"
info "Fonte: $SOURCE_DIR"
info "Destino: $CONFIG_DIR"
if ! confirm "Começar?"; then
    exit 0
fi

# ---------- AUR helper ----------
if command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
else
    step "AUR helper não encontrado"
    if confirm "Instalar o yay agora? (necessário para o mango e outros pacotes do AUR)"; then
        sudo pacman -S --needed --noconfirm base-devel git
        TMP_YAY="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay.git "$TMP_YAY/yay"
        (cd "$TMP_YAY/yay" && makepkg -si --noconfirm)
        rm -rf "$TMP_YAY"
        AUR_HELPER="yay"
    else
        err "Sem AUR helper não dá pra continuar. Abortando."
        exit 1
    fi
fi
ok "Usando $AUR_HELPER"

# ---------- pacotes ----------
# mangowc-git saiu do AUR (renomeado pelo autor) -> pacote certo hoje é mangowm-git
PACKAGES=(
    mangowm-git

    waybar rofi fuzzel wmenu

    kitty fish fastfetch

    nemo pavucontrol

    swaybg kanshi wlr-randr

    wl-clipboard cliphist wl-clip-persist

    grim slurp

    dunst

    swayosd brightnessctl

    swaylock wlogout

    xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk

    xorg-xwayland

    ttf-jetbrains-mono-nerd

    pipewire pipewire-pulse pipewire-alsa wireplumber

    discord spotify-launcher helium-browser-bin

    # tema do GRUB (ultragrub)
    wget
)

step "Pacotes (${#PACKAGES[@]})"
info "${PACKAGES[*]}"
if confirm "Instalar tudo agora? (compila pacotes -git do AUR, pode demorar)"; then
    "$AUR_HELPER" -S --needed "${PACKAGES[@]}"
    ok "Pacotes instalados"
else
    warn "Pulado. O resto do script continua, mas o ambiente só funciona depois de instalar isso manualmente."
fi

# ---------- backup + copia das dotfiles ----------
step "Copiando dotfiles para $CONFIG_DIR"
if [[ -d "$CONFIG_DIR" ]]; then
    if confirm "Já existe $CONFIG_DIR. Fazer backup e sobrescrever?"; then
        backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        mv "$CONFIG_DIR" "$backup"
        ok "Backup em $backup"
    else
        err "Preciso sobrescrever $CONFIG_DIR pra continuar. Abortando."
        exit 1
    fi
fi
mkdir -p "$CONFIG_DIR"
cp -a "$SOURCE_DIR/." "$CONFIG_DIR/"
rm -rf "$CONFIG_DIR/.git" "$CONFIG_DIR/install.sh"
ok "Copiado"

# ---------- correções ----------
step "Aplicando correções"

# 1) waybar: systemctl -> loginctl (sistema sem systemd, roda elogind)
if [[ -f "$CONFIG_DIR/config.jsonc" ]]; then
    sed -i \
        -e 's/systemctl poweroff/loginctl poweroff/' \
        -e 's/systemctl reboot/loginctl reboot/' \
        "$CONFIG_DIR/config.jsonc"
    log_adapt "waybar (config.jsonc): systemctl poweroff/reboot -> loginctl (não tem systemd)"
fi

# 2) wlogout: hyprlock/hyprctl (Hyprland) nao existem aqui -> swaylock/mmsg (mango)
if [[ -f "$CONFIG_DIR/wlogout/layout" ]]; then
    sed -i \
        -e 's/"action" : "hyprlock"/"action" : "swaylock -f"/' \
        -e 's/"action" : "hyprctl dispatch exit"/"action" : "mmsg -d quit"/' \
        "$CONFIG_DIR/wlogout/layout"
    log_adapt "wlogout/layout: hyprlock -> swaylock -f, hyprctl dispatch exit -> mmsg -d quit (comandos do Hyprland, não do mango)"
fi

# 3) keybind do spotify: o pacote spotify-launcher instala o binário "spotify-launcher", não "spotify"
if [[ -f "$CONFIG_DIR/config.conf" ]]; then
    sed -i 's/bind=SUPER,s,spawn,spotify$/bind=SUPER,s,spawn,spotify-launcher/' "$CONFIG_DIR/config.conf"
    log_adapt "config.conf: bind SUPER+s agora chama spotify-launcher (binário real do pacote)"
fi

# 4) autostart.sh: caminho do wallpaper apontava pra fora do repo (/home/julia/wallpaper/...)
#    + dunst e swayosd-server não sobem sozinhos sem systemd --user, precisam de start manual
if [[ -f "$CONFIG_DIR/autostart.sh" ]]; then
    sed -i \
        -e "s#/home/julia/wallpaper/wallpaper\\.png#${CONFIG_DIR}/kohagi_personal_configs/wallpaper/wallpaper.png#" \
        -e "s#/home/julia/wallpaper/wallpaper2\\.png#${CONFIG_DIR}/kohagi_personal_configs/wallpaper/wallpaper2.png#" \
        "$CONFIG_DIR/autostart.sh"
    log_adapt "autostart.sh: caminho do wallpaper corrigido pra dentro de ~/.config/mango"

    if ! grep -q "swayosd-server" "$CONFIG_DIR/autostart.sh"; then
        sed -i '/pgrep -x pipewire-pulse/a pgrep -x dunst >/dev/null || dunst \&\npgrep -x swayosd-server >/dev/null || swayosd-server \&' "$CONFIG_DIR/autostart.sh"
        log_adapt "autostart.sh: adicionado start de dunst e swayosd-server (usados por volume.sh/brightness.sh mas nunca eram iniciados)"
    fi
fi

# 5) volume.sh: notificação de mute apontava pra um ícone que não existe no repo (rice_assets/Icons/mute.png)
if [[ -f "$CONFIG_DIR/scripts/volume.sh" ]]; then
    sed -i 's#\${HOME}/\.config/rice_assets/Icons/mute\.png#/usr/share/icons/Adwaita/96x96/status/audio-volume-muted-symbolic.symbolic.png#' "$CONFIG_DIR/scripts/volume.sh"
    log_adapt "scripts/volume.sh: ícone de mute corrigido (o antigo caminho não existe em lugar nenhum do repo)"
fi

ok "Correções aplicadas"

# ---------- sensor de temperatura (waybar) ----------
step "Detectando sensor de CPU para a waybar"
hwmon_path=""
for d in /sys/class/hwmon/hwmon*; do
    [ -r "$d/name" ] || continue
    name="$(cat "$d/name" 2>/dev/null || true)"
    case "$name" in
        k10temp|coretemp|zenpower|cpu_thermal|acpitz)
            hwmon_path="$d/temp1_input"
            break
            ;;
    esac
done
if [[ -n "$hwmon_path" && -f "$CONFIG_DIR/config.jsonc" ]]; then
    sed -i "s#/sys/class/hwmon/hwmon[0-9]*/temp1_input#${hwmon_path}#" "$CONFIG_DIR/config.jsonc"
    ok "Sensor: $hwmon_path"
    log_adapt "waybar (config.jsonc): hwmon-path era fixo (hwmon4) e detectado automaticamente como $hwmon_path"
else
    warn "Não detectei o sensor automaticamente. Ajuste 'hwmon-path' em $CONFIG_DIR/config.jsonc à mão (rode 'sensors' ou veja /sys/class/hwmon/*/name)."
fi

# ---------- fastfetch (fora do ~/.config/mango) ----------
step "Configurando fastfetch"
FASTFETCH_SRC="$CONFIG_DIR/kohagi_personal_configs/terminal_configs/fastfetch.jsonc"
if [[ -f "$FASTFETCH_SRC" ]]; then
    mkdir -p "$HOME/.config/fastfetch"
    cp "$FASTFETCH_SRC" "$HOME/.config/fastfetch/config.jsonc"
    # o ascii.txt referenciado não existe no repo; sem isso o fastfetch quebra o logo.
    # removendo a linha, ele cai pro logo automático da distro (funciona sozinho).
    sed -i '\#"source": "~/.config/fastfetch/ascii.txt"#d' "$HOME/.config/fastfetch/config.jsonc"
    ok "~/.config/fastfetch/config.jsonc"
    log_adapt "fastfetch: logo customizado (ascii.txt) não existe no repo -> removido, usa logo automático da distro"
fi

# ---------- kanshi (fora do ~/.config/mango) ----------
step "Configurando kanshi"
KANSHI_SRC="$CONFIG_DIR/kohagi_personal_configs/kanshi (if_u_have_2_monitors)/config"
if [[ -f "$KANSHI_SRC" ]]; then
    mkdir -p "$HOME/.config/kanshi"
    cp "$KANSHI_SRC" "$HOME/.config/kanshi/config"
    ok "~/.config/kanshi/config"
    log_adapt "kanshi: config estava só dentro do repo (~/.config/mango/...), kanshi lê de ~/.config/kanshi/config -> copiado pro lugar certo"
else
    info "Sem config de kanshi (perfil de 2 monitores) no repo, pulando."
fi

# ---------- random_image.sh + fish ----------
step "Configurando terminal (imagem aleatória + fastfetch)"
RANDIMG_SRC="$CONFIG_DIR/kohagi_personal_configs/terminal_configs/random_image.sh"
if [[ -f "$RANDIMG_SRC" ]]; then
    cp "$RANDIMG_SRC" "$HOME/random_image.sh"
    chmod +x "$HOME/random_image.sh"
    mkdir -p "$HOME/img_terminal"
    ok "~/random_image.sh (imagens em ~/img_terminal/)"

    FISH_CONFIG="$HOME/.config/fish/config.fish"
    mkdir -p "$HOME/.config/fish"
    touch "$FISH_CONFIG"
    if ! grep -q "random_image.sh" "$FISH_CONFIG"; then
        cat >> "$FISH_CONFIG" <<'EOF'

# Victorias-Mangowm: imagem aleatoria + fastfetch ao abrir terminal
if status is-interactive
    and test -f "$HOME/random_image.sh"
    bash "$HOME/random_image.sh"
end
EOF
        ok "Chamada adicionada em ~/.config/fish/config.fish"
        log_adapt "fish: random_image.sh nunca era chamado por nada -> chamado automaticamente em shell interativa"
    else
        info "~/.config/fish/config.fish já chama random_image.sh"
    fi
fi

# ---------- permissões ----------
step "Ajustando permissões"
find "$CONFIG_DIR" -name '*.sh' -exec chmod +x {} \;
ok "Scripts marcados como executáveis"

# ---------- cursor ----------
step "Cursor (Animated-Mew-Cursor)"
CURSOR_SRC="$CONFIG_DIR/kohagi_personal_configs/Animated-Mew-Cursor"
CURSOR_DST="$HOME/.local/share/icons/Animated-Mew-Cursor"
if [[ -d "$CURSOR_SRC" ]]; then
    mkdir -p "$HOME/.local/share/icons"
    rm -rf "$CURSOR_DST"
    cp -a "$CURSOR_SRC" "$CURSOR_DST"
    ok "Cursor copiado do repo para $CURSOR_DST"
    log_adapt "cursor: tema Animated-Mew-Cursor agora vem no repo -> copiado pra ~/.local/share/icons/"

    # index.theme deveria ser texto simples ([Icon Theme]...); no repo hoje ele está
    # salvo como OpenDocument Text (.odt), não como o arquivo de tema de verdade.
    if [[ -f "$CURSOR_DST/index.theme" ]] && ! head -c 200 "$CURSOR_DST/index.theme" 2>/dev/null | grep -q '\[Icon Theme\]'; then
        warn "$CURSOR_DST/index.theme não é um arquivo de tema válido (tipo 'OpenDocument Text', não texto simples)."
        info "Os cursores em cursors/ são X11 cursor de verdade e devem funcionar via XCURSOR_THEME mesmo assim,"
        info "mas index.theme/cursor.theme precisam ser corrigidos no repo (parece um .odt commitado no lugar errado)."
    fi
elif [[ -d "$HOME/.local/share/icons/Animated-Mew-Cursor" || -d "$HOME/.icons/Animated-Mew-Cursor" || -d "/usr/share/icons/Animated-Mew-Cursor" ]]; then
    ok "Tema de cursor já presente"
else
    warn "Tema 'Animated-Mew-Cursor' não encontrado no repo nem instalado. Baixe manualmente:"
    info "https://www.gnome-look.org/c/2326996"
    info "Extraia em ~/.local/share/icons/Animated-Mew-Cursor"
fi

# ---------- grub (ultragrub: tema + patch de entradas) ----------
ULTRAGRUB_DIR="$CONFIG_DIR/kohagi_personal_configs/ultragrub"
if [[ -d "$ULTRAGRUB_DIR" ]]; then
    step "Tema do GRUB (UltraGrub)"
    warn "Essa etapa mexe em /etc/default/grub e nos scripts de /etc/grub.d (bootloader)."
    if confirm "Instalar o tema do GRUB e aplicar o patch das entradas (deixa a entrada do Windows mais limpa)?"; then
        GRUB_BACKUP="/etc/grub-backup-$(date +%Y%m%d%H%M%S)"
        sudo mkdir -p "$GRUB_BACKUP"
        for f in /etc/default/grub /etc/grub.d/30_os-prober /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware; do
            [[ -f "$f" ]] && sudo cp -a "$f" "$GRUB_BACKUP/" 2>/dev/null
        done
        ok "Backup dos arquivos do GRUB em $GRUB_BACKUP"

        grub_install_ok=1
        info "Rodando install.sh do tema (baixa o UltraGrub do GitHub, --lang Portuguese)..."
        if ! bash "$ULTRAGRUB_DIR/install.sh" --lang Portuguese; then
            err "install.sh do tema falhou (veja a saída acima). Pulando patch_entries.sh."
            grub_install_ok=0
        fi

        if [[ "$grub_install_ok" -eq 1 ]]; then
            info "Rodando patch_entries.sh..."
            if bash "$ULTRAGRUB_DIR/patch_entries.sh"; then
                ok "Entradas do GRUB corrigidas"
                log_adapt "GRUB: tema UltraGrub + patch_entries.sh aplicados (backup em $GRUB_BACKUP)"
            else
                err "patch_entries.sh falhou. Backup dos arquivos originais está em $GRUB_BACKUP."
            fi
        fi
    else
        info "Pulado. Pra rodar depois:"
        info "  bash '$ULTRAGRUB_DIR/install.sh' --lang Portuguese && bash '$ULTRAGRUB_DIR/patch_entries.sh'"
    fi
fi

# ---------- grupo video (swayosd escrever em /sys/class/backlight) ----------
step "Permissão de brilho"
if ! groups "$USER" | grep -qw video; then
    if confirm "Adicionar seu usuário ao grupo 'video' (necessário pro swayosd controlar o brilho)?"; then
        sudo usermod -aG video "$USER"
        ok "Adicionado. Precisa relogar pra valer."
        log_adapt "usuário adicionado ao grupo 'video' (sem isso o brilho via swayosd falha por permissão)"
    fi
else
    ok "Já está no grupo video"
fi

# ---------- shell padrão ----------
step "Shell padrão"
FISH_BIN="$(command -v fish || true)"
if [[ -n "$FISH_BIN" && "$SHELL" != "$FISH_BIN" ]]; then
    if confirm "Trocar seu shell padrão para fish?"; then
        grep -qxF "$FISH_BIN" /etc/shells || echo "$FISH_BIN" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$FISH_BIN"
        ok "Shell trocado (vale a partir do próximo login)"
    fi
else
    info "Já é fish ou fish não está instalado"
fi

# ---------- resumo ----------
step "Concluído"
if [[ "${#ADAPTACOES[@]}" -gt 0 ]]; then
    echo -e "${c_bold}Adaptações feitas (código do repo original tinha isso quebrado/incompleto):${c_reset}"
    for a in "${ADAPTACOES[@]}"; do
        printf "  - %s\n" "$a"
    done
fi
echo
echo -e "${c_bold}Confira manualmente:${c_reset}"
info "Nomes de monitor (DP-1/HDMI-A-1) em autostart.sh e no kanshi -> rode 'wlr-randr' pra confirmar"
info "Cursor Animated-Mew-Cursor, se não estava instalado (ver aviso acima)"
echo
info "Pra iniciar: faça login numa TTY e rode 'mango'"

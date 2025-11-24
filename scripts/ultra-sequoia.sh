#!/usr/bin/env bash
# Ultra Sequoia Installer (Hybrid) — updated with auto-backup and DE detection
set -euo pipefail
IFS=$'\n\t'

# Paths & timestamps
TS="$(date +%Y%m%d%H%M%S)"
WORKDIR="$HOME/.local/share/sequoia_install_$TS"
BACKUP_DIR="/usr/share/sequoia_backup_$TS"

PATCH_DIR="$(pwd)/patches"
RES_DIR="$(pwd)/resources"
SCRIPTS_DIR="$(pwd)/scripts"

mkdir -p "$WORKDIR"
echo "[INFO] Workdir: $WORKDIR"
echo "[INFO] Backup dir (system): $BACKUP_DIR (created on changes)"

# ---------- helper functions ----------
bold(){ printf "\e[1m%s\e[0m\n" "$*"; }
info(){ printf "\e[34m[INFO]\e[0m %s\n" "$*"; }
warn(){ printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
ok(){ printf "\e[32m[OK]\e[0m %s\n" "$*"; }
err(){ printf "\e[31m[ERR]\e[0m %s\n" "$*"; }

confirm(){ local msg="$1"; read -rp "$msg [y/N]: " a; [[ "$a" == "y" || "$a" == "Y" ]]; }

# ---------- detect desktop environment ----------
DETECT_DE() {
  if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
    echo "$XDG_CURRENT_DESKTOP"
  elif [ -n "${DESKTOP_SESSION:-}" ]; then
    echo "$DESKTOP_SESSION"
  elif command -v gdbus >/dev/null 2>&1; then
    # try GNOME session detection
    gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.GetLoginId >/dev/null 2>&1 && echo "GNOME" || true
  else
    echo "unknown"
  fi
}

DE_NAME="$(DETECT_DE)"
info "Detected Desktop Environment: $DE_NAME"

# ---------- auto-backup helper ----------
backup_file() {
  local target="$1"
  if [ -e "$target" ]; then
    sudo mkdir -p "$BACKUP_DIR/$(dirname "$target")"
    sudo cp -a "$target" "$BACKUP_DIR/$target"
    ok "Backed up $target -> $BACKUP_DIR/$target"
  else
    warn "File to backup not found: $target"
  fi
}

backup_and_replace() {
  local target="$1"
  local src="$2"
  if [ -e "$target" ]; then
    backup_file "$target"
    sudo cp -a "$src" "$target"
    ok "Replaced $target with $src"
  else
    # try to just copy into place (mkdir if needed)
    local d
    d="$(dirname "$target")"
    sudo mkdir -p "$d"
    sudo cp -a "$src" "$target"
    ok "Installed $src -> $target"
  fi
}

# ---------- install dependencies ----------
install_dependencies() {
  info "Installing dependencies (apt) - may prompt for password..."
  sudo apt update
  sudo apt install -y git curl wget unzip jq gnome-tweaks gnome-shell-extensions \
    sassc imagemagick glib-compile-resources dconf-cli || warn "Some packages failed to install"
}

# ---------- core apply actions ----------
install_icons_and_wallpapers() {
  info "Installing icons and wallpapers (user-level)..."
  mkdir -p "$HOME/.local/share/icons/Sequoia"
  mkdir -p "$HOME/.local/share/backgrounds/sequoia"
  cp -r "$RES_DIR/icons/"* "$HOME/.local/share/icons/Sequoia/" 2>/dev/null || warn "No icons to copy"
  cp -r "$RES_DIR/wallpaper/"* "$HOME/.local/share/backgrounds/sequoia/" 2>/dev/null || warn "No wallpapers to copy"
  ok "Icons & wallpapers installed to user dir"
}

apply_gtk_theme() {
  info "Applying GTK theme (user-level) from resources..."
  mkdir -p "$HOME/.themes/Sequoia"
  cp -r "$RES_DIR/css/"* "$HOME/.themes/Sequoia/" 2>/dev/null || warn "No CSS to copy"
  gsettings set org.gnome.desktop.interface gtk-theme "Sequoia" 2>/dev/null || warn "Unable to set GTK theme automatically"
  ok "GTK theme installed"
}

apply_shell_css_user() {
  info "Applying GNOME Shell CSS (user-level fallback)"
  mkdir -p "$HOME/.local/share/gnome-shell/theme"
  if [ -f "$RES_DIR/css/sequoia.css" ]; then
    cp "$RES_DIR/css/sequoia.css" "$HOME/.local/share/gnome-shell/theme/gnome-shell.css"
    ok "User-level shell CSS applied"
  else
    warn "Shell CSS resource not found"
  fi
}

# ---------- high risk system patches ----------
patch_control_center_deep() {
  info "Control Center deep-patch (will recompile gresource if available)"
  if [ ! -f /usr/share/gnome-control-center/gnome-control-center.gresource ]; then
    warn "gnome-control-center.gresource not found — skipping deep patch"
    return 1
  fi
  if confirm "Deep-patch Control Center? This modifies system gresource and will create backups. Proceed"; then
    sudo mkdir -p "$BACKUP_DIR/usr/share/gnome-control-center"
    sudo cp -a /usr/share/gnome-control-center/gnome-control-center.gresource "$BACKUP_DIR/usr/share/gnome-control-center/gnome-control-center.gresource.bak" || true
    # Use extracted patched resource in patches/gcc (script assumes you built one)
    if [ -f "$WORKDIR/gcc/gnome-control-center.gresource" ]; then
      sudo cp -a "$WORKDIR/gcc/gnome-control-center.gresource" /usr/share/gnome-control-center/gnome-control-center.gresource
      ok "Control Center gresource replaced (backup at $BACKUP_DIR)"
    else
      warn "Patched gresource not found in $WORKDIR/gcc/ — make sure you prepared the patched resource"
    fi
  else
    warn "Skipped Control Center deep-patch"
  fi
}

patch_nautilus() {
  info "Patching Nautilus UI files (system-level)"
  local tgt1="/usr/share/nautilus/ui/nautilus.css"
  if [ -f "$PATCH_DIR/nautilus/nautilus.css" ]; then
    backup_and_replace "$tgt1" "$PATCH_DIR/nautilus/nautilus.css"
  else
    warn "No nautilus patch file found"
  fi
}

patch_gdm() {
  info "Patching GDM login screen (system-level)"
  # common gdm css path
  local tgt="/usr/share/gnome-shell/theme/gdm.css"
  if [ -f "$PATCH_DIR/gdm/gdm.css" ]; then
    if confirm "Patch GDM (login screen)? This will modify system GDM theme; proceed"; then
      backup_and_replace "$tgt" "$PATCH_DIR/gdm/gdm.css"
      # also patch gnome-shell.css if resource exists
      if [ -f "$PATCH_DIR/gdm/gnome-shell.css" ]; then
        backup_and_replace "/usr/share/gnome-shell/theme/gnome-shell.css" "$PATCH_DIR/gdm/gnome-shell.css"
      fi
      ok "GDM patched (backups stored under $BACKUP_DIR)"
    else
      warn "Skipped GDM patch"
    fi
  else
    warn "No gdm patch file found"
  fi
}

# ---------- autopatch enable / extension helper ----------
enable_extensions_best_effort() {
  info "Attempting to enable common extensions (best-effort)"
  local exts=( "dash-to-dock@micxgx.gmail.com" "user-theme@gnome-shell-extensions.gcampax.github.com" "blur-my-shell@aunetx" )
  for uuid in "${exts[@]}"; do
    gnome-extensions enable "$uuid" >/dev/null 2>&1 || warn "Could not enable $uuid automatically"
  done
  ok "Extension enable attempts finished"
}

# ---------- main flow ----------
main() {
  info "Installer started. Detected DE: $DE_NAME"
  install_dependencies
  install_icons_and_wallpapers
  apply_gtk_theme
  apply_shell_css_user

  # ask user about high-risk patches
  if confirm "Run Nautilus patch?"; then
    patch_nautilus
  fi

  if confirm "Run GDM patch?"; then
    patch_gdm
  fi

  if confirm "Run Control Center deep patch?"; then
    patch_control_center_deep
  fi

  enable_extensions_best_effort

  echo ""
  ok "Ultra Sequoia steps completed. Backups (if any) are at: $BACKUP_DIR"
  echo "If you need to rollback, run scripts/rollback.sh (it will locate latest /usr/share/sequoia_backup_*)."
}

main "$@"

#!/bin/bash

# === VARIABLES ===
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# A la date du moment...
## Génère un timestamp pour identifier les fichiers de log de manière unique.
LOG_DIR="./logs"
# Tracer les actions a tel endroit : /logs
## Définit le répertoire où les logs seront stockés.
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"
#Creation du fichier independant de logs a l'heure dediee.
## Définit le fichier de log avec un nom unique basé sur le timestamp.
CONFIG_DIR="./config"
# Declaration du dossier de configuration
## Définit le répertoire contenant les fichiers de configuration.
PACKAGE_LIST="./lists/packages.txt"
# Declaration du dossier dans lequel se trouve les packages necessaires.
## Définit le fichier contenant la liste des paquets à installer.
USERNAME=$(logname)
# L'user pour l'authentification de session par laquelle est lancee ce bash (check des droits)
## Récupère le nom de l'utilisateur connecté.
USER_HOME="/home/$USERNAME"
# Declaration du dossier de l'utilisateur
## Définit le chemin du répertoire personnel de l'utilisateur.

# === FUNCTIONS ===
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
# Va tracer les logs en silence et dater + heure le tout dans le fichier de variable $LOG_FILE.
## Fonction pour écrire des messages dans le fichier de log avec un timestamp.

check_and_install() {
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
  # Si le paquet est installe, alors...
    log "$pkg is already installed."
    # dire qu'il est deja installe.
  else
    log "Installing $pkg..."
    # Si ce n'est pas le cas, indiquer qu'il va s'installer et le tracer dans la variable precedemment declaree $pkg.
    apt install -y "$pkg" &>>"$LOG_FILE"
    # l'installer, avec accord automatique "yes" de toutes les questions durant l'install
    # + tracabilite dans le fichier de variable $LOG_FILE
    if [ $? -eq 0 ]; then
    # Cite la condition qui permet de savoir si le paquet est installe ou pas... (Je ne sais pas la lire)
      log "$pkg successfully installed."
      # Message en log indiquant la reussite de l'installation du paquet.
    else
      log "Failed to install $pkg."
      # Message en log indiquant l'echec de l'installation du paquet cite dans la variable.
    fi
    # 
  fi
}
## Vérifie si un paquet est installé. Si non, il l'installe et logue le résultat.

ask_yes_no() {
  # Commande qui permet de poser une question avec reponse oui ou non.
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}
## Pose une question avec une réponse oui/non et retourne 0 pour "oui", 1 pour "non".


# === INITIAL SETUP ===
mkdir -p "$LOG_DIR"
# Creer le dossier de log $LOG_DIR
## Crée le répertoire de logs s'il n'existe pas.
touch "$LOG_FILE"
## Crée le fichier de log.
log "Starting post-installation script. Logged user: $USERNAME"
# Lancement de l'installation du paquet par l'utilisateur variable $username (la personne loggee)
## Logue le début du script avec le nom de l'utilisateur.
if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  # Indique que le script se lance en root ?
  exit 1
fi
## Vérifie que le script est exécuté en tant que root. Sinon, il quitte.


# === 1. SYSTEM UPDATE ===
log "Updating system packages..."
#Trace que le systeme installe les paquets de mises a jour.
apt update && apt upgrade -y &>>"$LOG_FILE"
# Mise a jour des paquets systemes et sauvegarde dans le $Log_file.
## Met à jour les paquets système et logue le résultat.


# === 2. PACKAGE INSTALLATION ===
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  # Indique qu'il y a tel ou tel paquet dans la liste a installer (message textuel)
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
  # Indique qu'il n'a pas trouve les packets. (message textuel a l'ecran)
fi
## Lit la liste des paquets à partir du fichier et installe chaque paquet non commenté.


# === 3. UPDATE MOTD ===
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi
# Deplace le fichier avec les nouveaux a l'endroit qui permettra d'etre lu au bon moment ("les news")
## Met à jour le fichier MOTD (Message of the Day) si le fichier de configuration existe.


# === 4. CUSTOM .bashrc ===
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi
## Ajoute des personnalisations au fichier `.bashrc` de l'utilisateur.


# === 5. CUSTOM .nanorc ===
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi
## Ajoute des personnalisations au fichier `.nanorc` de l'utilisateur.


# === 6. ADD SSH PUBLIC KEY ===
if ask_yes_no "Would you like to add a public SSH key?"; then
# La fabuleuse question du "est-ce qu'on veut utiliser une connexion SSH" et donc ajouter sa cle publique.
  read -p "Paste your public SSH key: " ssh_key
  # Dis de coller sa cle dans le fichier ssh_key.
  mkdir -p "$USER_HOME/.ssh"
  # Creer le dossier .ssh dans le dossier racine de l'utilisateur
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi
## Demande à l'utilisateur s'il souhaite ajouter une clé
## SSH publique, puis l'ajoute au fichier `authorized_keys`.


# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi
## Configure le serveur SSH pour désactiver l'authentification par mot de
##passe et activer uniquement l'authentification par clé.


log "Post-installation script completed."
# Message indiquant la reussite du processus de script.
## Logue la fin du script et quitte avec succès.

exit 0
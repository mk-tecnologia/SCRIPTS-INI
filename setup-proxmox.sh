#!/usr/bin/env bash
# setup-proxmox.sh — Pós-instalação automatizada do Proxmox VE
set -Eeuo pipefail

APP_VERSION="1.3.1"
SCRIPT_NAME=${0##*/}
DOMAIN=""
NETWORK_INTERFACE=""
BACKUP_DIR="/root/proxmox-setup-backup-$(date +%Y%m%d-%H%M%S)"
PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKR5RW8eXT3nFrUjFBohZbMARFHB9VMASxomQIDR09SM marcos@mktecnologia.net.br'
ISSUE_LOCK_PENDING="false"
COMMUNITY_POST_INSTALL="false"
COMMUNITY_REF="b19dad180918365c57aedac5d2f1ad48717426be"
COMMUNITY_SHA256="6af05f05b4079376bd17e0aae3c63cdd2654b3dfbd24b4061458a511391201b8"

usage() {
    cat <<USAGE
Uso: $SCRIPT_NAME [--domain DOMINIO] [--interface INTERFACE]

Opções:
  -d, --domain       Nome de domínio (padrão: mk.intranet)
  -i, --interface    Bridge/interface usada para mostrar o IPv4 no /etc/issue
  --community-post-install
                     Executa opcionalmente o post-install do Community Scripts
  -h, --help         Exibe esta ajuda
  -v, --version      Exibe a versão
USAGE
}

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }

backup_file() {
    local file=$1
    if [[ -e $file || -L $file ]]; then
        mkdir -p "$BACKUP_DIR$(dirname "$file")"
        cp -a "$file" "$BACKUP_DIR$file"
    fi
}

restore_issue_lock() {
    if [[ $ISSUE_LOCK_PENDING == true ]] && command -v chattr >/dev/null; then
        chattr +i /etc/issue 2>/dev/null || true
    fi
}
trap restore_issue_lock EXIT

run_community_post_install() {
    local original sanitized answer
    original=$(mktemp /tmp/community-post-pve.XXXXXX)
    sanitized=$(mktemp /tmp/community-post-pve-sanitized.XXXXXX)

    log 'Preparando o post-install externo do Proxmox Community Scripts'
    backup_file /etc/apt
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates whiptail

    curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
        "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/${COMMUNITY_REF}/tools/pve/post-pve-install.sh" \
        -o "$original"
    printf '%s  %s\n' "$COMMUNITY_SHA256" "$original" | sha256sum -c - >/dev/null \
        || die 'checksum inválido no post-install externo do PVE'
    bash -n "$original"

    awk 'BEGIN { skip = 0 } /^# Telemetry$/ { skip = 2; next } skip > 0 { skip--; next } { print }' \
        "$original" > "$sanitized"
    if grep -Eq 'api\.func|init_tool_telemetry' "$sanitized"; then
        rm -f "$original" "$sanitized"
        die 'não foi possível remover com segurança o carregamento de telemetria'
    fi
    bash -n "$sanitized"

    printf '\nScript externo: community-scripts/ProxmoxVE@%s\n' "$COMMUNITY_REF"
    printf 'SHA-256: %s\n' "$COMMUNITY_SHA256"
    printf 'Checksum verificado e carregamento de telemetria removido.\n'
    printf 'IMPORTANTE: responda NÃO ao reboot oferecido pelo script externo.\n'
    read -r -p 'Executar agora o post-install externo do PVE? [s/N] ' answer
    if [[ ! ${answer:-n} =~ ^[SsYy]$ ]]; then
        rm -f "$original" "$sanitized"
        printf 'Post-install externo ignorado.\n'
        return
    fi

    if ! DIAGNOSTICS=no bash "$sanitized"; then
        rm -f "$original" "$sanitized"
        die 'o post-install externo do PVE terminou com erro'
    fi
    rm -f "$original" "$sanitized"
}

validate_domain() {
    [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $1 == *.* ]]
}

validate_interface() {
    ip link show dev "$1" &>/dev/null && [[ $1 != lo ]]
}

choose_domain() {
    while [[ -z $DOMAIN ]]; do
        read -r -p 'Informe o nome de domínio [mk.intranet]: ' DOMAIN
        DOMAIN=${DOMAIN:-mk.intranet}
        if ! validate_domain "$DOMAIN"; then
            printf 'Domínio inválido. Exemplo válido: mk.intranet\n' >&2
            DOMAIN=""
        fi
    done
    validate_domain "$DOMAIN" || die "domínio inválido: $DOMAIN"
}

choose_interface() {
    local -a interfaces=()
    local choice

    if [[ -n $NETWORK_INTERFACE ]]; then
        validate_interface "$NETWORK_INTERFACE" || die "interface inexistente: $NETWORK_INTERFACE"
        return
    fi

    mapfile -t interfaces < <(ip -o link show | awk -F': ' '$2 ~ /^vmbr[0-9]+(@.*)?$/ {sub(/@.*/, "", $2); print $2}')
    if ((${#interfaces[@]} == 0)); then
        mapfile -t interfaces < <(ip -o link show | awk -F': ' '$2 != "lo" {sub(/@.*/, "", $2); print $2}')
    fi
    ((${#interfaces[@]} > 0)) || die 'nenhuma interface de rede foi detectada'

    if ((${#interfaces[@]} == 1)); then
        NETWORK_INTERFACE=${interfaces[0]}
        printf 'Interface detectada: %s\n' "$NETWORK_INTERFACE"
        return
    fi

    printf 'Bridges/interfaces detectadas:\n'
    PS3='Selecione a interface usada no /etc/issue: '
    select choice in "${interfaces[@]}"; do
        if [[ -n $choice ]]; then
            NETWORK_INTERFACE=$choice
            break
        fi
        printf 'Opção inválida.\n' >&2
    done
}

while (($#)); do
    case $1 in
        -d|--domain)
            (($# >= 2)) || die "$1 requer um valor"
            DOMAIN=$2
            shift 2
            ;;
        -i|--interface)
            (($# >= 2)) || die "$1 requer um valor"
            NETWORK_INTERFACE=$2
            shift 2
            ;;
        --community-post-install) COMMUNITY_POST_INSTALL="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        -v|--version) printf '%s %s\n' "$SCRIPT_NAME" "$APP_VERSION"; exit 0 ;;
        *) die "opção desconhecida: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || die 'execute este script como root'
command -v apt-get >/dev/null || die 'apt-get não encontrado'
command -v pveversion >/dev/null || die 'Proxmox VE não detectado (pveversion ausente)'

choose_domain
choose_interface

printf '\nResumo:\n  Plataforma: %s\n  Domínio: %s\n  Interface: %s\n  Community post-install: %s\n' \
    "$(pveversion | head -n1)" "$DOMAIN" "$NETWORK_INTERFACE" "$COMMUNITY_POST_INSTALL"
read -r -p 'Aplicar os ajustes? [S/n] ' CONFIRM
[[ ${CONFIRM:-s} =~ ^[SsYy]$ ]] || die 'operação cancelada'

mkdir -p "$BACKUP_DIR"

if [[ $COMMUNITY_POST_INSTALL == true ]]; then
    run_community_post_install
fi

log 'Instalando vim e fastfetch'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y vim fastfetch

log 'Cadastrando a chave pública SSH para o usuário root'
install -d -m 0700 -o root -g root /root/.ssh
backup_file /root/.ssh/authorized_keys
touch /root/.ssh/authorized_keys
chown root:root /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
if ! grep -qxF "$PUBLIC_KEY" /root/.ssh/authorized_keys; then
    printf '%s\n' "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi

log 'Configurando o acesso SSH do root somente com chave pública'
backup_file /etc/ssh/sshd_config
if [[ -e /etc/ssh/sshd_config.d/99-mktecnologia.conf ]]; then
    backup_file /etc/ssh/sshd_config.d/99-mktecnologia.conf
    rm -f /etc/ssh/sshd_config.d/99-mktecnologia.conf
fi

SSHD_CONFIG_TEMP=$(mktemp /tmp/sshd_config.XXXXXX)
awk '
    function print_root_login_config() {
        print "# PermitRootLogin yes"
        print "PermitRootLogin prohibit-password"
    }
    BEGIN { global = 1; configured = 0 }
    {
        normalized = tolower($0)
        sub(/^[[:space:]]+/, "", normalized)
        if (global && normalized ~ /^match[[:space:]]/) {
            if (!configured) { print_root_login_config(); print ""; configured = 1 }
            global = 0
        }
        candidate = normalized
        sub(/^#[[:space:]]*/, "", candidate)
        if (global && candidate ~ /^permitrootlogin[[:space:]]+/) {
            if (!configured) { print_root_login_config(); configured = 1 }
            next
        }
        print
    }
    END {
        if (global && !configured) {
            print ""
            print "# Gerenciado por setup-proxmox.sh"
            print_root_login_config()
        }
    }
' /etc/ssh/sshd_config > "$SSHD_CONFIG_TEMP"
cat "$SSHD_CONFIG_TEMP" > /etc/ssh/sshd_config
rm -f "$SSHD_CONFIG_TEMP"

sshd -t
EFFECTIVE_ROOT_LOGIN=$(sshd -T | awk '$1 == "permitrootlogin" {print $2; exit}')
[[ $EFFECTIVE_ROOT_LOGIN == without-password || $EFFECTIVE_ROOT_LOGIN == prohibit-password ]] \
    || die "configuração SSH efetiva inesperada: PermitRootLogin $EFFECTIVE_ROOT_LOGIN"
systemctl restart ssh

log 'Configurando fastfetch no MOTD dinâmico'
backup_file /etc/update-motd.d/10-uname
cat > /etc/update-motd.d/10-uname <<'EOF'
#!/bin/sh
echo ""
fastfetch
EOF
chmod 0755 /etc/update-motd.d/10-uname

log 'Limpando /etc/motd'
backup_file /etc/motd
: > /etc/motd

log 'Configurando o getty e /etc/issue'
mkdir -p /etc/systemd/system/getty@.service.d
backup_file /etc/systemd/system/getty@.service.d/override.conf
cat > /etc/systemd/system/getty@.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \u' %I $TERM
EOF

command -v chattr >/dev/null || die 'chattr não encontrado; instale o pacote e2fsprogs'
ISSUE_LOCK_PENDING="true"
chattr -i /etc/issue 2>/dev/null || true
backup_file /etc/issue
cat > /etc/issue <<EOF

   ███╗   ███╗██╗  ██╗████████╗███████╗ ██████╗███╗   ██╗ ██████╗ ██╗      ██████╗  ██████╗ ██╗ █████╗
   ████╗ ████║██║ ██╔╝╚══██╔══╝██╔════╝██╔════╝████╗  ██║██╔═══██╗██║     ██╔═══██╗██╔════╝ ██║██╔══██╗
   ██╔████╔██║█████╔╝    ██║   █████╗  ██║     ██╔██╗ ██║██║   ██║██║     ██║   ██║██║  ███╗██║███████║
   ██║╚██╔╝██║██╔═██╗    ██║   ██╔══╝  ██║     ██║╚██╗██║██║   ██║██║     ██║   ██║██║   ██║██║██╔══██║
   ██║ ╚═╝ ██║██║  ██╗   ██║   ███████╗╚██████╗██║ ╚████║╚██████╔╝███████╗╚██████╔╝╚██████╔╝██║██║  ██║
   ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═╝
   marcos@mktecnologia.net.br
   www.mktecnologia.net.br
   Use linux :)

   ## Based in => \\S
   ## Kernel => \\r on an \\m

   ## Hostname => \\n.\\o
   ## IPV4 $NETWORK_INTERFACE => \\4{$NETWORK_INTERFACE}

   #################
   # MK Tecnologia #
   #################

EOF
chattr +i /etc/issue
ISSUE_LOCK_PENDING="false"

systemctl daemon-reload
systemctl restart getty@tty1.service

log 'Configurando /root/.bashrc'
backup_file /root/.bashrc
cat > /root/.bashrc <<'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.
export LS_OPTIONS='--color=auto'
eval "$(dircolors)"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'

# Aliases interativos para evitar alterações acidentais.
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
EOF

log 'Configurando o nome de domínio do kernel'
backup_file /etc/sysctl.d/99-custom.conf
cat > /etc/sysctl.d/99-custom.conf <<EOF
# Gerenciado por setup-proxmox.sh
kernel.domainname = $DOMAIN
EOF
sysctl --system >/dev/null

printf '\nConfiguração do Proxmox concluída. Backups: %s\n' "$BACKUP_DIR"

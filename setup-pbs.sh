#!/usr/bin/env bash
# setup-pbs.sh — Pós-instalação automatizada do Proxmox Backup Server
set -Eeuo pipefail

APP_VERSION="1.4.0"
SCRIPT_NAME=${0##*/}
DOMAIN=""
NETWORK_INTERFACE=""
BACKUP_DIR="/root/pbs-setup-backup-$(date +%Y%m%d-%H%M%S)"
PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKR5RW8eXT3nFrUjFBohZbMARFHB9VMASxomQIDR09SM marcos@mktecnologia.net.br'
ISSUE_LOCK_PENDING="false"
COMMUNITY_POST_INSTALL=""
COMMUNITY_REF="b19dad180918365c57aedac5d2f1ad48717426be"
COMMUNITY_SHA256="cd4f9871021933f52e5d032c8e2dceda16ffa74c77037a47eb0bb0c026b0ce5e"

usage() {
    cat <<USAGE
Uso: $SCRIPT_NAME [--domain DOMINIO] [--interface INTERFACE]

Opções:
  -d, --domain       Nome de domínio (padrão: mk.intranet)
  -i, --interface    Interface usada para mostrar o IPv4 no /etc/issue
  --community-post-install
                     Força a execução do post-install do Community Scripts
  --no-community-post-install
                     Ignora o post-install sem perguntar
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
    local original
    original=$(mktemp /tmp/community-post-pbs.XXXXXX)

    log 'Executando ao final o post-install externo do Proxmox Community Scripts'
    backup_file /etc/apt
    command -v curl >/dev/null || die 'curl é necessário para baixar o post-install externo'
    if ! command -v whiptail >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail \
            || die 'não foi possível instalar whiptail; corrija os repositórios APT e tente novamente'
    fi

    curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
        "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/${COMMUNITY_REF}/tools/pve/post-pbs-install.sh" \
        -o "$original"
    printf '%s  %s\n' "$COMMUNITY_SHA256" "$original" | sha256sum -c - >/dev/null \
        || die 'checksum inválido no post-install externo do PBS'
    bash -n "$original"

    printf '\nScript externo: community-scripts/ProxmoxVE@%s\n' "$COMMUNITY_REF"
    printf 'SHA-256: %s\n' "$COMMUNITY_SHA256"
    printf 'Checksum e sintaxe verificados; código externo preservado sem alterações.\n'
    printf 'ALERTA: a opção dist-upgrade pode conflitar com /etc/issue imutável.\n'

    if ! DIAGNOSTICS=no bash "$original"; then
        rm -f "$original"
        die 'o post-install externo do PBS terminou com erro'
    fi
    rm -f "$original"
}

choose_community_post_install() {
    local answer
    [[ -n $COMMUNITY_POST_INSTALL ]] && return
    read -r -p 'Deseja executar também o post-install do Proxmox Community Scripts? [s/N] ' answer
    if [[ ${answer:-n} =~ ^[SsYy]$ ]]; then
        COMMUNITY_POST_INSTALL="true"
    else
        COMMUNITY_POST_INSTALL="false"
    fi
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

    mapfile -t interfaces < <(ip -o link show | awk -F': ' '$2 ~ /^(nic|vmbr)[0-9]+(@.*)?$/ {sub(/@.*/, "", $2); print $2}')
    if ((${#interfaces[@]} == 0)); then
        mapfile -t interfaces < <(ip -o link show | awk -F': ' '$2 != "lo" {sub(/@.*/, "", $2); print $2}')
    fi
    ((${#interfaces[@]} > 0)) || die 'nenhuma interface de rede foi detectada'

    if ((${#interfaces[@]} == 1)); then
        NETWORK_INTERFACE=${interfaces[0]}
        printf 'Interface detectada: %s\n' "$NETWORK_INTERFACE"
        return
    fi

    printf 'Interfaces detectadas:\n'
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
        --no-community-post-install) COMMUNITY_POST_INSTALL="false"; shift ;;
        -h|--help) usage; exit 0 ;;
        -v|--version) printf '%s %s\n' "$SCRIPT_NAME" "$APP_VERSION"; exit 0 ;;
        *) die "opção desconhecida: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || die 'execute este script como root'
command -v apt-get >/dev/null || die 'apt-get não encontrado'
command -v proxmox-backup-manager >/dev/null || die 'Proxmox Backup Server não detectado'

choose_domain
choose_interface
choose_community_post_install

PBS_VERSION=$(proxmox-backup-manager versions 2>/dev/null | sed -n '1p' || true)
printf '\nResumo:\n  Plataforma: %s\n  Domínio: %s\n  Interface: %s\n  Community post-install: %s\n' \
    "${PBS_VERSION:-Proxmox Backup Server}" "$DOMAIN" "$NETWORK_INTERFACE" "$COMMUNITY_POST_INSTALL"
read -r -p 'Aplicar os ajustes? [S/n] ' CONFIRM
[[ ${CONFIRM:-s} =~ ^[SsYy]$ ]] || die 'operação cancelada'

mkdir -p "$BACKUP_DIR"

log 'Instalando vim, fastfetch e qemu-guest-agent'
if [[ $COMMUNITY_POST_INSTALL == true ]]; then
    apt-get update || printf 'Aviso: apt-get update parcial; o Community post-install tratará os repositórios ao final.\n' >&2
else
    apt-get update
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y vim fastfetch qemu-guest-agent

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
            print "# Gerenciado por setup-pbs.sh"
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

   ################
   # MKTECNOLOGIA #
   ################

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
# Gerenciado por setup-pbs.sh
kernel.domainname = $DOMAIN
EOF
sysctl --system >/dev/null

VIRTUALIZATION=$(systemd-detect-virt --vm 2>/dev/null || true)
if [[ $VIRTUALIZATION == kvm || $VIRTUALIZATION == qemu ]]; then
    log 'Iniciando o qemu-guest-agent'
    systemctl start qemu-guest-agent.service
else
    log 'qemu-guest-agent instalado; inicialização ignorada fora de uma VM KVM/QEMU'
fi

printf '\nConfiguração do PBS concluída. Backups: %s\n' "$BACKUP_DIR"
if [[ $COMMUNITY_POST_INSTALL == true ]]; then
    run_community_post_install
else
    read -r -p 'Deseja reiniciar o servidor agora? [s/N] ' REBOOT_ANSWER
    if [[ ${REBOOT_ANSWER:-n} =~ ^[SsYy]$ ]]; then
        systemctl reboot
    fi
fi

#!/usr/bin/env bash
# setup-debian13.sh — Pós-instalação automatizada do Debian 13
set -Eeuo pipefail

APP_VERSION="1.0.3"
SCRIPT_NAME=${0##*/}
DOMAIN=""
NETWORK_INTERFACE=""
BACKUP_DIR="/root/debian13-setup-backup-$(date +%Y%m%d-%H%M%S)"
PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKR5RW8eXT3nFrUjFBohZbMARFHB9VMASxomQIDR09SM marcos@mktecnologia.net.br'
ISSUE_LOCK_PENDING="false"

usage() {
    cat <<USAGE
Uso: $SCRIPT_NAME [--domain DOMINIO] [--interface INTERFACE]

Opções:
  -d, --domain       Nome de domínio (ex.: mk.intranet)
  -i, --interface    Interface usada para mostrar o IPv4 em /etc/issue
  -h, --help         Exibe esta ajuda
  -v, --version      Exibe a versão
USAGE
}

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

backup_file() {
    local file=$1
    if [[ -e "$file" || -L "$file" ]]; then
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

    mapfile -t interfaces < <(ip -o link show | awk -F': ' '$2 != "lo" {sub(/@.*/, "", $2); print $2}')
    ((${#interfaces[@]} > 0)) || die 'nenhuma interface de rede foi detectada'

    if [[ -n $NETWORK_INTERFACE ]]; then
        validate_interface "$NETWORK_INTERFACE" || die "interface inexistente: $NETWORK_INTERFACE"
        return
    fi

    if ((${#interfaces[@]} == 1)); then
        NETWORK_INTERFACE=${interfaces[0]}
        printf 'Interface detectada: %s\n' "$NETWORK_INTERFACE"
        return
    fi

    printf 'Interfaces de rede detectadas:\n'
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
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            printf '%s %s\n' "$SCRIPT_NAME" "$APP_VERSION"
            exit 0
            ;;
        *)
            die "opção desconhecida: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || die 'execute este script como root'
command -v apt-get >/dev/null || die 'apt-get não encontrado; este script requer Debian/Ubuntu'

choose_domain
choose_interface

printf '\nResumo:\n  Domínio: %s\n  Interface: %s\n' "$DOMAIN" "$NETWORK_INTERFACE"
read -r -p 'Aplicar os ajustes? [S/n] ' CONFIRM
[[ ${CONFIRM:-s} =~ ^[SsYy]$ ]] || die 'operação cancelada'

mkdir -p "$BACKUP_DIR"

log 'Instalando vim, qemu-guest-agent e fastfetch'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y vim qemu-guest-agent fastfetch

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
mkdir -p /etc/ssh/sshd_config.d
backup_file /etc/ssh/sshd_config.d/99-mktecnologia.conf
cat > /etc/ssh/sshd_config.d/99-mktecnologia.conf <<'EOF'
# Gerenciado por setup-debian13.sh
PermitRootLogin prohibit-password
EOF
sshd -t
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
# Gerenciado por setup-debian13.sh
kernel.domainname = $DOMAIN
EOF
sysctl --system >/dev/null

log 'Desativando os sockets SSH automáticos AF_VSOCK no GRUB'
command -v update-grub >/dev/null || die 'update-grub não encontrado'
backup_file /etc/default/grub
if grep -Eq '^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"$' /etc/default/grub; then
    GRUB_DEFAULT_ARGS=$(sed -n -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"$/\1/p' /etc/default/grub)
    if [[ " $GRUB_DEFAULT_ARGS " != *' systemd.ssh_auto=no '* ]]; then
        if [[ -n $GRUB_DEFAULT_ARGS ]]; then
            sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)"$/\1 systemd.ssh_auto=no"/' /etc/default/grub
        else
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=""$/GRUB_CMDLINE_LINUX_DEFAULT="systemd.ssh_auto=no"/' /etc/default/grub
        fi
    fi
else
    die 'formato de GRUB_CMDLINE_LINUX_DEFAULT não reconhecido em /etc/default/grub'
fi
update-grub

log 'Ativando o qemu-guest-agent'
systemctl enable --now qemu-guest-agent

printf '\nConfiguração concluída. Backups: %s\n' "$BACKUP_DIR"
printf 'Reinicie o sistema para aplicar systemd.ssh_auto=no.\n'

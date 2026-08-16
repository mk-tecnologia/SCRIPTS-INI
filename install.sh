#!/usr/bin/env bash
# install.sh — Instalador rápido do debian13-setup
set -Eeuo pipefail

INSTALLER_VERSION="1.1.0"
DEFAULT_REPO="mk-tecnologia/SCRIPTS-INI"
REPO="${SCRIPTS_INI_REPO:-$DEFAULT_REPO}"
REF="${SCRIPTS_INI_REF:-}"
RAW_BASE="${SCRIPTS_INI_RAW_BASE:-https://raw.githubusercontent.com}"
API_BASE="${SCRIPTS_INI_API_BASE:-https://api.github.com}"
TARGET="debian"
SETUP_SCRIPT="setup-debian13.sh"
INSTALL_PATH="/usr/local/sbin/debian13-setup"
ACTION="install-run"
declare -a SETUP_ARGS=()
STAGING_FILE=""

info() { printf 'ℹ️  %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

cleanup() {
    [[ -z ${STAGING_FILE:-} ]] || rm -f "$STAGING_FILE"
}
trap cleanup EXIT INT TERM

usage() {
    cat <<EOF
Instalador do SCRIPTS-INI v${INSTALLER_VERSION}

Uso: $0 [opções do instalador] [-- opções do assistente]

Opções do instalador:
  --install-only       Instala o comando sem executar os ajustes
  --uninstall          Remove o comando instalado
  --proxmox            Instala/executa o perfil para Proxmox VE
  --target ALVO        Seleciona debian ou proxmox
  --ref REF            Baixa uma tag, branch ou commit
  -h, --help           Exibe esta ajuda
  --version            Exibe a versão do instalador

Opções como --domain e --interface são encaminhadas ao assistente.

Exemplos:
  $0
  $0 --domain mk.intranet --interface ens18
  $0 --proxmox --domain brsul.intranet
  $0 --install-only
EOF
}

while (($#)); do
    case $1 in
        --install-only) ACTION="install-only"; shift ;;
        --uninstall) ACTION="uninstall"; shift ;;
        --proxmox) TARGET="proxmox"; shift ;;
        --target)
            (($# >= 2)) || die 'faltou o valor de --target'
            TARGET=$2
            shift 2
            ;;
        --ref)
            (($# >= 2)) || die 'faltou o valor de --ref'
            REF=$2
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        --version)
            printf 'debian13-setup-installer %s\n' "$INSTALLER_VERSION"
            exit 0
            ;;
        --) shift; SETUP_ARGS+=("$@"); break ;;
        *) SETUP_ARGS+=("$1"); shift ;;
    esac
done

case $TARGET in
    debian)
        SETUP_SCRIPT="setup-debian13.sh"
        INSTALL_PATH="/usr/local/sbin/debian13-setup"
        ;;
    proxmox)
        SETUP_SCRIPT="setup-proxmox.sh"
        INSTALL_PATH="/usr/local/sbin/proxmox-setup"
        ;;
    *) die "alvo inválido: $TARGET (use debian ou proxmox)" ;;
esac

[[ $EUID -eq 0 ]] || die 'execute o instalador como root'

if [[ $ACTION == uninstall ]]; then
    if [[ -e $INSTALL_PATH || -L $INSTALL_PATH ]]; then
        rm -f "$INSTALL_PATH"
        ok "Comando removido: $INSTALL_PATH"
    else
        info 'O comando não está instalado.'
    fi
    exit 0
fi

command -v curl >/dev/null || die 'curl não está instalado'
[[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "repositório inválido: $REPO"

if [[ -z $REF ]]; then
    info 'Consultando a versão estável mais recente'
    REF=$(curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 \
        -H 'Accept: application/vnd.github+json' \
        "${API_BASE}/repos/${REPO}/releases/latest" \
        | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p')
    [[ -n $REF ]] || die 'não foi possível identificar a release mais recente'
fi

[[ $REF =~ ^[A-Za-z0-9._/-]+$ ]] || die "referência inválida: $REF"

STAGING_FILE=$(mktemp /tmp/debian13-setup.XXXXXX)
info "Baixando ${REPO}@${REF}"
curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
    "${RAW_BASE}/${REPO}/${REF}/${SETUP_SCRIPT}" \
    -o "$STAGING_FILE"

bash -n "$STAGING_FILE" || die 'o script baixado contém erro de sintaxe'
install -m 0755 -o root -g root "$STAGING_FILE" "$INSTALL_PATH"
rm -f "$STAGING_FILE"
STAGING_FILE=""
ok "Comando instalado: $INSTALL_PATH"

if [[ $ACTION == install-only ]]; then
    printf 'Execute quando desejar: sudo debian13-setup\n'
    exit 0
fi

info 'Iniciando o assistente de configuração'
exec "$INSTALL_PATH" "${SETUP_ARGS[@]}"

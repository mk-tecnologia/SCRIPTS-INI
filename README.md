# SCRIPTS-INI

Assistentes de pós-instalação para Debian 13 e Proxmox VE. Instalam os pacotes
básicos e configuram SSH, chave pública do root, fastfetch, MOTD, console,
aliases e nome de domínio. O perfil Debian também ajusta o GRUB.

## Instalação rápida

No servidor Debian 13, como `root`:

```bash
apt-get update && apt-get install -y curl ca-certificates
curl -fsSLo /tmp/debian13-install.sh \
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-INI/main/install.sh
bash /tmp/debian13-install.sh
```

O primeiro comando também atende instalações mínimas do Debian, que podem não
trazer o `curl` instalado por padrão.

O instalador baixa e valida o assistente, cria o comando
`/usr/local/sbin/debian13-setup` e inicia a configuração interativa.
Por padrão, ele usa a release estável mais recente, evitando versões antigas
eventualmente mantidas no cache da referência `main`.

### Proxmox VE

No host Proxmox, use o mesmo instalador com o perfil específico:

```bash
apt-get update && apt-get install -y curl ca-certificates
curl -fsSLo /tmp/scripts-ini-install.sh \
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-INI/main/install.sh
bash /tmp/scripts-ini-install.sh --proxmox
```

O perfil valida a presença do Proxmox, usa `mk.intranet` como domínio
padrão e prioriza interfaces bridge `vmbr*`. Quando existe mais de uma bridge,
apresenta um menu; com apenas uma, seleciona-a automaticamente.

Para somente instalar o comando administrativo:

```bash
bash /tmp/scripts-ini-install.sh --proxmox --install-only
proxmox-setup
```

Durante a execução:

- o nome de domínio é solicitado e validado;
- uma única interface de rede é selecionada automaticamente;
- quando há várias interfaces, um menu permite escolher qual IPv4 mostrar;
- um resumo é exibido antes de qualquer alteração;
- arquivos alterados são copiados para um diretório de backup em `/root`.
- `systemd.ssh_auto=no` é acrescentado ao GRUB para desativar os sockets SSH
  automáticos `AF_VSOCK`; uma reinicialização é necessária para aplicá-lo.

## Execução direta

É possível informar domínio e interface no próprio comando de instalação:

```bash
bash /tmp/debian13-install.sh \
  --domain mk.intranet \
  --interface ens18
```

Para instalar o comando sem executar os ajustes imediatamente:

```bash
bash /tmp/debian13-install.sh --install-only
debian13-setup
```

Ajuda e versão:

```bash
debian13-setup --help
debian13-setup --version
```

## Versão específica

Uma tag, branch ou commit pode ser selecionado com `--ref`:

```bash
bash /tmp/debian13-install.sh --ref v1.0.0
```

## Desinstalação do comando

```bash
bash /tmp/debian13-install.sh --uninstall
```

A desinstalação remove somente `/usr/local/sbin/debian13-setup`. Ela não
desfaz configurações já aplicadas ao sistema nem remove os backups.

## Segurança SSH

A chave pública de `marcos@mktecnologia.net.br` é adicionada de forma
idempotente a `/root/.ssh/authorized_keys`. Chaves existentes são preservadas.
O login SSH do root fica permitido somente por chave pública:

```text
PermitRootLogin prohibit-password
```

O `/etc/issue` recebe o atributo imutável após a configuração para impedir que
seja sobrescrito na inicialização. Em uma nova execução, o assistente remove o
atributo temporariamente e garante sua reaplicação mesmo se ocorrer um erro.

O `PermitRootLogin prohibit-password` é gravado diretamente no arquivo
`/etc/ssh/sshd_config`. O assistente valida tanto a sintaxe (`sshd -t`) quanto o
valor efetivamente interpretado pelo servidor (`sshd -T`) antes de reiniciá-lo.
A alternativa `# PermitRootLogin yes` permanece logo acima, comentada, para
facilitar uma alteração emergencial feita conscientemente pelo administrador.

# SCRIPTS-INI

Assistente de pós-instalação para Debian 13. Instala os pacotes básicos e
configura SSH, chave pública do root, fastfetch, MOTD, console, aliases, GRUB e
nome de domínio.

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

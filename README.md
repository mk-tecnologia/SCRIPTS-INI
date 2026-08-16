# SCRIPTS-INI

Assistentes de pós-instalação para Debian 13, Proxmox VE e Proxmox Backup Server. Instalam os pacotes
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
apt-get install -y curl ca-certificates
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

### Proxmox Backup Server

```bash
apt-get install -y curl ca-certificates
curl -fsSLo /tmp/scripts-ini-install.sh \
  https://raw.githubusercontent.com/mk-tecnologia/SCRIPTS-INI/main/install.sh
bash /tmp/scripts-ini-install.sh --pbs
```

O perfil PBS valida `proxmox-backup-manager`, usa `mk.intranet` como domínio
padrão e prioriza interfaces `nic*` ou bridges `vmbr*`. O comando instalado é
`pbs-setup`.

### Community post-install opcional

Durante a instalação, os perfis PVE e PBS perguntam se devem executar, depois
das personalizações locais, o post-install do projeto
`community-scripts/ProxmoxVE`:

```bash
bash /tmp/scripts-ini-install.sh --proxmox
bash /tmp/scripts-ini-install.sh --pbs
```

As opções `--community-post-install` e `--no-community-post-install` existem
somente para automações que precisam responder essa pergunta previamente.

Essa integração não usa diretamente a referência mutável `main`. Ela baixa a
revisão fixa `b19dad180918365c57aedac5d2f1ad48717426be`, confere o SHA-256 e a
sintaxe e executa o código externo sem modificá-lo. A execução usa
`DIAGNOSTICS=no`, opção de saída da telemetria documentada pelo projeto. Antes
da execução, `/etc/apt` é copiado para o diretório de backup. Como o código é
preservado, ele ainda carrega o helper `api.func` da branch `main`, embora o
envio de diagnósticos permaneça desativado.

Antes do primeiro `apt-get update`, os perfis PVE e PBS desativam o repositório
Enterprise: entradas legadas são comentadas e arquivos `.sources` recebem
`Enabled: false` somente nos blocos que apontam para
`enterprise.proxmox.com`, incluindo os repositórios Enterprise do Ceph. Blocos
No-Subscription presentes no mesmo arquivo são preservados. O conteúdo anterior
de `/etc/apt` permanece no backup da execução. Essa política pressupõe que o
servidor não utiliza uma assinatura Enterprise ativa.

> **Atenção ao `dist-upgrade`:** o script externo pode alterar repositórios APT,
> atualizar pacotes, modificar a interface web e reiniciar o servidor. Nesse
> ponto, `/etc/issue` já estará protegido com `chattr +i`; portanto, escolher
> `dist-upgrade` pode falhar caso algum pacote tente sobrescrever esse arquivo.
> O reboot final é controlado pelo próprio Community Script.

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

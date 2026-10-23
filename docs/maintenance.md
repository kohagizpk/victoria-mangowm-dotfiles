# Manutenção e preferências pessoais

Mantenha o checkout fora de `~/.config/mango`. Se você clonou diretamente nessa pasta, mova o checkout para `~/src/victoria-mangowm-dotfiles` antes de instalar. Guarde uma cópia das suas alterações primeiro.

## Atualizar apenas os dotfiles

Execute `./install.sh --config-only --dry-run` para ver o plano e `./install.sh --config-only` para aplicar. Cada execução cria um diretório `~/victoria-backup.*` antes de alterar as configurações. O caminho é exibido no terminal. O estado do Waypaper em XDG_STATE_HOME também recebe backup.

O modo copia apenas arquivos necessários à sessão, prepara o hook do Waypaper e gera a paleta se o Wallust estiver instalado. Não usa sudo, não instala pacotes e não altera serviços ou o gerenciador de login. Se a geração falhar, o comando retorna erro; consulte o log do Wallust e o backup exibido. Para configurar Materia/Kvantum e dependências, use a instalação completa.

## Onde personalizar

| Arquivo instalado | Uso |
| --- | --- |
| `~/.config/mango/local/input.conf` | Teclado e repetição de teclas |
| `~/.config/mango/local/monitor.conf` | Regras dos seus monitores |
| `~/.config/mango/local/custom.conf` | Gaps, aparência e outras opções pessoais |

Esses arquivos são preservados nas atualizações. Teclado e customizações gerais são carregados por último; as regras pessoais de monitor são carregadas **antes** das geradas, pois o Mango usa a primeira regra correspondente. O modo de configurações migra teclado e regras pessoais de monitor da instalação anterior quando ainda não existem overrides. O par exato de monitores padrão das versões antigas é substituído pela detecção; regras editadas são mantidas. A instalação completa aplica o teclado escolhido no menu; `custom.conf` continua tendo a palavra final.

No modo de configurações, `apps.conf`, `bind.conf` e `env.conf` existentes também são preservados, com a exceção de `XCURSOR_THEME`: essa variável é alinhada ao cursor selecionado e disponível. A configuração da Waybar mantém seus módulos, sensores e ações de energia; apenas o nome antigo do script Cava é migrado. Para adotar novos atalhos padrão, compare seu arquivo com `config/mango/bind.conf` no checkout. Kitty, Fastfetch e as ações do wlogout existentes são mantidos. Os estilos gerenciados de menus e Waybar são atualizados; guarde personalizações de estilo no checkout ou no backup antes de atualizar.

Não edite arquivos de cores gerados: altere os templates em `config/wallust/templates/` e reinstale as configurações. A paleta é renderizada em uma área temporária e validada antes de substituir os resultados. Rofi, Fuzzel e wlogout usam as cores novas na próxima abertura; Fish as aplica no próximo prompt.

## Detecção dos monitores

Na instalação completa e em `--config-only`, `monitor.conf` é gerado a partir de `/sys/class/drm` e dos modos anunciados pelo driver via libdrm. Funciona também pelo TTY, sem sudo, sem abrir uma sessão gráfica e sem alterar o hardware durante a consulta. Quando disponível, usa a resolução preferencial e a maior frequência anunciada nessa resolução. Não cria modos personalizados.

As telas ficam lado a lado, em escala 1, com coordenadas positivas; a tela interna do notebook vem primeiro, seguida dos conectores em ordem alfabética. A ordem física não pode ser detectada pelo cabo. Para mudar posição, resolução, frequência, rotação ou escala, coloque uma regra completa por tela em `~/.config/mango/local/monitor.conf`. As regras pessoais prevalecem e ficam salvas nas atualizações.

Para consultar o resultado sem gravar nada:

```bash
python3 ~/.config/mango/scripts/monitors.py
```

Para detectar novamente após trocar os monitores:

```bash
python3 ~/.config/mango/scripts/monitors.py --output ~/.config/mango/monitor.conf
```

O comando só substitui arquivos marcados como gerados. Guarde alterações manuais em `local/monitor.conf`; o detector não modifica esse arquivo. Não existe um serviço de detecção contínua.

Sem acesso aos modos da GPU, a detecção usa os nomes e tamanhos disponíveis em sysfs para posicionar as telas, deixando o modo/frequência para o Mango. Sem saídas legíveis, mantém o comportamento padrão do compositor. Conectores com nomes repetidos em GPUs diferentes exigem regras manuais. O instalador não muda permissões da GPU para contornar essas limitações.

## Cursor

O padrão é `Animated-Mew-Cursor`, incluído e instalado nas duas modalidades. Se o cursor anterior estiver disponível em `themes/`, `~/.local/share/icons`, `~/.icons` ou `/usr/share/icons`, sua seleção é preservada. Um cursor ausente é substituído pelo tema incluído, mantendo `config.conf`, `env.conf` e `autostart.sh` coerentes. A instalação completa também ajusta o cursor nas configurações GTK; o modo de configurações mantém as preferências GTK existentes.

## Diagnóstico e validação

`./install.sh --diagnose` é somente leitura. Retorna 1 se encontrar componentes ausentes, com instruções de correção. Ele verifica arquivos e comandos; não substitui um teste da sessão gráfica.

`python3 -m unittest discover -s tests -v` executa testes isolados, sem instalar pacotes. Os testes com Fish e Wallust reais exigem esses binários; a CI os instala. Para validar Mango na sua máquina, use `mango -c ~/.config/mango/config.conf -p` antes de reiniciar a sessão.

## Melhorias futuras opcionais

- Menu para restaurar um backup escolhido, mostrando antes os arquivos afetados.
- Perfis leve/completo para máquinas com diferentes recursos.
- Galeria de capturas reais com diferentes wallpapers para comparar as paletas.

Essas ideias não foram ativadas; podem ser avaliadas separadamente depois de testar esta versão.

# GitHub Auto Publisher

Publicador automático de projetos Git para **Linux, macOS e Windows**. Um arquivo de configuração compartilhado (`repositore.conf`) define o repositório de destino, a branch e o nível de detalhe do relatório.

O objetivo é executar o fluxo básico de publicação com um comando: **verificar alterações → preparar arquivos → criar commit automático → sincronizar com o remoto → enviar ao GitHub**.

> **Importante:** o publicador **não cria o repositório no site do GitHub**. Crie o repositório remoto antes da primeira execução e configure a autenticação do Git na máquina.

## Funcionalidades

- Inicializa o Git com `git init -b` quando a pasta ainda não é um repositório.
- Confere se a branch atual corresponde à branch configurada.
- Adiciona o remoto `origin` caso ele ainda não exista; não sobrescreve um remoto diferente.
- Exibe os arquivos novos, modificados e removidos.
- Prepara as alterações com `git add -A`.
- Opcionalmente mostra o `git diff` completo, linha a linha.
- Gera commits automáticos no formato **Conventional Commits**.
- Executa `git pull --rebase` quando a branch remota já existe.
- Publica com `git push -u origin <branch>`, **sem `--force`**.
- Interrompe o fluxo em caso de conflito ou falha de autenticação.
- Bloqueia o commit automático de alguns arquivos sensíveis comuns, como `.env`, `.pem`, `.p12` e chaves privadas conhecidas.

## Arquivos

```text
meu-projeto/
├── repositore.conf       # Configuração compartilhada
├── publicar.sh           # Linux / macOS / Git Bash
├── publicar.bat          # Windows (Prompt de Comando)
├── README.md             # Este guia
└── ...                   # Código do seu projeto
```

**Coloque os scripts e `repositore.conf` na raiz do projeto.** Os scripts usam sua própria pasta como diretório de trabalho.

## Pré-requisitos

1. **Git** instalado e disponível no terminal.
2. **Repositório criado no GitHub** (pode estar vazio).
3. Permissão para enviar código ao repositório, com autenticação configurada (por exemplo, Git Credential Manager ou SSH).
4. Nome e email configurados no Git:

```bash
git config --global user.name "Seu Nome"
git config --global user.email "voce@exemplo.com"
```

Para conferir:

```bash
git --version
git config --get user.name
git config --get user.email
```

## Configuração — `repositore.conf`

Edite **somente** `repositore.conf` para trocar o repositório ou a branch:

```ini
# Configuração do publicador automático GitHub.
# Não coloque espaços antes/depois do sinal =.

URL_REPOSITORIO="https://github.com/SEU-USUARIO/SEU-REPOSITORIO.git"
BRANCH="main"
MOSTRAR_DIFF_COMPLETO="sim"
```

| Campo | Descrição | Exemplo |
| --- | --- | --- |
| `URL_REPOSITORIO` | URL do repositório GitHub que já existe | `https://github.com/usuario/projeto.git` |
| `BRANCH` | Branch que será publicada | `main` |
| `MOSTRAR_DIFF_COMPLETO` | Mostra as linhas alteradas com `git diff --cached` | `sim` ou `nao` |

Também é possível usar uma URL SSH, se o acesso por chave SSH estiver configurado:

```ini
URL_REPOSITORIO="git@github.com:usuario/projeto.git"
```

**Atenção:** mantenha o nome **`repositore.conf`** exatamente assim; é o nome que os dois scripts procuram. As configurações seguem o formato simples `CHAVE="valor"`; não utilize comandos de shell nem espaços ao redor de `=`.

## Como usar

### Linux / Fedora / macOS

Abra o terminal na pasta do projeto:

```bash
chmod +x publicar.sh
./publicar.sh
```

Em execuções seguintes, basta:

```bash
./publicar.sh
```

### Windows (CMD)

Abra o Prompt de Comando na pasta do projeto e execute:

```bat
publicar.bat
```

Também é possível dar duplo clique no arquivo, mas o terminal pode fechar ao concluir; para acompanhar as mensagens, prefira executá-lo no Prompt de Comando.

## O que acontece durante a publicação?

| Etapa | Ação |
| --- | --- |
| 1 | Detecta o repositório Git; inicializa se necessário. |
| 2 | Verifica `origin` e branch configurados. |
| 3 | Mostra arquivos alterados via `git status --short`. |
| 4 | Executa `git add -A` e mostra os arquivos preparados. |
| 5 | Cria um commit automático se houver mudanças. |
| 6 | Consulta a branch remota e executa `git pull --rebase` quando aplicável. |
| 7 | Envia a branch com `git push -u origin`. |

O **commit local ocorre antes do pull**. Isso evita tentar executar um rebase com alterações locais ainda não registradas. Quando a branch remota não existe, o script pula o pull e tenta criá-la com o primeiro push.

### Exemplo de saída

```text
[3/7] Arquivos alterados antes de adicionar:
 M api/main.py
?? api/estoque.py

[4/7] Mudanças preparadas para o commit:
M   api/main.py
A   api/estoque.py

[5/7] Criando commit: chore(auto): sincronizar 2 arquivo(s)

[6/7] Verificando atualizações no GitHub...
Already up to date.

[7/7] Publicando no GitHub...
PUBLICADO COM SUCESSO!
```

*Saída ilustrativa; a formatação varia entre Linux e Windows.*

## Mensagens de commit automáticas

Os scripts usam o prefixo `chore(auto):` seguido de uma descrição baseada nas operações dos arquivos:

```text
chore(auto): adicionar 3 arquivo(s)
chore(auto): atualizar 2 arquivo(s)
chore(auto): remover 1 arquivo(s)
chore(auto): sincronizar 5 arquivo(s)
```

A regra é propositalmente conservadora. O script **não tenta adivinhar** se uma mudança é uma nova funcionalidade (`feat`) ou uma correção (`fix`) analisando somente nomes de arquivos. Para commits semânticos específicos, use `git commit` manualmente.

Quando não há modificações locais, o script não cria commit vazio: ele ainda verifica o remoto e tenta sincronizar/publicar a branch.

## Segurança e boas práticas

- **Revise o relatório de mudanças** antes de compartilhar alterações importantes. O script é automático e não pede confirmação antes de publicar.
- Adicione um `.gitignore` adequado ao seu projeto, especialmente para `.env`, `.venv/`, `node_modules/`, bancos locais, logs e artefatos de build.
- A verificação de segredos bloqueia **alguns nomes de arquivos conhecidos**, mas **não examina o conteúdo** em busca de senhas, tokens ou chaves. Isso **não substitui** revisão de código e ferramentas de detecção de segredos.
- Se detectar um arquivo sensível, o script interrompe a publicação, mas o arquivo pode continuar no *stage*. Remova-o com `git restore --staged -- caminho/do/arquivo` e atualize o `.gitignore`.
- O script nunca executa `git push --force` nem troca automaticamente para uma branch diferente da configurada.
- A opção `MOSTRAR_DIFF_COMPLETO="sim"` pode exibir informações sensíveis no terminal. Use `nao` quando o histórico do terminal ou logs forem compartilhados.

Exemplo mínimo de `.gitignore` para um projeto Python:

```gitignore
.env
.env.*
!.env.example
.venv/
__pycache__/
*.py[cod]
.pytest_cache/
*.sqlite3
*.log
```

## Solução de problemas

<details>
<summary><strong>Git não encontrado</strong></summary>

Instale o Git e confirme com `git --version`. No Windows, instale o Git for Windows e abra um novo terminal.

</details>

<details>
<summary><strong>URL ou branch inválida</strong></summary>

Confira `URL_REPOSITORIO` e `BRANCH` no `repositore.conf`. A URL precisa apontar para um repositório existente e ao qual você tenha acesso.

</details>

<details>
<summary><strong>O remoto origin é diferente</strong></summary>

O script interrompe o fluxo para evitar publicar no destino errado. Verifique `git remote -v`. Se quiser alterar o destino conscientemente, execute manualmente `git remote set-url origin NOVA_URL` e mantenha a mesma URL em `repositore.conf`.

</details>

<details>
<summary><strong>Falha no pull/rebase ou conflitos</strong></summary>

Verifique os arquivos envolvidos:

```bash
git status
```

Resolva os conflitos, prepare os arquivos resolvidos e continue:

```bash
git add caminho/do/arquivo
git rebase --continue
```

Ou cancele a operação sem descartar deliberadamente seus commits locais:

```bash
git rebase --abort
```

Se o repositório local e o remoto foram criados **com históricos iniciais independentes**, o primeiro pull pode falhar com *unrelated histories*. Nesse caso, é necessária uma integração manual dos históricos; o script não força a união automaticamente.

</details>

<details>
<summary><strong>Falha no push / permissão negada</strong></summary>

Verifique a autenticação, o acesso de escrita ao repositório e eventuais regras de proteção da branch no GitHub. Um token ou chave SSH **não deve** ser colocado dentro de `repositore.conf`.

</details>

## Limitações atuais

- Não cria repositórios no GitHub via API.
- Não gera tags, releases ou pull requests.
- Não executa testes, lint ou builds automaticamente.
- Não detecta semanticamente o conteúdo das mudanças para classificar `feat` e `fix`.
- O script `.bat` é destinado ao **CMD do Windows**; o `.sh` usa **Bash**.

---

**Licença:** defina uma licença (`LICENSE`) para o projeto caso pretenda disponibilizá-lo publicamente para reutilização.

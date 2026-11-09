#!/usr/bin/env bash
# Publicador Git para Linux/macOS (Git Bash também funciona).
set -Eeuo pipefail

# O projeto e o arquivo de configuração ficam na mesma pasta do script.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
ARQUIVO_CONFIG="./repositorio.conf"
# Migra automaticamente o nome usado nas versoes anteriores.
if [[ ! -f "$ARQUIVO_CONFIG" && -f "./repositore.conf" ]]; then
  cp -- "./repositore.conf" "$ARQUIVO_CONFIG"
  printf 'Configuracao antiga copiada para repositorio.conf.\n'
fi

log()   { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
erro()  { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

# Lê um arquivo simples KEY=VALUE, também compatível com o Windows.
# Não usamos 'source' para não executar comandos eventualmente presentes no .conf.
[[ -f "$ARQUIVO_CONFIG" ]] || erro "Arquivo repositorio.conf nao encontrado. Copie example.repositorio.conf e edite a URL."
URL_REPOSITORIO=""
BRANCH=""
MOSTRAR_DIFF_COMPLETO="nao"
while IFS='=' read -r chave valor || [[ -n "$chave" ]]; do
  case "$chave" in ''|\#*) continue ;; esac
  valor="${valor%$'\r'}"
  # Aceita URL_REPOSITORIO="..." ou URL_REPOSITORIO=...
  if [[ "$valor" == \"*\" || "$valor" == \'*\' ]]; then
    valor="${valor:1:${#valor}-2}"
  fi
  case "$chave" in
    URL_REPOSITORIO) URL_REPOSITORIO="$valor" ;;
    BRANCH) BRANCH="$valor" ;;
    MOSTRAR_DIFF_COMPLETO) MOSTRAR_DIFF_COMPLETO="$valor" ;;
  esac
done < "$ARQUIVO_CONFIG"

command -v git >/dev/null 2>&1 || erro "Git não encontrado. Instale o Git primeiro."
[[ -n "$URL_REPOSITORIO" && -n "$BRANCH" ]] || erro "Configure URL_REPOSITORIO e BRANCH."
[[ "$URL_REPOSITORIO" != *"SEU-USUARIO"* && "$URL_REPOSITORIO" != *"SEU-REPOSITORIO"* ]] \
  || erro "Substitua SEU-USUARIO e SEU-REPOSITORIO na configuração."

git check-ref-format --branch "$BRANCH" >/dev/null || erro "Nome da branch inválido: $BRANCH"

# 1) Inicia repositório apenas quando necessário.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "1/7 Iniciando repositório Git..."
  git init -b "$BRANCH"
else
  # Nunca publicar, por acidente, um repositório pai.
  [[ -z "$(git rev-parse --show-prefix)" ]] \
    || erro "O script deve ficar na raiz do repositório Git, não em uma subpasta."
fi

# 2) Confere a branch atual sem sobrescrever histórico.
BRANCH_ATUAL="$(git symbolic-ref --quiet --short HEAD)" \
  || erro "HEAD desconectado (detached). Selecione uma branch antes de publicar."
if [[ "$BRANCH_ATUAL" != "$BRANCH" ]]; then
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    erro "Você está em '$BRANCH_ATUAL', mas configurou '$BRANCH'. Troque de branch manualmente."
  fi
  # Repositório novo sem commits: apenas renomeia o ramo inicial.
  git symbolic-ref HEAD "refs/heads/$BRANCH"
fi

# 3) Adiciona origin se ausente; bloqueia URLs divergentes.
log "2/7 Conferindo repositório remoto..."
if git remote get-url origin >/dev/null 2>&1; then
  URL_ATUAL="$(git remote get-url origin)"
  [[ "$URL_ATUAL" == "$URL_REPOSITORIO" ]] || erro "origin aponta para '$URL_ATUAL', diferente da URL configurada. Não alterei o remoto."
else
  git remote add origin "$URL_REPOSITORIO"
fi
printf 'Remoto: %s\nBranch: %s\n' "$URL_REPOSITORIO" "$BRANCH"

# 4) Garante que configuracoes locais nao sejam versionadas.
# Adiciona as regras ao .gitignore sem apagar regras existentes do projeto.
if [[ ! -f .gitignore ]]; then
  printf '# Configuracoes locais do publicador GitHub\n' > .gitignore
fi
for padrao in '/repositorio.conf' '/repositore.conf'; do
  grep -Fqx -- "$padrao" .gitignore || printf '%s\n' "$padrao" >> .gitignore
done

log "3/7 Arquivos alterados (antes de adicionar)..."
git -c core.quotepath=false status --short

# O .gitignore evita adiciona-las; se ja rastreadas, removemos do indice abaixo.
git add -A

# Caso alguma configuracao ja esteja rastreada, remove SOMENTE do indice.
# Isso cria um commit de remocao, sem apagar o arquivo do computador.
for privado in repositorio.conf repositore.conf; do
  if git ls-files --error-unmatch -- "$privado" >/dev/null 2>&1; then
    log "Removendo '$privado' do controle de versao (mantendo arquivo local)..."
    git rm --cached -f -- "$privado"
  fi
done

log "4/7 Mudanças preparadas para o commit..."
git -c core.quotepath=false diff --cached --name-status
git diff --cached --stat

# Nunca faça commit automático de arquivos comuns de segredo.
# Adicione outros padrões ao .gitignore do seu projeto.
while IFS= read -r arquivo; do
  nome="${arquivo##*/}"
  case "$nome" in
    .env.example|.env.sample|.env.template) ;;
    .env|.env.*|*.pem|*.p12|*.pfx|id_rsa|id_ed25519)
      erro "Arquivo sensível preparado: '$arquivo'. Remova-o do stage com 'git restore --staged -- \"$arquivo\"' e configure o .gitignore."
      ;;
  esac
done < <(git -c core.quotepath=false diff --cached --name-only --diff-filter=ACMRT)

if [[ "$MOSTRAR_DIFF_COMPLETO" == "sim" ]]; then
  log "Diferenças linha a linha (arquivos de texto)..."
  # Nunca imprime o conteudo das configuracoes privadas, nem suas exclusoes.
  git --no-pager -c core.quotepath=false diff --cached --no-ext-diff -- . \
    ':(exclude)repositorio.conf' ':(exclude)repositore.conf'
fi

# 5) Cria mensagem Conventional Commits com base na operação dos arquivos.
if ! git diff --cached --quiet; then
  git config user.name >/dev/null || erro "Configure: git config --global user.name 'Seu Nome'"
  git config user.email >/dev/null || erro "Configure: git config --global user.email 'seu@email.com'"

  adicionados=$(git diff --cached --name-only --diff-filter=A | wc -l | tr -d '[:space:]')
  removidos=$(git diff --cached --name-only --diff-filter=D | wc -l | tr -d '[:space:]')
  total=$(git diff --cached --name-only | wc -l | tr -d '[:space:]')

  acao="sincronizar"
  if (( adicionados == total )); then
    acao="adicionar"
  elif (( removidos == total )); then
    acao="remover"
  elif (( adicionados == 0 && removidos == 0 )); then
    acao="atualizar"
  fi

  # Tipo 'chore': arquivos modificados não provam, por si só, feat ou fix.
  MENSAGEM="chore(auto): $acao $total arquivo(s)"
  log "5/7 Criando commit automático: $MENSAGEM"
  git commit -m "$MENSAGEM"
else
  log "5/7 Nenhuma alteração local para commitar."
fi

# Sem commits não há nada para publicar.
git rev-parse --verify HEAD >/dev/null 2>&1 \
  || erro "O repositório está sem commits. Adicione arquivos e execute novamente."

# 6) Sincroniza com o remoto antes de enviar. Rebase não força sobrescrita.
log "6/7 Verificando atualizações no GitHub..."
if git ls-remote --exit-code --heads origin "refs/heads/$BRANCH" >/dev/null; then
  if ! git pull --rebase origin "$BRANCH"; then
    erro "Pull/rebase interrompido (possível conflito). Resolva com 'git status', 'git add ...' e 'git rebase --continue'; ou cancele com 'git rebase --abort'. Não execute push até resolver."
  fi
else
  resultado=$?
  [[ "$resultado" -eq 2 ]] || erro "Não foi possível consultar o remoto (rede/autenticação/URL)."
  printf 'Branch remota ainda não existe; será criada no push.\n'
fi

# 7) Publica e mostra a situação final.
log "7/7 Publicando no GitHub..."
git push -u origin "$BRANCH" || erro "Falha no push. Confira acesso, autenticação e proteção da branch."

log "Publicado com sucesso!"
git log -1 --format='Último commit: %h %s'
git status --short
printf 'Destino: %s (branch: %s)\n' "$URL_REPOSITORIO" "$BRANCH"

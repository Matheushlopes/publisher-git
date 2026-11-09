@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM Scripts e repositorio.conf na raiz; example.repositorio.conf e modelo versionavel.
cd /d "%~dp0" || goto :erro
set "ARQUIVO_CONFIG=%~dp0repositorio.conf"
if not exist "%ARQUIVO_CONFIG%" if exist "%~dp0repositore.conf" (
    copy /y "%~dp0repositore.conf" "%ARQUIVO_CONFIG%" >nul || goto :erro
    echo Configuracao antiga copiada para repositorio.conf.
)
if not exist "%ARQUIVO_CONFIG%" (
    echo ERRO: Crie repositorio.conf a partir de example.repositorio.conf.
    exit /b 1
)
set "URL_REPOSITORIO="
set "BRANCH="
set "MOSTRAR_DIFF_COMPLETO=nao"
REM O mesmo arquivo .conf atende Linux e Windows.
REM Linhas vazias ou iniciadas com # sao ignoradas.
for /f "usebackq tokens=1,* delims==" %%A in ("%ARQUIVO_CONFIG%") do (
    if /i "%%A"=="URL_REPOSITORIO" set "URL_REPOSITORIO=%%~B"
    if /i "%%A"=="BRANCH" set "BRANCH=%%~B"
    if /i "%%A"=="MOSTRAR_DIFF_COMPLETO" set "MOSTRAR_DIFF_COMPLETO=%%~B"
)

where git >nul 2>&1 || (echo ERRO: Git nao encontrado. Instale Git for Windows. & exit /b 1)
if "%URL_REPOSITORIO%"=="" (echo ERRO: Configure URL_REPOSITORIO. & exit /b 1)
if "%BRANCH%"=="" (echo ERRO: Configure BRANCH. & exit /b 1)
echo %URL_REPOSITORIO% | findstr /C:"SEU-USUARIO" /C:"SEU-REPOSITORIO" >nul
if not errorlevel 1 (echo ERRO: Substitua os campos da URL. & exit /b 1)

git check-ref-format --branch "%BRANCH%" >nul 2>&1 || (echo ERRO: Nome de branch invalido. & exit /b 1)

REM 1) Inicia Git, se ainda não for um repositório.
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo.
    echo [1/7] Iniciando repositorio Git...
    git init -b "%BRANCH%" || goto :erro
) else (
    REM Se houver um repositório pai, exija que o script esteja na raiz.
    for /f "delims=" %%P in ('git rev-parse --show-prefix') do set "GIT_PREFIX=%%P"
    if defined GIT_PREFIX (echo ERRO: Salve o script na raiz do repositorio. & exit /b 1)
)

REM 2) Verifica a branch sem trocar historico existente.
for /f "delims=" %%B in ('git symbolic-ref --quiet --short HEAD 2^>nul') do set "BRANCH_ATUAL=%%B"
if not defined BRANCH_ATUAL (echo ERRO: HEAD desconectado. Selecione uma branch. & exit /b 1)
if /i not "%BRANCH_ATUAL%"=="%BRANCH%" (
    git rev-parse --verify HEAD >nul 2>&1
    if not errorlevel 1 (
        echo ERRO: Branch atual diferente da configurada. Troque de branch manualmente.
        exit /b 1
    )
    git symbolic-ref HEAD "refs/heads/%BRANCH%" || goto :erro
)

REM 3) Confere origin. Nunca muda a URL existente sem avisar.
echo.
echo [2/7] Conferindo repositorio remoto...
git remote get-url origin >nul 2>&1
if errorlevel 1 (
    git remote add origin "%URL_REPOSITORIO%" || goto :erro
) else (
    call :conferir_origin || exit /b 1
)
echo Remoto: %URL_REPOSITORIO%
echo Branch: %BRANCH%

REM 4) Insere exclusoes no .gitignore sem sobrescrever as regras do projeto.
if not exist ".gitignore" >".gitignore" echo # Configuracoes locais do publicador GitHub
findstr /L /X /C:"/repositorio.conf" ".gitignore" >nul 2>&1 || >>".gitignore" echo /repositorio.conf
findstr /L /X /C:"/repositore.conf" ".gitignore" >nul 2>&1 || >>".gitignore" echo /repositore.conf

echo.
echo [3/7] Arquivos alterados antes de adicionar:
git -c core.quotepath=false status --short
REM Prepara todas as alteracoes; arquivos privados serao desindexados abaixo.
git add -A || goto :erro
REM Se antes foram rastreados, remove do indice mas preserva no disco.
git ls-files --error-unmatch -- "repositorio.conf" >nul 2>&1
if not errorlevel 1 (
    echo Removendo repositorio.conf do Git, mantendo copia local...
    git rm --cached -f -- "repositorio.conf" || goto :erro
)
git ls-files --error-unmatch -- "repositore.conf" >nul 2>&1
if not errorlevel 1 (
    echo Removendo repositore.conf do Git, mantendo copia local...
    git rm --cached -f -- "repositore.conf" || goto :erro
)

echo.
echo [4/7] Mudancas preparadas para o commit:
git -c core.quotepath=false diff --cached --name-status
git diff --cached --stat
REM Bloqueia arquivos sensiveis comuns antes do commit.
for /f "delims=" %%F in ('git -c core.quotepath=false diff --cached --name-only --diff-filter=ACMRT') do (
    call :verificar_segredo "%%F"
    if errorlevel 1 goto :segredo
)

if /i "%MOSTRAR_DIFF_COMPLETO%"=="sim" (
    echo.
    echo Diferencas linha a linha:
    REM Nao exibe conteudo ou exclusao do arquivo privado.
    git --no-pager -c core.quotepath=false diff --cached --no-ext-diff -- . ":(exclude)repositorio.conf" ":(exclude)repositore.conf"
)

REM 5) Cria commit com prefixo Conventional Commits.
git diff --cached --quiet
if errorlevel 1 (
    call :commitar || goto :erro
) else (
    echo.
    echo [5/7] Nenhuma alteracao local para commitar.
)

git rev-parse --verify HEAD >nul 2>&1 || (echo ERRO: Repositorio sem commits. & exit /b 1)

REM 6) Sincroniza antes do push; se der conflito, para para resolucao manual.
echo.
echo [6/7] Verificando atualizacoes no GitHub...
git ls-remote --exit-code --heads origin "refs/heads/%BRANCH%" >nul
if "%ERRORLEVEL%"=="0" (
    git pull --rebase origin "%BRANCH%"
    if errorlevel 1 goto :conflito
) else (
    if "%ERRORLEVEL%"=="2" (
        echo Branch remota nao existe. Sera criada no push.
    ) else (
        echo ERRO: Falha ao consultar o remoto. Verifique conexao e acesso.
        exit /b 1
    )
)

REM 7) Publica e mostra o resultado.
echo.
echo [7/7] Publicando no GitHub...
git push -u origin "%BRANCH%" || goto :erro

echo.
echo PUBLICADO COM SUCESSO!
git log -1 --format="Ultimo commit: %%h %%s"
git status --short
echo Destino: %URL_REPOSITORIO% [branch: %BRANCH%]
exit /b 0

:conferir_origin
for /f "delims=" %%U in ('git remote get-url origin') do set "URL_ATUAL=%%U"
if /i not "%URL_ATUAL%"=="%URL_REPOSITORIO%" (
    echo ERRO: origin difere da URL configurada: %URL_ATUAL%
    echo Nao alterei o remoto.
    exit /b 1
)
exit /b 0

:commitar
git config user.name >nul 2>&1 || (echo ERRO: Execute git config --global user.name "Seu Nome" & exit /b 1)
git config user.email >nul 2>&1 || (echo ERRO: Execute git config --global user.email "seu@email.com" & exit /b 1)
call :gerar_mensagem
echo.
echo [5/7] Criando commit: %MENSAGEM%
git commit -m "%MENSAGEM%" || exit /b 1
exit /b 0

:gerar_mensagem
set "ADICIONADOS=0"
set "REMOVIDOS=0"
set "TOTAL=0"
for /f %%N in ('git diff --cached --name-only --diff-filter=A ^| find /c /v ""') do set "ADICIONADOS=%%N"
for /f %%N in ('git diff --cached --name-only --diff-filter=D ^| find /c /v ""') do set "REMOVIDOS=%%N"
for /f %%N in ('git diff --cached --name-only ^| find /c /v ""') do set "TOTAL=%%N"
set "ACAO=sincronizar"
if %ADICIONADOS% EQU %TOTAL% set "ACAO=adicionar"
if %REMOVIDOS% EQU %TOTAL% set "ACAO=remover"
if %ADICIONADOS% EQU 0 if %REMOVIDOS% EQU 0 set "ACAO=atualizar"
set "MENSAGEM=chore(auto): %ACAO% %TOTAL% arquivo(s)"
exit /b 0

:verificar_segredo
set "NOME=%~nx1"
if /i "%NOME%"==".env.example" exit /b 0
if /i "%NOME%"==".env.sample" exit /b 0
if /i "%NOME%"==".env.template" exit /b 0
if /i "%NOME%"==".env" exit /b 1
if /i "%NOME:~0,5%"==".env." exit /b 1
if /i "%NOME:~-4%"==".pem" exit /b 1
if /i "%NOME:~-4%"==".p12" exit /b 1
if /i "%NOME:~-4%"==".pfx" exit /b 1
if /i "%NOME%"=="id_rsa" exit /b 1
if /i "%NOME%"=="id_ed25519" exit /b 1
exit /b 0

:segredo
echo.
echo ERRO: Foi detectado arquivo potencialmente sensivel entre os arquivos preparados.
echo Revise 'git diff --cached --name-only' e configure o .gitignore.
echo Para tirar um arquivo do stage: git restore --staged -- "nome-do-arquivo"
exit /b 1

:conflito
echo.
echo ERRO: Falha no pull/rebase. Pode haver conflitos.
echo Resolva: git status ^& git add ... ^& git rebase --continue
echo Ou cancele: git rebase --abort
exit /b 1

:erro
echo.
echo ERRO: Publicacao interrompida. Confira as mensagens acima.
exit /b 1

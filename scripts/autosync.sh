#!/bin/bash
# Salvamento automático (padrão quiz-aritan).
# A cada execução: se houver alteração, faz commit + push no GitHub (o Netlify publica sozinho)
# e registra o histórico na nota do projeto no Obsidian.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="$(basename "$REPO")"
PROJETO="Residencial Ere"
SITE="curylançamento.com.br"
VAULT="$HOME/Cérebro/CÉREBRO/Cerebro-Claude"
PASTA_OBS="$VAULT/01-Projetos/$PROJETO"
NOTA="$VAULT/01-Projetos/Projeto - $PROJETO.md"
LOG="$REPO/.autosync.log"
LOCK="/tmp/$SLUG-autosync.lock"

cd "$REPO" || exit 1

# Evita duas execuções ao mesmo tempo
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK"' EXIT

# Nada mudou: sai
[ -z "$(git status --porcelain)" ] && exit 0

# Espera os arquivos pararem de mudar (evita salvar no meio de uma edição)
ANTES=$(git status --porcelain | shasum)
sleep 15
DEPOIS=$(git status --porcelain | shasum)
[ "$ANTES" != "$DEPOIS" ] && exit 0

AGORA=$(date '+%d/%m/%Y %H:%M')

# Trava de segurança: o GitHub recusa arquivos acima de 100 MB e isso trava o envio.
# Arquivo novo/alterado acima de 95 MB: NÃO salva e avisa no log (uma vez por hora).
GRANDES=$(git status --porcelain -uall | cut -c4- | sed 's/^"//; s/"$//' | while IFS= read -r f; do
  [ -f "$f" ] && [ "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")" -gt 99614720 ] && echo "$f"; done)
if [ -n "$GRANDES" ]; then
  AVISO="/tmp/$SLUG-autosync-grande.$(date +%Y%m%d%H)"
  if [ ! -f "$AVISO" ]; then
    touch "$AVISO"
    echo "$AGORA | PAUSADO: arquivo acima de 95 MB ($(echo $GRANDES)). Comprima ou coloque no .gitignore." >> "$LOG"
  fi
  exit 0
fi

ARQUIVOS=$(git status --porcelain | cut -c4- | tr '\n' ',' | sed 's/,$//; s/,/, /g')

git add -A
git commit -q -m "auto: $AGORA - $ARQUIVOS"

if git pull -q --rebase origin main >>"$LOG" 2>&1 && git push -q origin main >>"$LOG" 2>&1; then
  RESULTADO="salvo no GitHub e publicado"
else
  git rebase --abort >/dev/null 2>&1
  RESULTADO="ERRO ao enviar ao GitHub (ver .autosync.log)"
fi
echo "$AGORA | $ARQUIVOS | $RESULTADO" >> "$LOG"

# Espelho no Obsidian
if [ -d "$VAULT" ]; then
  mkdir -p "$PASTA_OBS"
  cp README.md "$PASTA_OBS/$PROJETO - README.md" 2>/dev/null
  cp CLAUDE.md "$PASTA_OBS/$PROJETO - CLAUDE.md" 2>/dev/null
  [ -f "$NOTA" ] || printf '# Projeto - %s\n\nSite %s. Histórico do salvamento automático:\n\n' "$PROJETO" "$SITE" > "$NOTA"
  echo "- $AGORA: $ARQUIVOS ($RESULTADO)" >> "$NOTA"
fi

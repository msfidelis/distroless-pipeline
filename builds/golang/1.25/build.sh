#!/usr/bin/env bash
# build.sh — Build local efêmero: Melange + APKO
#
# Gera um par de chaves RSA temporário por execução, compila os pacotes APK
# com Melange, monta a imagem OCI com APKO e destrói a chave privada ao final.
# Não requer nenhum secret, credencial ou arquivo de chave persistido.
#
# Uso:
#   ./build.sh [TAG]
#   TAG — tag da imagem gerada (default: golang-1.25-distroless:local)
#
# Pré-requisitos:
#   docker (para executar Melange e APKO via imagens Chainguard)
#   ou: melange e apko instalados localmente (https://github.com/chainguard-dev)

set -euo pipefail

# ── Configuração ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="${1:-golang-1.25-distroless:local}"
OUTPUT_TAR="${SCRIPT_DIR}/image.tar"
PACKAGES_DIR="${SCRIPT_DIR}/packages"
KEYRING_DIR="${SCRIPT_DIR}/melange-keyring"

# ── Chave efêmera em diretório temporário ───────────────────────────────────
# O trap garante que a chave privada seja destruída mesmo em caso de erro.
EPHEMERAL_KEY_DIR="$(mktemp -d)"

cleanup() {
  if [[ -f "${EPHEMERAL_KEY_DIR}/melange.rsa" ]]; then
    shred -u "${EPHEMERAL_KEY_DIR}/melange.rsa" 2>/dev/null \
      || rm -f "${EPHEMERAL_KEY_DIR}/melange.rsa"
    echo "[build.sh] Chave privada efêmera destruída."
  fi
  rm -rf "${EPHEMERAL_KEY_DIR}"
}
trap cleanup EXIT INT TERM

EPHEMERAL_PRIVKEY="${EPHEMERAL_KEY_DIR}/melange.rsa"
EPHEMERAL_PUBKEY="${EPHEMERAL_KEY_DIR}/melange.rsa.pub"

# ── Funções auxiliares ───────────────────────────────────────────────────────
log()  { echo "[build.sh] $*"; }
step() { echo ""; echo "[build.sh] ── $* ──────────────────────────────────"; }

# Detecta se melange/apko estão disponíveis como binários ou usa Docker
run_melange() {
  if command -v melange &>/dev/null; then
    melange "$@"
  else
    docker run --rm --privileged \
      -v "${SCRIPT_DIR}":/work \
      -v "${EPHEMERAL_KEY_DIR}":/keys \
      -w /work \
      cgr.dev/chainguard/melange "$@"
  fi
}

run_apko() {
  if command -v apko &>/dev/null; then
    apko "$@"
  else
    docker run --rm \
      -v "${SCRIPT_DIR}":/work \
      -v "${EPHEMERAL_KEY_DIR}":/keys \
      -w /work \
      cgr.dev/chainguard/apko "$@"
  fi
}

# ── Step 1: Gerar chave efêmera ──────────────────────────────────────────────
step "Gerando par de chaves RSA efêmero"
if command -v melange &>/dev/null; then
  # Se melange está instalado localmente, roda no diretório temporário
  (cd "${EPHEMERAL_KEY_DIR}" && melange keygen && chmod 600 melange.rsa)
else
  # Via Docker
  docker run --rm \
    -v "${EPHEMERAL_KEY_DIR}":/work \
    -w /work \
    sh -c 'melange keygen && chmod 600 melange.rsa'
fi

# Extrai a chave pública a partir da privada (OpenSSL)
openssl rsa -in "${EPHEMERAL_PRIVKEY}" -pubout \
  -out "${EPHEMERAL_PUBKEY}" 2>/dev/null || \
openssl pkey -in "${EPHEMERAL_PRIVKEY}" -pubout \
  -out "${EPHEMERAL_PUBKEY}"
log "Chave efêmera gerada em: ${EPHEMERAL_KEY_DIR} (temporário)"

# Copia a chave pública para o keyring do projeto (referenciada pelo apko.yaml)
mkdir -p "${KEYRING_DIR}"
cp "${EPHEMERAL_PUBKEY}" "${KEYRING_DIR}/melange.rsa.pub"
log "Chave pública copiada para: ${KEYRING_DIR}/melange.rsa.pub"

# ── Step 2: Build dos pacotes APK com Melange ────────────────────────────────
step "Build pacotes APK (Melange)"
mkdir -p "${PACKAGES_DIR}"
run_melange build melange.yaml \
  --arch amd64,arm64 \
  --signing-key "${EPHEMERAL_PRIVKEY}" \
  --out-dir "${PACKAGES_DIR}"
log "Pacotes gerados em: ${PACKAGES_DIR}"

# Chave privada já não é mais necessária — destruída aqui explicitamente
# (o trap também garante isso em qualquer saída)
shred -u "${EPHEMERAL_PRIVKEY}" 2>/dev/null \
  || rm -f "${EPHEMERAL_PRIVKEY}"
log "Chave privada efêmera destruída após build dos pacotes."

# ── Step 3: Build da imagem OCI com APKO ────────────────────────────────────
step "Build imagem OCI (APKO)"
run_apko build apko.yaml \
  "${IMAGE_TAG}" \
  "${OUTPUT_TAR}"
log "Imagem gerada em: ${OUTPUT_TAR}"

# ── Step 4: Load opcional no Docker local ───────────────────────────────────
if command -v docker &>/dev/null; then
  step "Carregando imagem no Docker local"
  docker load < "${OUTPUT_TAR}"
  log "Imagem disponível como: ${IMAGE_TAG}"
fi

# ── Resumo ───────────────────────────────────────────────────────────────────
echo ""
echo "[build.sh] ════════════════════════════════════════════"
echo "[build.sh]  Build concluído com sucesso!"
echo "[build.sh]  Imagem : ${IMAGE_TAG}"
echo "[build.sh]  Tar    : ${OUTPUT_TAR}"
echo "[build.sh]  Chave privada efêmera: destruída"
echo "[build.sh] ════════════════════════════════════════════"
echo ""
echo "Para executar os smoke tests:"
echo "  ./tests/smoke.sh \"${IMAGE_TAG}\""

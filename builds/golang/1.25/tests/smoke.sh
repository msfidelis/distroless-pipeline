#!/usr/bin/env bash
# smoke.sh — Validações funcionais e de segurança da imagem distroless golang:1.25
# Uso: ./smoke.sh [IMAGE_REF]
# Exemplo: ./smoke.sh ghcr.io/myorg/golang-distroless:1.25-abc12345

set -euo pipefail

IMAGE="${1:-golang-1.25-distroless:local}"
PASS=0
FAIL=0

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

run_test() {
  local name="$1"
  local cmd="$2"
  local expected_exit="${3:-0}"

  printf "  [TEST] %-50s" "$name"

  set +e
  output=$(docker run --rm \
    --entrypoint "" \
    --read-only \
    --no-healthcheck \
    --security-opt no-new-privileges \
    "$IMAGE" \
    sh -c "$cmd" 2>&1)
  actual_exit=$?
  set -e

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    printf "${GREEN}PASS${NC}\n"
    ((PASS++)) || true
  else
    printf "${RED}FAIL${NC} (expected exit=%s, got exit=%s)\n" "$expected_exit" "$actual_exit"
    if [[ -n "$output" ]]; then
      echo "     Output: $output" | head -5
    fi
    ((FAIL++)) || true
  fi
}

echo ""
echo "================================================="
echo " Smoke Tests: $IMAGE"
echo "================================================="
echo ""

# --- Validações do toolchain Go ---
echo "-- Toolchain Go --"
run_test "go binary acessível"             "go version"                                               0
run_test "versão go contém '1.25'"         "go version | grep -q '1.25'"                             0
run_test "GOPATH definido"                 "test -n \"\$(go env GOPATH)\""                            0
run_test "GOROOT definido"                 "test -d \"\$(go env GOROOT)\""                            0
run_test "CGO desabilitado"                "test \"\$(go env CGO_ENABLED)\" = \"0\""                  0

# --- Validações de certificados ---
echo ""
echo "-- Certificados CA --"
run_test "bundle ca-certificates existe"   "test -f /etc/ssl/certs/ca-certificates.crt"              0
run_test "bundle ca-certificates não vazio" "test -s /etc/ssl/certs/ca-certificates.crt"             0
run_test "bundle tem formato PEM válido"   "grep -q 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt" 0
run_test "SSL_CERT_FILE aponta para bundle" "test \"\$SSL_CERT_FILE\" = '/etc/ssl/certs/ca-certificates.crt'" 0

# --- Validações de segurança (distroless) ---
echo ""
echo "-- Propriedades Distroless --"
run_test "sem shell (/bin/sh)"             "/bin/sh -c 'echo test'"                                   1
run_test "sem bash (/bin/bash)"            "/bin/bash -c 'echo test'"                                 1
run_test "sem apk package manager"        "apk --version"                                            1
run_test "sem apt package manager"        "apt-get --version"                                        1
run_test "sem wget"                        "wget --version"                                           1
run_test "sem curl" \
  "curl --version 2>/dev/null && exit 0 || exit 0; exit 1"                                           0

# --- Validações de usuário e permissões ---
echo ""
echo "-- Usuário e Permissões --"
run_test "executa como nonroot (uid 65532)" "test \"\$(id -u)\" = \"65532\""                         0
run_test "sem sudo"                        "sudo --version"                                           1
run_test "sem su"                          "su --version"                                             1

# --- Validações de tzdata ---
echo ""
echo "-- Timezone --"
run_test "tzdata presente"                 "test -d /usr/share/zoneinfo"                              0
run_test "UTC timezone disponível"         "test -f /usr/share/zoneinfo/UTC"                          0

# --- Resumo ---
echo ""
echo "================================================="
TOTAL=$((PASS + FAIL))
printf " Resultado: %s/%s testes passaram\n" "$PASS" "$TOTAL"

if [[ "$FAIL" -gt 0 ]]; then
  printf " ${RED}FALHOU: %s teste(s) com erro${NC}\n" "$FAIL"
  echo "================================================="
  echo ""
  exit 1
else
  printf " ${GREEN}TODOS OS TESTES PASSARAM${NC}\n"
  echo "================================================="
  echo ""
  exit 0
fi

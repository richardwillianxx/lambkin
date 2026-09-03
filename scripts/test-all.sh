#!/usr/bin/env bash

set -e

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"

cd "$ROOT_DIR"

echo
echo "========================================"
echo " LAMBKIN - TESTE COMPLETO DO BACKEND"
echo "========================================"
echo

run_test() {
  SCRIPT="$1"
  NAME="$2"

  echo
  echo "----------------------------------------"
  echo " $NAME"
  echo "----------------------------------------"
  echo

  "./scripts/$SCRIPT"
}

run_test \
  "test-auth.sh" \
  "AUTENTICAÇÃO"

run_test \
  "test-people-users.sh" \
  "PEOPLE / USERS / GUARDIANS"

run_test \
  "test-posts-media.sh" \
  "POSTS / MEDIA"

run_test \
  "test-media-s3.sh" \
  "MEDIA / AWS S3"

run_test \
  "test-quizzes-ranking.sh" \
  "QUIZZES / RANKING"

run_test \
  "test-recitatives.sh" \
  "RECITATIVOS"

run_test \
  "test-admin-audit.sh" \
  "ADMIN / AUDITORIA"

echo
echo "========================================"
echo " ✅ TODOS OS TESTES DO BACKEND PASSARAM"
echo "========================================"
echo
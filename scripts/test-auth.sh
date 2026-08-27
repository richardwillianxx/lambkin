#!/usr/bin/env bash

set -e

API="http://localhost:3000"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BODY="$(mktemp)"
COOKIE_JAR="$(mktemp)"
OLD_COOKIE_JAR="$(mktemp)"

trap 'rm -f "$BODY" "$COOKIE_JAR" "$OLD_COOKIE_JAR"' EXIT

cd "$ROOT_DIR"

# Carrega MYSQL_ROOT_PASSWORD do .env da raiz
set -a
source .env
set +a

echo
echo "========================================"
echo " LAMBKIN - TESTE COMPLETO AUTENTICAÇÃO"
echo "========================================"
echo

# ------------------------------------------------------------
# Funções auxiliares
# ------------------------------------------------------------

check_status() {
  EXPECTED="$1"
  ACTUAL="$2"
  NAME="$3"

  if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✅ $NAME"
  else
    echo "❌ $NAME"
    echo "Esperado: HTTP $EXPECTED"
    echo "Recebido: HTTP $ACTUAL"
    echo
    cat "$BODY"
    echo
    exit 1
  fi
}

json_field() {
  python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$1" "$2"
}

# ------------------------------------------------------------
# Preparar usuário de teste
# ------------------------------------------------------------

echo "Preparando dados de teste..."

PASSWORD="Teste123"
NEW_PASSWORD="NovaSenha123"

HASH="$(
  cd "$ROOT_DIR/apps/api"

  node -e "
    const argon2 = require('argon2');

    argon2
      .hash('$PASSWORD', { type: argon2.argon2id })
      .then(console.log)
      .catch(error => {
        console.error(error);
        process.exit(1);
      });
  "
)"

docker exec -i lambkin-db \
  mysql \
  -uroot \
  -p"$MYSQL_ROOT_PASSWORD" \
  lambkin_db <<SQL

DELETE FROM user_tokens
WHERE user_id IN (
    SELECT id
    FROM users
    WHERE username = 'auth_test'
);

DELETE FROM user_sessions
WHERE user_id IN (
    SELECT id
    FROM users
    WHERE username = 'auth_test'
);

DELETE FROM audit_logs
WHERE user_id IN (
    SELECT id
    FROM users
    WHERE username = 'auth_test'
);

DELETE FROM users
WHERE username = 'auth_test';

DELETE FROM people
WHERE preferred_name = 'Auth Test';

DELETE FROM congregations
WHERE name = 'Congregação Teste Auth';

INSERT INTO congregations (
    name,
    status
)
VALUES (
    'Congregação Teste Auth',
    'A'
);

SET @congregation_id = LAST_INSERT_ID();

INSERT INTO people (
    congregation_id,
    role,
    gender,
    full_name,
    preferred_name,
    birth_date,
    email,
    whatsapp,
    status
)
VALUES (
    @congregation_id,
    'LAMB',
    'MALE',
    'Usuário Teste Autenticação',
    'Auth Test',
    '2000-01-01',
    'auth.test@lambkin.local',
    '5511999999999',
    'A'
);

SET @person_id = LAST_INSERT_ID();

INSERT INTO users (
    person_id,
    verification_person_id,
    username,
    password_hash,
    is_system_admin,
    email_verified_at,
    whatsapp_verified_at,
    status
)
VALUES (
    @person_id,
    NULL,
    'auth_test',
    '$HASH',
    FALSE,
    NULL,
    NULL,
    'A'
);

SQL

echo "✅ Usuário de teste criado"
echo

# ------------------------------------------------------------
# TESTE 1 - DTO inválido
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":123}')

check_status 400 "$STATUS" "1. DTO inválido é recusado"

# ------------------------------------------------------------
# TESTE 2 - Login antes da verificação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "password":"Teste123"
  }')

check_status 401 "$STATUS" "2. Conta não verificada não consegue login"

# ------------------------------------------------------------
# TESTE 3 - Gerar código de verificação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/verification/resend" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "channel":"EMAIL"
  }')

check_status 201 "$STATUS" "3. Código de verificação é criado"

VERIFICATION_CODE=$(json_field "$BODY" developmentCode)

echo "   Código de desenvolvimento: $VERIFICATION_CODE"

# ------------------------------------------------------------
# TESTE 4 - Código errado
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/verification/confirm" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "channel":"EMAIL",
    "code":"000000"
  }')

check_status 400 "$STATUS" "4. Código incorreto é recusado"

# ------------------------------------------------------------
# TESTE 5 - Confirmar conta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/verification/confirm" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\":\"auth_test\",
    \"channel\":\"EMAIL\",
    \"code\":\"$VERIFICATION_CODE\"
  }")

check_status 201 "$STATUS" "5. Conta é verificada"

# ------------------------------------------------------------
# TESTE 6 - Senha errada
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "password":"senha_errada"
  }')

check_status 401 "$STATUS" "6. Senha errada é recusada"

# ------------------------------------------------------------
# TESTE 7 - Login correto
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -c "$COOKIE_JAR" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" "7. Login correto funciona"

ACCESS_TOKEN=$(json_field "$BODY" accessToken)

echo "   Access Token gerado"

# ------------------------------------------------------------
# TESTE 8 - /me sem JWT
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/auth/me")

check_status 401 "$STATUS" "8. Rota protegida bloqueia usuário sem token"

# ------------------------------------------------------------
# TESTE 9 - /me com JWT
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/auth/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

check_status 200 "$STATUS" "9. JWT válido acessa rota protegida"

# ------------------------------------------------------------
# TESTE 10 - Guardar refresh token antigo
# ------------------------------------------------------------

cp "$COOKIE_JAR" "$OLD_COOKIE_JAR"

# ------------------------------------------------------------
# TESTE 10 - Refresh
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -b "$COOKIE_JAR" \
  -c "$COOKIE_JAR" \
  -X POST \
  "$API/auth/refresh")

check_status 201 "$STATUS" "10. Refresh token gera novo access token"

NEW_ACCESS_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# TESTE 11 - Refresh antigo não funciona
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -b "$OLD_COOKIE_JAR" \
  -X POST \
  "$API/auth/refresh")

check_status 401 "$STATUS" "11. Refresh token antigo é invalidado"

# ------------------------------------------------------------
# TESTE 12 - Logout
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -b "$COOKIE_JAR" \
  -c "$COOKIE_JAR" \
  -X POST \
  "$API/auth/logout" \
  -H "Authorization: Bearer $NEW_ACCESS_TOKEN")

check_status 201 "$STATUS" "12. Logout funciona"

# ------------------------------------------------------------
# TESTE 13 - JWT depois do logout
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/auth/me" \
  -H "Authorization: Bearer $NEW_ACCESS_TOKEN")

check_status 401 "$STATUS" "13. Sessão encerrada invalida acesso"

# ------------------------------------------------------------
# TESTE 14 - Solicitar recuperação de senha
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/password/forgot" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "channel":"EMAIL"
  }')

check_status 201 "$STATUS" "14. Recuperação de senha gera código"

PASSWORD_CODE=$(json_field "$BODY" developmentCode)

echo "   Código de recuperação: $PASSWORD_CODE"

# ------------------------------------------------------------
# TESTE 15 - Redefinir senha
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/password/reset" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\":\"auth_test\",
    \"code\":\"$PASSWORD_CODE\",
    \"newPassword\":\"$NEW_PASSWORD\"
  }")

check_status 201 "$STATUS" "15. Senha é redefinida"

# ------------------------------------------------------------
# TESTE 16 - Senha antiga
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "password":"Teste123"
  }')

check_status 401 "$STATUS" "16. Senha antiga deixa de funcionar"

# ------------------------------------------------------------
# TESTE 17 - Nova senha
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -c "$COOKIE_JAR" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"auth_test",
    "password":"NovaSenha123"
  }')

check_status 201 "$STATUS" "17. Nova senha funciona"

FINAL_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# TESTE 18 - /me após nova senha
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/auth/me" \
  -H "Authorization: Bearer $FINAL_TOKEN")

check_status 200 "$STATUS" "18. Nova sessão autenticada funciona"

echo
echo "========================================"
echo " ✅ TODOS OS TESTES DE AUTH PASSARAM"
echo "========================================"
echo

#!/usr/bin/env bash

set -e

API="http://localhost:3000"

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"

BODY="$(mktemp)"

trap '
  rm -f "$BODY"
' EXIT

cd "$ROOT_DIR"

set -a
source .env
set +a

echo
echo "========================================"
echo " LAMBKIN - TESTE ADMIN / AUDITORIA"
echo "========================================"
echo

TEST_NUMBER=0

next_test() {
  TEST_NUMBER=$((TEST_NUMBER + 1))
}

check_status() {
  EXPECTED="$1"
  ACTUAL="$2"
  NAME="$3"

  next_test

  if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✅ $TEST_NUMBER. $NAME"
  else
    echo "❌ $TEST_NUMBER. $NAME"
    echo "Esperado: HTTP $EXPECTED"
    echo "Recebido: HTTP $ACTUAL"
    echo
    cat "$BODY"
    echo
    exit 1
  fi
}

check_value() {
  EXPECTED="$1"
  ACTUAL="$2"
  NAME="$3"

  next_test

  if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✅ $TEST_NUMBER. $NAME"
  else
    echo "❌ $TEST_NUMBER. $NAME"
    echo "Esperado: $EXPECTED"
    echo "Recebido: $ACTUAL"
    exit 1
  fi
}

json_path() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    value = json.load(file)

for part in sys.argv[2].split("."):
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value[part]

if value is None:
    print("null")
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

json_has_key_recursive() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    data = json.load(file)

target = sys.argv[2]

def has_key(value):
    if isinstance(value, dict):
        if target in value:
            return True

        return any(
            has_key(item)
            for item in value.values()
        )

    if isinstance(value, list):
        return any(
            has_key(item)
            for item in value
        )

    return False

print(
    "true"
    if has_key(data)
    else "false"
)
PY
}

request() {
  METHOD="$1"
  PATH_VALUE="$2"
  TOKEN="${3:-}"
  DATA="${4:-}"

  ARGS=(
    -s
    -o "$BODY"
    -w "%{http_code}"
    -X "$METHOD"
    "$API$PATH_VALUE"
  )

  if [ -n "$TOKEN" ]; then
    ARGS+=(
      -H "Authorization: Bearer $TOKEN"
    )
  fi

  if [ -n "$DATA" ]; then
    ARGS+=(
      -H "Content-Type: application/json"
      -d "$DATA"
    )
  fi

  curl "${ARGS[@]}"
}

mysql_exec() {
  docker exec \
    -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
    lambkin-db \
    mysql \
    -uroot \
    lambkin_db \
    -N \
    -B \
    -e "$1"
}

echo "Preparando banco de teste..."

PASSWORD="Teste123"

HASH="$(
  cd "$ROOT_DIR/apps/api"

  node -e "
    const argon2 = require('argon2');

    argon2.hash(
      '$PASSWORD',
      { type: argon2.argon2id }
    )
    .then(console.log)
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
  "
)"

# ------------------------------------------------------------
# Limpeza anterior
# ------------------------------------------------------------

mysql_exec "
SET @cid = (
  SELECT id
  FROM congregations
  WHERE name =
    'Congregação Teste Admin Audit'
  LIMIT 1
);

DELETE FROM audit_logs
WHERE entity_type =
  'admin-audit-test';

DELETE FROM audit_logs
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id =
    @cid
);

DELETE FROM user_tokens
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id =
    @cid
);

DELETE FROM user_sessions
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id =
    @cid
);

DELETE FROM users
WHERE person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id =
    @cid
);

DELETE FROM people
WHERE congregation_id =
  @cid;

DELETE FROM congregations
WHERE id =
  @cid;
"

# ------------------------------------------------------------
# Congregação
# ------------------------------------------------------------

mysql_exec "
INSERT INTO congregations (
  name,
  status
)
VALUES (
  'Congregação Teste Admin Audit',
  'A'
);
"

CID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name =
      'Congregação Teste Admin Audit';
  "
)"

# ------------------------------------------------------------
# Usuários
# ------------------------------------------------------------

create_user() {
  ROLE="$1"
  NAME="$2"
  USERNAME="$3"
  EMAIL="$4"
  ADMIN="$5"

  mysql_exec "
  INSERT INTO people (
    congregation_id,
    role,
    gender,
    full_name,
    preferred_name,
    birth_date,
    email,
    status
  )
  VALUES (
    $CID,
    '$ROLE',
    'MALE',
    '$NAME',
    '$NAME',
    '1990-01-01',
    '$EMAIL',
    'A'
  );

  SET @pid = LAST_INSERT_ID();

  INSERT INTO users (
    person_id,
    username,
    password_hash,
    is_system_admin,
    email_verified_at,
    status
  )
  VALUES (
    @pid,
    '$USERNAME',
    '$HASH',
    $ADMIN,
    NOW(3),
    'A'
  );
  "
}

create_user \
  "MINISTRY" \
  "Admin Audit Test" \
  "admin_audit_test" \
  "admin.audit@lambkin.local" \
  "TRUE"

create_user \
  "LAMB" \
  "User Audit Test" \
  "user_audit_test" \
  "user.audit@lambkin.local" \
  "FALSE"

ADMIN_USER_ID="$(
  mysql_exec "
    SELECT id
    FROM users
    WHERE username =
      'admin_audit_test';
  "
)"

USER_ID="$(
  mysql_exec "
    SELECT id
    FROM users
    WHERE username =
      'user_audit_test';
  "
)"

# ------------------------------------------------------------
# Logs controlados
# ------------------------------------------------------------

mysql_exec "
INSERT INTO audit_logs (
  user_id,
  action,
  entity_type,
  entity_id,
  metadata,
  ip_address,
  created_at
)
VALUES
(
  $ADMIN_USER_ID,
  'TEST_CREATE',
  'admin-audit-test',
  1001,
  JSON_OBJECT(
    'name',
    'Primeiro'
  ),
  '127.0.0.1',
  '2026-09-01 10:00:00'
),
(
  $ADMIN_USER_ID,
  'TEST_UPDATE',
  'admin-audit-test',
  1001,
  JSON_OBJECT(
    'name',
    'Segundo'
  ),
  '127.0.0.1',
  '2026-09-01 11:00:00'
),
(
  $USER_ID,
  'TEST_CREATE',
  'admin-audit-test',
  2002,
  JSON_OBJECT(
    'name',
    'Terceiro'
  ),
  '192.168.0.10',
  '2026-09-01 12:00:00'
);
"

LOG_ID="$(
  mysql_exec "
    SELECT id
    FROM audit_logs
    WHERE entity_type =
      'admin-audit-test'
    ORDER BY id
    LIMIT 1;
  "
)"

echo "✅ Banco preparado"
echo

# ------------------------------------------------------------
# Login
# ------------------------------------------------------------

login_user() {
  USERNAME="$1"
  NAME="$2"
  VARIABLE="$3"

  STATUS="$(
    request \
      POST \
      "/auth/login" \
      "" \
      "{
        \"username\":\"$USERNAME\",
        \"password\":\"$PASSWORD\"
      }"
  )"

  check_status \
    201 \
    "$STATUS" \
    "$NAME"

  TOKEN="$(
    json_path \
      "$BODY" \
      "accessToken"
  )"

  printf -v \
    "$VARIABLE" \
    '%s' \
    "$TOKEN"
}

login_user \
  "admin_audit_test" \
  "System Admin autentica" \
  "ADMIN_TOKEN"

login_user \
  "user_audit_test" \
  "Usuário comum autentica" \
  "USER_TOKEN"

# ------------------------------------------------------------
# Segurança
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs"
)"

check_status \
  401 \
  "$STATUS" \
  "Auditoria exige autenticação"

STATUS="$(
  request \
    GET \
    "/admin/audit-logs" \
    "$USER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Usuário comum não acessa auditoria"

# ------------------------------------------------------------
# Consulta Admin
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?entityType=admin-audit-test" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin consulta auditoria"

TOTAL="$(
  json_path \
    "$BODY" \
    "total"
)"

check_value \
  "3" \
  "$TOTAL" \
  "Consulta retorna os três logs de teste"

ITEM_COUNT="$(
  python3 - "$BODY" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    data = json.load(file)

print(len(data["items"]))
PY
)"

check_value \
  "3" \
  "$ITEM_COUNT" \
  "Lista possui três itens"

FIRST_ACTION="$(
  json_path \
    "$BODY" \
    "items.0.action"
)"

check_value \
  "TEST_CREATE" \
  "$FIRST_ACTION" \
  "Logs são ordenados do mais recente para o mais antigo"

FIRST_ENTITY_ID="$(
  json_path \
    "$BODY" \
    "items.0.entity_id"
)"

check_value \
  "2002" \
  "$FIRST_ENTITY_ID" \
  "Log mais recente aparece primeiro"

HAS_PASSWORD="$(
  json_has_key_recursive \
    "$BODY" \
    "password_hash"
)"

check_value \
  "false" \
  "$HAS_PASSWORD" \
  "Auditoria não expõe password_hash"

# ------------------------------------------------------------
# Filtro por action
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?entityType=admin-audit-test&action=TEST_UPDATE" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Filtro por action funciona"

TOTAL="$(
  json_path "$BODY" "total"
)"

check_value \
  "1" \
  "$TOTAL" \
  "Filtro por action retorna um log"

ACTION="$(
  json_path \
    "$BODY" \
    "items.0.action"
)"

check_value \
  "TEST_UPDATE" \
  "$ACTION" \
  "Filtro retorna a action correta"

# ------------------------------------------------------------
# Filtro por entityId
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?entityType=admin-audit-test&entityId=1001" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Filtro por entityId funciona"

TOTAL="$(
  json_path "$BODY" "total"
)"

check_value \
  "2" \
  "$TOTAL" \
  "entityId 1001 possui dois logs"

# ------------------------------------------------------------
# Filtro por userId
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?entityType=admin-audit-test&userId=$USER_ID" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Filtro por userId funciona"

TOTAL="$(
  json_path "$BODY" "total"
)"

check_value \
  "1" \
  "$TOTAL" \
  "Filtro por usuário retorna somente seus logs"

# ------------------------------------------------------------
# Datas
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?entityType=admin-audit-test&from=2026-09-01T10:30:00.000Z&to=2026-09-01T11:30:00.000Z" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Filtro por período funciona"

TOTAL="$(
  json_path "$BODY" "total"
)"

check_value \
  "1" \
  "$TOTAL" \
  "Período retorna somente o log esperado"

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?from=2026-09-02T00:00:00.000Z&to=2026-09-01T00:00:00.000Z" \
    "$ADMIN_TOKEN"
)"

check_status \
  400 \
  "$STATUS" \
  "Data inicial maior que final é bloqueada"

# ------------------------------------------------------------
# Paginação
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?entityType=admin-audit-test&page=1&limit=2" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Paginação funciona"

LIMIT="$(
  json_path "$BODY" "limit"
)"

check_value \
  "2" \
  "$LIMIT" \
  "Limit solicitado é aplicado"

TOTAL_PAGES="$(
  json_path \
    "$BODY" \
    "totalPages"
)"

check_value \
  "2" \
  "$TOTAL_PAGES" \
  "Total de páginas é calculado corretamente"

PAGE_ITEMS="$(
  python3 - "$BODY" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    data = json.load(file)

print(len(data["items"]))
PY
)"

check_value \
  "2" \
  "$PAGE_ITEMS" \
  "Primeira página contém dois itens"

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?limit=101" \
    "$ADMIN_TOKEN"
)"

check_status \
  400 \
  "$STATUS" \
  "Limit acima de 100 é bloqueado"

STATUS="$(
  request \
    GET \
    "/admin/audit-logs?page=0" \
    "$ADMIN_TOKEN"
)"

check_status \
  400 \
  "$STATUS" \
  "Página zero é bloqueada"

# ------------------------------------------------------------
# Detalhe
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/admin/audit-logs/$LOG_ID" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin consulta detalhe do log"

DETAIL_ID="$(
  json_path "$BODY" "id"
)"

check_value \
  "$LOG_ID" \
  "$DETAIL_ID" \
  "Detalhe retorna o log correto"

STATUS="$(
  request \
    GET \
    "/admin/audit-logs/$LOG_ID" \
    "$USER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Usuário comum não consulta detalhe"

STATUS="$(
  request \
    GET \
    "/admin/audit-logs/999999999" \
    "$ADMIN_TOKEN"
)"

check_status \
  404 \
  "$STATUS" \
  "Log inexistente retorna 404"

# ------------------------------------------------------------
# Append-only
# ------------------------------------------------------------

STATUS="$(
  request \
    DELETE \
    "/admin/audit-logs/$LOG_ID" \
    "$ADMIN_TOKEN"
)"

check_status \
  404 \
  "$STATUS" \
  "API não permite excluir log de auditoria"

STATUS="$(
  request \
    PATCH \
    "/admin/audit-logs/$LOG_ID" \
    "$ADMIN_TOKEN" \
    '{
      "action":"ALTERADO"
    }'
)"

check_status \
  404 \
  "$STATUS" \
  "API não permite alterar log de auditoria"

echo
echo "========================================"
echo " ✅ TODOS OS $TEST_NUMBER TESTES ADMIN/AUDITORIA PASSARAM"
echo "========================================"
echo

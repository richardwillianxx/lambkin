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
echo " LAMBKIN - TESTE RECITATIVOS"
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

json_array_length() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    print(len(json.load(file)))
PY
}

json_array_contains_id() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    data = json.load(file)

target = int(sys.argv[2])

print(
    "true"
    if any(
        item.get("id") == target
        for item in data
    )
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

mysql_exec "
SET @cid1 = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Recitativos'
  LIMIT 1
);

SET @cid2 = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Recitativos Outra'
  LIMIT 1
);

SET @cid3 = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Recitativos Inativa'
  LIMIT 1
);

DELETE FROM recitatives
WHERE congregation_id IN (
  @cid1,
  @cid2,
  @cid3
);

DELETE FROM user_tokens
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid1,
    @cid2,
    @cid3
  )
);

DELETE FROM user_sessions
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid1,
    @cid2,
    @cid3
  )
);

DELETE FROM audit_logs
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid1,
    @cid2,
    @cid3
  )
);

DELETE FROM users
WHERE person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id IN (
    @cid1,
    @cid2,
    @cid3
  )
);

DELETE FROM people
WHERE congregation_id IN (
  @cid1,
  @cid2,
  @cid3
);

DELETE FROM congregations
WHERE id IN (
  @cid1,
  @cid2,
  @cid3
);
"

mysql_exec "
INSERT INTO congregations (
  name,
  status
)
VALUES
(
  'Congregação Teste Recitativos',
  'A'
),
(
  'Congregação Teste Recitativos Outra',
  'A'
),
(
  'Congregação Teste Recitativos Inativa',
  'I'
);
"

CID1="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name =
      'Congregação Teste Recitativos';
  "
)"

CID2="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name =
      'Congregação Teste Recitativos Outra';
  "
)"

CID3="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name =
      'Congregação Teste Recitativos Inativa';
  "
)"

create_user() {
  CID="$1"
  ROLE="$2"
  NAME="$3"
  USERNAME="$4"
  EMAIL="$5"
  ADMIN="$6"

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
  "$CID1" \
  "MINISTRY" \
  "Admin Recitative" \
  "admin_recitative_test" \
  "admin.recitative@lambkin.local" \
  "TRUE"

create_user \
  "$CID1" \
  "ASSISTANT" \
  "Assistant Recitative" \
  "assistant_recitative_test" \
  "assistant.recitative@lambkin.local" \
  "FALSE"

create_user \
  "$CID1" \
  "ASSISTANT" \
  "Second Assistant Recitative" \
  "assistant2_recitative_test" \
  "assistant2.recitative@lambkin.local" \
  "FALSE"

create_user \
  "$CID1" \
  "LAMB" \
  "Lamb Recitative" \
  "lamb_recitative_test" \
  "lamb.recitative@lambkin.local" \
  "FALSE"

create_user \
  "$CID1" \
  "MINISTRY" \
  "Ministry Recitative" \
  "ministry_recitative_test" \
  "ministry.recitative@lambkin.local" \
  "FALSE"

create_user \
  "$CID2" \
  "ASSISTANT" \
  "Other Assistant Recitative" \
  "other_assistant_recitative_test" \
  "other.assistant.recitative@lambkin.local" \
  "FALSE"

create_user \
  "$CID3" \
  "ASSISTANT" \
  "Inactive Assistant Recitative" \
  "inactive_assistant_recitative_test" \
  "inactive.assistant.recitative@lambkin.local" \
  "FALSE"

echo "✅ Banco preparado"
echo

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
  "admin_recitative_test" \
  "Administrador autentica" \
  "ADMIN_TOKEN"

login_user \
  "assistant_recitative_test" \
  "Assistant autentica" \
  "ASSISTANT_TOKEN"

login_user \
  "assistant2_recitative_test" \
  "Segundo Assistant autentica" \
  "ASSISTANT2_TOKEN"

login_user \
  "lamb_recitative_test" \
  "Lamb autentica" \
  "LAMB_TOKEN"

login_user \
  "ministry_recitative_test" \
  "Ministry autentica" \
  "MINISTRY_TOKEN"

login_user \
  "other_assistant_recitative_test" \
  "Assistant de outra congregação autentica" \
  "OTHER_TOKEN"

login_user \
  "inactive_assistant_recitative_test" \
  "Assistant de congregação inativa autentica" \
  "INACTIVE_TOKEN"

STATUS="$(
  request \
    GET \
    "/recitatives"
)"

check_status \
  401 \
  "$STATUS" \
  "/recitatives exige autenticação"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$LAMB_TOKEN" \
    '{
      "name":"Proibido",
      "groupNumber":"FIRST",
      "bibleBook":"João",
      "bibleChapter":3,
      "bibleVerse":"16",
      "gender":"MALE",
      "recitativeDate":"2026-09-20"
    }'
)"

check_status \
  403 \
  "$STATUS" \
  "Lamb não pode cadastrar recitativo"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$MINISTRY_TOKEN" \
    '{
      "name":"Proibido Ministry",
      "groupNumber":"FIRST",
      "bibleBook":"João",
      "bibleChapter":3,
      "bibleVerse":"16",
      "gender":"MALE",
      "recitativeDate":"2026-09-20"
    }'
)"

check_status \
  403 \
  "$STATUS" \
  "Ministry não cadastra recitativo"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$ASSISTANT_TOKEN" \
    "{
      \"name\":\"Recitativo Principal\",
      \"groupNumber\":\"FIRST\",
      \"bibleBook\":\"João\",
      \"bibleChapter\":3,
      \"bibleVerse\":\"16\",
      \"gender\":\"MALE\",
      \"recitativeDate\":\"2026-09-20\",
      \"afterText\":\"Após o cântico\",
      \"recitersCount\":5
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Assistant cadastra recitativo"

RECITATIVE_ID="$(
  json_path "$BODY" "id"
)"

CREATED_CID="$(
  json_path \
    "$BODY" \
    "congregation_id"
)"

check_value \
  "$CID1" \
  "$CREATED_CID" \
  "Assistant grava na própria congregação"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$ASSISTANT_TOKEN" \
    "{
      \"name\":\"Outra congregação\",
      \"groupNumber\":\"FIRST\",
      \"bibleBook\":\"João\",
      \"bibleChapter\":3,
      \"bibleVerse\":\"16\",
      \"gender\":\"MALE\",
      \"congregationId\":$CID2,
      \"recitativeDate\":\"2026-09-20\"
    }"
)"

check_status \
  403 \
  "$STATUS" \
  "Assistant não cadastra para outra congregação"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$INACTIVE_TOKEN" \
    '{
      "name":"Congregação inativa",
      "groupNumber":"FIRST",
      "bibleBook":"João",
      "bibleChapter":3,
      "bibleVerse":"16",
      "gender":"MALE",
      "recitativeDate":"2026-09-20"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Congregação inativa é bloqueada"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$ADMIN_TOKEN" \
    "{
      \"name\":\"Recitativo Outra Congregação\",
      \"groupNumber\":\"SECOND\",
      \"bibleBook\":\"Salmos\",
      \"bibleChapter\":23,
      \"bibleVerse\":\"1\",
      \"gender\":\"FEMALE\",
      \"congregationId\":$CID2,
      \"recitativeDate\":\"2026-09-21\"
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "System Admin cadastra para outra congregação"

OTHER_RECITATIVE_ID="$(
  json_path "$BODY" "id"
)"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$ASSISTANT_TOKEN" \
    '{
      "name":"Data inválida",
      "groupNumber":"FIRST",
      "bibleBook":"João",
      "bibleChapter":3,
      "bibleVerse":"16",
      "gender":"MALE",
      "recitativeDate":"2026-02-31"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Data inexistente é bloqueada"

STATUS="$(
  request \
    POST \
    "/recitatives" \
    "$ASSISTANT_TOKEN" \
    '{
      "name":"Enum inválido",
      "groupNumber":"FIFTH",
      "bibleBook":"João",
      "bibleChapter":3,
      "bibleVerse":"16",
      "gender":"MALE",
      "recitativeDate":"2026-09-20"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Grupo inválido é bloqueado"

STATUS="$(
  request \
    GET \
    "/recitatives/$RECITATIVE_ID" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Usuário da congregação consulta recitativo"

STATUS="$(
  request \
    GET \
    "/recitatives/$RECITATIVE_ID" \
    "$OTHER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Outra congregação não consulta recitativo"

STATUS="$(
  request \
    GET \
    "/recitatives" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Usuário consulta lista da própria congregação"

COUNT="$(
  json_array_length "$BODY"
)"

check_value \
  "1" \
  "$COUNT" \
  "Lista comum não mistura congregações"

HAS_MAIN="$(
  json_array_contains_id \
    "$BODY" \
    "$RECITATIVE_ID"
)"

check_value \
  "true" \
  "$HAS_MAIN" \
  "Lista contém recitativo da própria congregação"

HAS_OTHER="$(
  json_array_contains_id \
    "$BODY" \
    "$OTHER_RECITATIVE_ID"
)"

check_value \
  "false" \
  "$HAS_OTHER" \
  "Lista não contém recitativo de outra congregação"

STATUS="$(
  request \
    GET \
    "/recitatives" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin consulta todas as congregações"

COUNT="$(
  json_array_length "$BODY"
)"

check_value \
  "2" \
  "$COUNT" \
  "Admin recebe recitativos das duas congregações"

STATUS="$(
  request \
    PATCH \
    "/recitatives/$RECITATIVE_ID" \
    "$ASSISTANT2_TOKEN" \
    '{
      "name":"Alteração indevida"
    }'
)"

check_status \
  403 \
  "$STATUS" \
  "Outro Assistant não altera recitativo alheio"

STATUS="$(
  request \
    PATCH \
    "/recitatives/$RECITATIVE_ID" \
    "$ASSISTANT_TOKEN" \
    '{
      "name":"Recitativo Editado",
      "groupNumber":"THIRD",
      "afterText":null,
      "recitersCount":null
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "Criador altera o próprio recitativo"

NAME="$(
  json_path \
    "$BODY" \
    "name"
)"

check_value \
  "Recitativo Editado" \
  "$NAME" \
  "Nome é atualizado"

AFTER="$(
  json_path \
    "$BODY" \
    "after_text"
)"

check_value \
  "null" \
  "$AFTER" \
  "afterText pode ser limpo"

COUNT_VALUE="$(
  json_path \
    "$BODY" \
    "reciters_count"
)"

check_value \
  "null" \
  "$COUNT_VALUE" \
  "recitersCount pode ser limpo"

STATUS="$(
  request \
    PATCH \
    "/recitatives/$RECITATIVE_ID" \
    "$ADMIN_TOKEN" \
    '{
      "bibleVerse":"16-17"
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin pode alterar recitativo"

STATUS="$(
  request \
    DELETE \
    "/recitatives/$RECITATIVE_ID" \
    "$ASSISTANT2_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Outro usuário não remove recitativo"

STATUS="$(
  request \
    DELETE \
    "/recitatives/$RECITATIVE_ID" \
    "$ASSISTANT_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Criador remove o próprio recitativo"

DB_STATUS="$(
  mysql_exec "
    SELECT status
    FROM recitatives
    WHERE id =
      $RECITATIVE_ID;
  "
)"

check_value \
  "I" \
  "$DB_STATUS" \
  "Remoção utiliza soft delete"

STATUS="$(
  request \
    GET \
    "/recitatives/$RECITATIVE_ID" \
    "$ASSISTANT_TOKEN"
)"

check_status \
  404 \
  "$STATUS" \
  "Recitativo inativo não pode ser consultado"

echo
echo "========================================"
echo " ✅ TODOS OS $TEST_NUMBER TESTES RECITATIVOS PASSARAM"
echo "========================================"
echo

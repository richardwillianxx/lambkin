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
echo " LAMBKIN - TESTE QUIZZES / RANKING"
echo "========================================"
echo

# ------------------------------------------------------------
# Controle dos testes
# ------------------------------------------------------------

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
    echo
    exit 1
  fi
}

# ------------------------------------------------------------
# JSON
# ------------------------------------------------------------

json_path() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

file_path = sys.argv[1]
path = sys.argv[2]

with open(file_path) as file:
    value = json.load(file)

for part in path.split("."):
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
    data = json.load(file)

print(len(data))
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

json_array_contains_id() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    data = json.load(file)

target = int(sys.argv[2])

found = any(
    item.get("id") == target
    for item in data
)

print(
    "true"
    if found
    else "false"
)
PY
}

# ------------------------------------------------------------
# HTTP
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# MySQL
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Preparação
# ------------------------------------------------------------

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
# Limpeza de execução anterior
# ------------------------------------------------------------

mysql_exec "
SET @cid_main = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Quiz'
  LIMIT 1
);

SET @cid_other = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Quiz Outra'
  LIMIT 1
);

SET @cid_inactive = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Quiz Inativa'
  LIMIT 1
);

DELETE FROM quiz_answers
WHERE attempt_id IN (
  SELECT id
  FROM quiz_attempts
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
  OR quiz_id IN (
    SELECT q.id
    FROM quizzes q
    INNER JOIN users u
      ON u.id = q.created_by_user_id
    INNER JOIN people p
      ON p.id = u.person_id
    WHERE p.congregation_id IN (
      @cid_main,
      @cid_other,
      @cid_inactive
    )
  )
);

DELETE FROM quiz_attempts
WHERE congregation_id IN (
  @cid_main,
  @cid_other,
  @cid_inactive
)
OR quiz_id IN (
  SELECT q.id
  FROM quizzes q
  INNER JOIN users u
    ON u.id = q.created_by_user_id
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM quiz_options
WHERE question_id IN (
  SELECT qq.id
  FROM quiz_questions qq
  INNER JOIN quizzes q
    ON q.id = qq.quiz_id
  INNER JOIN users u
    ON u.id = q.created_by_user_id
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM quiz_questions
WHERE quiz_id IN (
  SELECT q.id
  FROM quizzes q
  INNER JOIN users u
    ON u.id = q.created_by_user_id
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM quizzes
WHERE created_by_user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM user_tokens
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM user_sessions
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM audit_logs
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM users
WHERE person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM people
WHERE congregation_id IN (
  @cid_main,
  @cid_other,
  @cid_inactive
);

DELETE FROM congregations
WHERE id IN (
  @cid_main,
  @cid_other,
  @cid_inactive
);
"

# ------------------------------------------------------------
# Congregações
# ------------------------------------------------------------

mysql_exec "
INSERT INTO congregations (
  name,
  status
)
VALUES
(
  'Congregação Teste Quiz',
  'A'
),
(
  'Congregação Teste Quiz Outra',
  'A'
),
(
  'Congregação Teste Quiz Inativa',
  'I'
);
"

CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste Quiz';
  "
)"

OTHER_CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste Quiz Outra';
  "
)"

INACTIVE_CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste Quiz Inativa';
  "
)"

# ------------------------------------------------------------
# Função para criar usuário
# ------------------------------------------------------------

create_user() {
  CONGREGATION="$1"
  ROLE="$2"
  GENDER="$3"
  FULL_NAME="$4"
  PREFERRED_NAME="$5"
  EMAIL="$6"
  USERNAME="$7"
  ADMIN="$8"

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
    $CONGREGATION,
    '$ROLE',
    '$GENDER',
    '$FULL_NAME',
    '$PREFERRED_NAME',
    '1990-01-01',
    '$EMAIL',
    'A'
  );

  SET @person_id = LAST_INSERT_ID();

  INSERT INTO users (
    person_id,
    username,
    password_hash,
    is_system_admin,
    email_verified_at,
    status
  )
  VALUES (
    @person_id,
    '$USERNAME',
    '$HASH',
    $ADMIN,
    NOW(3),
    'A'
  );
  "
}

# ------------------------------------------------------------
# Usuários
# ------------------------------------------------------------

create_user \
  "$CONGREGATION_ID" \
  "MINISTRY" \
  "MALE" \
  "Administrador Teste Quiz" \
  "Admin Quiz Test" \
  "admin.quiz@lambkin.local" \
  "admin_quiz_test" \
  "TRUE"

create_user \
  "$CONGREGATION_ID" \
  "MINISTRY" \
  "MALE" \
  "Ministério Teste Quiz" \
  "Ministry Quiz Test" \
  "ministry.quiz@lambkin.local" \
  "ministry_quiz_test" \
  "FALSE"

create_user \
  "$CONGREGATION_ID" \
  "ASSISTANT" \
  "FEMALE" \
  "Auxiliar Teste Quiz" \
  "Assistant Quiz Test" \
  "assistant.quiz@lambkin.local" \
  "assistant_quiz_test" \
  "FALSE"

create_user \
  "$CONGREGATION_ID" \
  "LAMB" \
  "MALE" \
  "Cordeiro Teste Quiz" \
  "Lamb Quiz Test" \
  "lamb.quiz@lambkin.local" \
  "lamb_quiz_test" \
  "FALSE"

create_user \
  "$CONGREGATION_ID" \
  "GUARDIAN" \
  "FEMALE" \
  "Responsável Teste Quiz" \
  "Guardian Quiz Test" \
  "guardian.quiz@lambkin.local" \
  "guardian_quiz_test" \
  "FALSE"

create_user \
  "$OTHER_CONGREGATION_ID" \
  "LAMB" \
  "FEMALE" \
  "Cordeiro Outra Congregação Quiz" \
  "Other Lamb Quiz Test" \
  "other.lamb.quiz@lambkin.local" \
  "other_lamb_quiz_test" \
  "FALSE"

create_user \
  "$INACTIVE_CONGREGATION_ID" \
  "LAMB" \
  "MALE" \
  "Cordeiro Congregação Inativa Quiz" \
  "Inactive Lamb Quiz Test" \
  "inactive.lamb.quiz@lambkin.local" \
  "inactive_lamb_quiz_test" \
  "FALSE"

echo "✅ Banco preparado"
echo

# ------------------------------------------------------------
# IDs
# ------------------------------------------------------------

LAMB_USER_ID="$(
  mysql_exec "
    SELECT id
    FROM users
    WHERE username = 'lamb_quiz_test';
  "
)"

OTHER_LAMB_USER_ID="$(
  mysql_exec "
    SELECT id
    FROM users
    WHERE username = 'other_lamb_quiz_test';
  "
)"

# ------------------------------------------------------------
# Login
# ------------------------------------------------------------



# ------------------------------------------------------------
# Login
# ------------------------------------------------------------

login_user() {
  USERNAME="$1"
  TEST_NAME="$2"
  VARIABLE_NAME="$3"

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
    "$TEST_NAME"

  TOKEN="$(
    json_path \
      "$BODY" \
      "accessToken"
  )"

  printf -v \
    "$VARIABLE_NAME" \
    '%s' \
    "$TOKEN"
}

login_user \
  "admin_quiz_test" \
  "Administrador consegue autenticar" \
  "ADMIN_TOKEN"

login_user \
  "ministry_quiz_test" \
  "Ministry consegue autenticar" \
  "MINISTRY_TOKEN"

login_user \
  "assistant_quiz_test" \
  "Assistant consegue autenticar" \
  "ASSISTANT_TOKEN"

login_user \
  "lamb_quiz_test" \
  "Lamb consegue autenticar" \
  "LAMB_TOKEN"

login_user \
  "guardian_quiz_test" \
  "Guardian consegue autenticar" \
  "GUARDIAN_TOKEN"

login_user \
  "other_lamb_quiz_test" \
  "Usuário de outra congregação consegue autenticar" \
  "OTHER_LAMB_TOKEN"

login_user \
  "inactive_lamb_quiz_test" \
  "Usuário de congregação inativa consegue autenticar" \
  "INACTIVE_LAMB_TOKEN"




# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/quizzes"
)"

check_status \
  401 \
  "$STATUS" \
  "/quizzes exige autenticação"

# ------------------------------------------------------------
# Permissões de criação
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes" \
    "$LAMB_TOKEN" \
    '{
      "title":"Quiz proibido Lamb",
      "maxAttempts":1
    }'
)"

check_status \
  403 \
  "$STATUS" \
  "Lamb não pode criar quiz"

STATUS="$(
  request \
    POST \
    "/quizzes" \
    "$GUARDIAN_TOKEN" \
    '{
      "title":"Quiz proibido Guardian",
      "maxAttempts":1
    }'
)"

check_status \
  403 \
  "$STATUS" \
  "Guardian não pode criar quiz"

# ------------------------------------------------------------
# Quiz principal - Ministry
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes" \
    "$MINISTRY_TOKEN" \
    '{
      "title":"Quiz Principal Teste",
      "description":"Quiz de integração",
      "maxAttempts":2
    }'
)"

check_status \
  201 \
  "$STATUS" \
  "Ministry pode criar quiz"

QUIZ_ID="$(
  json_path "$BODY" "id"
)"

QUIZ_STATE="$(
  json_path "$BODY" "quiz_state"
)"

check_value \
  "DRAFT" \
  "$QUIZ_STATE" \
  "Quiz é criado como DRAFT"

# ------------------------------------------------------------
# DRAFT e visibilidade
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID" \
    "$ASSISTANT_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Outro usuário não consulta DRAFT alheio"

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin consulta DRAFT alheio"

HAS_PASSWORD="$(
  json_has_key_recursive \
    "$BODY" \
    "password_hash"
)"

check_value \
  "false" \
  "$HAS_PASSWORD" \
  "Consulta do quiz não expõe password_hash"

STATUS="$(
  request \
    GET \
    "/quizzes" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Usuário comum consegue listar quizzes"

CONTAINS_DRAFT="$(
  json_array_contains_id \
    "$BODY" \
    "$QUIZ_ID"
)"

check_value \
  "false" \
  "$CONTAINS_DRAFT" \
  "DRAFT alheio não aparece para usuário comum"

STATUS="$(
  request \
    GET \
    "/quizzes" \
    "$MINISTRY_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Criador consegue listar seus quizzes"

CONTAINS_DRAFT="$(
  json_array_contains_id \
    "$BODY" \
    "$QUIZ_ID"
)"

check_value \
  "true" \
  "$CONTAINS_DRAFT" \
  "Criador visualiza o próprio DRAFT"

# ------------------------------------------------------------
# Assistant pode criar
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes" \
    "$ASSISTANT_TOKEN" \
    '{
      "title":"Quiz Assistant Teste",
      "description":"Será usado para testes de DRAFT",
      "maxAttempts":1
    }'
)"

check_status \
  201 \
  "$STATUS" \
  "Assistant pode criar quiz"

ASSISTANT_QUIZ_ID="$(
  json_path "$BODY" "id"
)"

# ------------------------------------------------------------
# Admin pode criar
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes" \
    "$ADMIN_TOKEN" \
    '{
      "title":"Quiz Admin Sem Estrutura",
      "maxAttempts":1
    }'
)"

check_status \
  201 \
  "$STATUS" \
  "System Admin pode criar quiz"

ADMIN_QUIZ_ID="$(
  json_path "$BODY" "id"
)"

# ------------------------------------------------------------
# DTO maxAttempts
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes" \
    "$MINISTRY_TOKEN" \
    '{
      "title":"Quiz Inválido",
      "maxAttempts":0
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "maxAttempts menor que 1 é bloqueado"

# ------------------------------------------------------------
# Permissão de edição
# ------------------------------------------------------------

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID" \
    "$ASSISTANT_TOKEN" \
    '{
      "title":"Alteração indevida"
    }'
)"

check_status \
  403 \
  "$STATUS" \
  "Outro usuário não edita DRAFT alheio"

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID" \
    "$ADMIN_TOKEN" \
    '{
      "title":"Quiz Principal Editado pelo Admin"
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin pode editar DRAFT alheio"

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID" \
    "$MINISTRY_TOKEN" \
    '{
      "title":"Quiz Principal Teste",
      "description":null
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "Criador pode editar o próprio DRAFT"

DESCRIPTION="$(
  json_path "$BODY" "description"
)"

check_value \
  "null" \
  "$DESCRIPTION" \
  "Descrição pode ser limpa com null"

# ------------------------------------------------------------
# Validações de estrutura
# ------------------------------------------------------------

STATUS="$(
  request \
    PUT \
    "/quizzes/$QUIZ_ID/structure" \
    "$MINISTRY_TOKEN" \
    '{
      "questions":[
        {
          "questionText":"Pergunta inválida",
          "points":10,
          "position":1,
          "options":[
            {
              "optionText":"Única opção",
              "isCorrect":true,
              "position":1
            }
          ]
        }
      ]
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Pergunta com menos de duas alternativas é bloqueada"

STATUS="$(
  request \
    PUT \
    "/quizzes/$QUIZ_ID/structure" \
    "$MINISTRY_TOKEN" \
    '{
      "questions":[
        {
          "questionText":"Duas corretas",
          "points":10,
          "position":1,
          "options":[
            {
              "optionText":"A",
              "isCorrect":true,
              "position":1
            },
            {
              "optionText":"B",
              "isCorrect":true,
              "position":2
            }
          ]
        }
      ]
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Pergunta com mais de uma alternativa correta é bloqueada"

STATUS="$(
  request \
    PUT \
    "/quizzes/$QUIZ_ID/structure" \
    "$MINISTRY_TOKEN" \
    '{
      "questions":[
        {
          "questionText":"Pergunta 1",
          "points":10,
          "position":1,
          "options":[
            {
              "optionText":"A",
              "isCorrect":true,
              "position":1
            },
            {
              "optionText":"B",
              "isCorrect":false,
              "position":2
            }
          ]
        },
        {
          "questionText":"Pergunta 2",
          "points":10,
          "position":1,
          "options":[
            {
              "optionText":"A",
              "isCorrect":true,
              "position":1
            },
            {
              "optionText":"B",
              "isCorrect":false,
              "position":2
            }
          ]
        }
      ]
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Posições duplicadas de perguntas são bloqueadas"

# ------------------------------------------------------------
# Estrutura inicial válida
# ------------------------------------------------------------

STATUS="$(
  request \
    PUT \
    "/quizzes/$QUIZ_ID/structure" \
    "$MINISTRY_TOKEN" \
    '{
      "questions":[
        {
          "questionText":"Pergunta Inicial",
          "points":5,
          "position":1,
          "options":[
            {
              "optionText":"Errada",
              "isCorrect":false,
              "position":1
            },
            {
              "optionText":"Correta",
              "isCorrect":true,
              "position":2
            }
          ]
        }
      ]
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "Estrutura válida pode ser gravada em DRAFT"

OLD_QUESTION_ID="$(
  json_path \
    "$BODY" \
    "quiz_questions.0.id"
)"

HAS_IS_CORRECT="$(
  json_has_key_recursive \
    "$BODY" \
    "is_correct"
)"

check_value \
  "true" \
  "$HAS_IS_CORRECT" \
  "Criador visualiza gabarito enquanto o quiz está em DRAFT"

# ------------------------------------------------------------
# Substituição da estrutura
# ------------------------------------------------------------

STATUS="$(
  request \
    PUT \
    "/quizzes/$QUIZ_ID/structure" \
    "$MINISTRY_TOKEN" \
    '{
      "questions":[
        {
          "questionText":"Pergunta 1",
          "points":10,
          "position":1,
          "options":[
            {
              "optionText":"P1 Errada",
              "isCorrect":false,
              "position":1
            },
            {
              "optionText":"P1 Correta",
              "isCorrect":true,
              "position":2
            }
          ]
        },
        {
          "questionText":"Pergunta 2",
          "points":20,
          "position":2,
          "options":[
            {
              "optionText":"P2 Correta",
              "isCorrect":true,
              "position":1
            },
            {
              "optionText":"P2 Errada",
              "isCorrect":false,
              "position":2
            }
          ]
        },
        {
          "questionText":"Pergunta 3",
          "points":30,
          "position":3,
          "options":[
            {
              "optionText":"P3 Errada",
              "isCorrect":false,
              "position":1
            },
            {
              "optionText":"P3 Correta",
              "isCorrect":true,
              "position":2
            }
          ]
        }
      ]
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "Estrutura pode ser substituída enquanto está em DRAFT"

OLD_STATUS="$(
  mysql_exec "
    SELECT status
    FROM quiz_questions
    WHERE id = $OLD_QUESTION_ID;
  "
)"

check_value \
  "I" \
  "$OLD_STATUS" \
  "Pergunta da estrutura anterior é inativada"

ACTIVE_QUESTIONS="$(
  mysql_exec "
    SELECT COUNT(*)
    FROM quiz_questions
    WHERE quiz_id = $QUIZ_ID
      AND status = 'A';
  "
)"

check_value \
  "3" \
  "$ACTIVE_QUESTIONS" \
  "Nova estrutura possui três perguntas ativas"

# ------------------------------------------------------------
# IDs da estrutura final
# ------------------------------------------------------------

Q1_ID="$(
  json_path "$BODY" "quiz_questions.0.id"
)"

Q1_WRONG="$(
  json_path "$BODY" "quiz_questions.0.quiz_options.0.id"
)"

Q1_CORRECT="$(
  json_path "$BODY" "quiz_questions.0.quiz_options.1.id"
)"

Q2_ID="$(
  json_path "$BODY" "quiz_questions.1.id"
)"

Q2_CORRECT="$(
  json_path "$BODY" "quiz_questions.1.quiz_options.0.id"
)"

Q2_WRONG="$(
  json_path "$BODY" "quiz_questions.1.quiz_options.1.id"
)"

Q3_ID="$(
  json_path "$BODY" "quiz_questions.2.id"
)"

Q3_WRONG="$(
  json_path "$BODY" "quiz_questions.2.quiz_options.0.id"
)"

Q3_CORRECT="$(
  json_path "$BODY" "quiz_questions.2.quiz_options.1.id"
)"

# ------------------------------------------------------------
# Ativação sem estrutura
# ------------------------------------------------------------

STATUS="$(
  request \
    PATCH \
    "/quizzes/$ADMIN_QUIZ_ID/state" \
    "$ADMIN_TOKEN" \
    '{
      "quizState":"ACTIVE"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz sem estrutura não pode ser ativado"

# ------------------------------------------------------------
# DRAFT não recebe tentativas
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$ASSISTANT_QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    '{
      "answers":[
        {
          "questionId":1,
          "selectedOptionId":1
        }
      ]
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz em DRAFT não aceita tentativa"

# ------------------------------------------------------------
# DRAFT -> ACTIVE
# ------------------------------------------------------------

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID/state" \
    "$MINISTRY_TOKEN" \
    '{
      "quizState":"ACTIVE"
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "Quiz válido pode passar de DRAFT para ACTIVE"

STATE="$(
  json_path "$BODY" "quiz_state"
)"

check_value \
  "ACTIVE" \
  "$STATE" \
  "Estado do quiz fica ACTIVE"

# ------------------------------------------------------------
# Consulta do participante
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Participante consegue consultar quiz ACTIVE"

HAS_IS_CORRECT="$(
  json_has_key_recursive \
    "$BODY" \
    "is_correct"
)"

check_value \
  "false" \
  "$HAS_IS_CORRECT" \
  "Quiz ACTIVE não expõe is_correct ao participante"

# ------------------------------------------------------------
# Estrutura congelada
# ------------------------------------------------------------

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID" \
    "$MINISTRY_TOKEN" \
    '{
      "title":"Tentativa de alterar ativo"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz ACTIVE não permite editar metadados"

STATUS="$(
  request \
    PUT \
    "/quizzes/$QUIZ_ID/structure" \
    "$MINISTRY_TOKEN" \
    '{
      "questions":[
        {
          "questionText":"Alteração proibida",
          "points":10,
          "position":1,
          "options":[
            {
              "optionText":"A",
              "isCorrect":true,
              "position":1
            },
            {
              "optionText":"B",
              "isCorrect":false,
              "position":2
            }
          ]
        }
      ]
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz ACTIVE não permite alterar estrutura"

STATUS="$(
  request \
    DELETE \
    "/quizzes/$QUIZ_ID" \
    "$MINISTRY_TOKEN"
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz ACTIVE não pode ser removido"

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID/state" \
    "$MINISTRY_TOKEN" \
    '{
      "quizState":"DRAFT"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz ACTIVE não pode voltar para DRAFT"

# ------------------------------------------------------------
# Tentativas inválidas
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Tentativa exige resposta para todas as perguntas"

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Pergunta não pode ser respondida mais de uma vez"

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":999999999,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Pergunta que não pertence ao quiz é bloqueada"

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Alternativa precisa pertencer à pergunta informada"

# ------------------------------------------------------------
# Congregação inativa
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$INACTIVE_LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Usuário de congregação inativa não pode responder"

# ------------------------------------------------------------
# Primeira tentativa - 10 pontos
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_WRONG
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_WRONG
        }
      ]
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Usuário consegue realizar primeira tentativa"

FIRST_ATTEMPT_ID="$(
  json_path "$BODY" "id"
)"

SCORE="$(
  json_path "$BODY" "score"
)"

check_value \
  "10" \
  "$SCORE" \
  "Score da primeira tentativa é calculado pelo backend"

CORRECT="$(
  json_path "$BODY" "correctAnswers"
)"

check_value \
  "1" \
  "$CORRECT" \
  "Quantidade de acertos é calculada pelo backend"

HAS_IS_CORRECT="$(
  json_has_key_recursive \
    "$BODY" \
    "isCorrect"
)"

check_value \
  "false" \
  "$HAS_IS_CORRECT" \
  "Resultado da tentativa não entrega gabarito"

ANSWER_COUNT="$(
  mysql_exec "
    SELECT COUNT(*)
    FROM quiz_answers
    WHERE attempt_id = $FIRST_ATTEMPT_ID
      AND status = 'A';
  "
)"

check_value \
  "3" \
  "$ANSWER_COUNT" \
  "Transaction grava todas as respostas da tentativa"

# ------------------------------------------------------------
# Segunda tentativa - 60 pontos
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Usuário consegue realizar segunda tentativa"

SCORE="$(
  json_path "$BODY" "score"
)"

check_value \
  "60" \
  "$SCORE" \
  "Segunda tentativa soma corretamente os pontos"

CORRECT="$(
  json_path "$BODY" "correctAnswers"
)"

check_value \
  "3" \
  "$CORRECT" \
  "Segunda tentativa registra três acertos"

# ------------------------------------------------------------
# Limite de tentativas
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "maxAttempts bloqueia tentativa excedente"

ATTEMPT_COUNT="$(
  mysql_exec "
    SELECT COUNT(*)
    FROM quiz_attempts
    WHERE quiz_id = $QUIZ_ID
      AND user_id = $LAMB_USER_ID
      AND status = 'A';
  "
)"

check_value \
  "2" \
  "$ATTEMPT_COUNT" \
  "Tentativa excedente não cria registro no banco"

ANSWER_TOTAL="$(
  mysql_exec "
    SELECT COUNT(*)
    FROM quiz_answers qa
    INNER JOIN quiz_attempts a
      ON a.id = qa.attempt_id
    WHERE a.quiz_id = $QUIZ_ID
      AND a.user_id = $LAMB_USER_ID
      AND a.status = 'A'
      AND qa.status = 'A';
  "
)"

check_value \
  "6" \
  "$ANSWER_TOTAL" \
  "Duas tentativas válidas possuem exatamente seis respostas"

# ------------------------------------------------------------
# Minhas tentativas
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID/my-attempts" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Usuário consulta suas tentativas"

MY_ATTEMPTS="$(
  json_array_length "$BODY"
)"

check_value \
  "2" \
  "$MY_ATTEMPTS" \
  "Histórico retorna as duas tentativas do usuário"

# ------------------------------------------------------------
# Outra congregação
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$OTHER_LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_WRONG
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_WRONG
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Usuário de outra congregação consegue responder quiz global"

OTHER_SCORE="$(
  json_path "$BODY" "score"
)"

check_value \
  "30" \
  "$OTHER_SCORE" \
  "Pontuação da outra congregação é calculada corretamente"

# ------------------------------------------------------------
# Ranking geral
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID/ranking" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Ranking geral pode ser consultado"

RANKING_SIZE="$(
  json_array_length "$BODY"
)"

check_value \
  "2" \
  "$RANKING_SIZE" \
  "Ranking utiliza apenas a melhor tentativa de cada usuário"

FIRST_RANK_USER="$(
  json_path "$BODY" "0.user.id"
)"

check_value \
  "$LAMB_USER_ID" \
  "$FIRST_RANK_USER" \
  "Usuário com maior score ocupa a primeira posição"

FIRST_RANK_SCORE="$(
  json_path "$BODY" "0.score"
)"

check_value \
  "60" \
  "$FIRST_RANK_SCORE" \
  "Ranking utiliza a melhor tentativa do usuário"

SECOND_RANK_USER="$(
  json_path "$BODY" "1.user.id"
)"

check_value \
  "$OTHER_LAMB_USER_ID" \
  "$SECOND_RANK_USER" \
  "Segundo usuário aparece corretamente no ranking"

# ------------------------------------------------------------
# Ranking por congregação
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID/ranking?congregationId=$OTHER_CONGREGATION_ID" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Ranking pode ser filtrado por congregação"

FILTER_SIZE="$(
  json_array_length "$BODY"
)"

check_value \
  "1" \
  "$FILTER_SIZE" \
  "Filtro de congregação retorna apenas usuários daquela congregação"

FILTER_USER="$(
  json_path "$BODY" "0.user.id"
)"

check_value \
  "$OTHER_LAMB_USER_ID" \
  "$FILTER_USER" \
  "Ranking filtrado retorna o usuário correto"

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID/ranking?congregationId=abc" \
    "$LAMB_TOKEN"
)"

check_status \
  400 \
  "$STATUS" \
  "congregationId inválido é bloqueado"

# ------------------------------------------------------------
# ACTIVE -> CLOSED
# ------------------------------------------------------------

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID/state" \
    "$MINISTRY_TOKEN" \
    '{
      "quizState":"CLOSED"
    }'
)"

check_status \
  200 \
  "$STATUS" \
  "Quiz ACTIVE pode ser encerrado"

STATE="$(
  json_path "$BODY" "quiz_state"
)"

check_value \
  "CLOSED" \
  "$STATE" \
  "Estado do quiz fica CLOSED"

# ------------------------------------------------------------
# CLOSED
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/quizzes/$QUIZ_ID/attempts" \
    "$OTHER_LAMB_TOKEN" \
    "{
      \"answers\":[
        {
          \"questionId\":$Q1_ID,
          \"selectedOptionId\":$Q1_CORRECT
        },
        {
          \"questionId\":$Q2_ID,
          \"selectedOptionId\":$Q2_CORRECT
        },
        {
          \"questionId\":$Q3_ID,
          \"selectedOptionId\":$Q3_CORRECT
        }
      ]
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz CLOSED não aceita novas tentativas"

STATUS="$(
  request \
    PATCH \
    "/quizzes/$QUIZ_ID/state" \
    "$MINISTRY_TOKEN" \
    '{
      "quizState":"ACTIVE"
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Quiz CLOSED não pode voltar para ACTIVE"

STATUS="$(
  request \
    GET \
    "/quizzes/$QUIZ_ID/ranking" \
    "$LAMB_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Ranking continua disponível após fechamento do quiz"

# ------------------------------------------------------------
# Soft delete de DRAFT
# ------------------------------------------------------------

STATUS="$(
  request \
    DELETE \
    "/quizzes/$ASSISTANT_QUIZ_ID" \
    "$ASSISTANT_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Criador pode remover quiz em DRAFT"

DELETED_STATUS="$(
  mysql_exec "
    SELECT status
    FROM quizzes
    WHERE id = $ASSISTANT_QUIZ_ID;
  "
)"

check_value \
  "I" \
  "$DELETED_STATUS" \
  "Remoção do quiz utiliza soft delete"

STATUS="$(
  request \
    GET \
    "/quizzes/$ASSISTANT_QUIZ_ID" \
    "$ASSISTANT_TOKEN"
)"

check_status \
  404 \
  "$STATUS" \
  "Quiz inativo não pode ser consultado"

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

echo
echo "========================================"
echo " ✅ TODOS OS $TEST_NUMBER TESTES QUIZZES/RANKING PASSARAM"
echo "========================================"
echo

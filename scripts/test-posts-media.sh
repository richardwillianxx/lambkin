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
echo " LAMBKIN - TESTE POSTS / MEDIA"
echo "========================================"
echo

# ------------------------------------------------------------
# Auxiliares
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

check_value() {
  EXPECTED="$1"
  ACTUAL="$2"
  NAME="$3"

  if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "✅ $NAME"
  else
    echo "❌ $NAME"
    echo "Esperado: $EXPECTED"
    echo "Recebido: $ACTUAL"
    echo
    exit 1
  fi
}

json_field() {
  python3 -c '
import json
import sys

data = json.load(open(sys.argv[1]))
print(data[sys.argv[2]])
' "$1" "$2"
}

json_has_key_recursive() {
  python3 -c '
import json
import sys

data = json.load(open(sys.argv[1]))
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

print("true" if has_key(data) else "false")
' "$1" "$2"
}

json_array_contains_id() {
  python3 -c '
import json
import sys

data = json.load(open(sys.argv[1]))
target = int(sys.argv[2])

found = any(
    item.get("id") == target
    for item in data
)

print("true" if found else "false")
' "$1" "$2"
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
  WHERE name = 'Congregação Teste Posts'
  LIMIT 1
);

SET @cid_other = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Posts Outra'
  LIMIT 1
);

SET @cid_inactive = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste Posts Inativa'
  LIMIT 1
);

DELETE FROM post_reactions
WHERE post_id IN (
  SELECT id
  FROM posts
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
  OR author_user_id IN (
    SELECT u.id
    FROM users u
    INNER JOIN people p
      ON p.id = u.person_id
    WHERE p.congregation_id IN (
      @cid_main,
      @cid_other,
      @cid_inactive
    )
  )
)
OR user_id IN (
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

DELETE FROM post_media
WHERE post_id IN (
  SELECT id
  FROM posts
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
  OR author_user_id IN (
    SELECT u.id
    FROM users u
    INNER JOIN people p
      ON p.id = u.person_id
    WHERE p.congregation_id IN (
      @cid_main,
      @cid_other,
      @cid_inactive
    )
  )
)
OR media_id IN (
  SELECT id
  FROM media
  WHERE uploaded_by_user_id IN (
    SELECT u.id
    FROM users u
    INNER JOIN people p
      ON p.id = u.person_id
    WHERE p.congregation_id IN (
      @cid_main,
      @cid_other,
      @cid_inactive
    )
  )
);

DELETE FROM posts
WHERE congregation_id IN (
  @cid_main,
  @cid_other,
  @cid_inactive
)
OR author_user_id IN (
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

DELETE FROM media
WHERE uploaded_by_user_id IN (
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

DELETE FROM image_authorizations
WHERE person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
)
OR authorized_by_person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
);

DELETE FROM person_guardians
WHERE child_person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id IN (
    @cid_main,
    @cid_other,
    @cid_inactive
  )
)
OR guardian_person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id IN (
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
  'Congregação Teste Posts',
  'A'
),
(
  'Congregação Teste Posts Outra',
  'A'
),
(
  'Congregação Teste Posts Inativa',
  'I'
);
"

CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste Posts';
  "
)"

OTHER_CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste Posts Outra';
  "
)"

INACTIVE_CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste Posts Inativa';
  "
)"

# ------------------------------------------------------------
# Usuários de teste
# ------------------------------------------------------------

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
  $CONGREGATION_ID,
  'MINISTRY',
  'MALE',
  'Administrador Teste Posts',
  'Admin Posts Test',
  '1990-01-01',
  'admin.posts@lambkin.local',
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
  'admin_posts_test',
  '$HASH',
  TRUE,
  NOW(3),
  'A'
);
"

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
  $CONGREGATION_ID,
  'MINISTRY',
  'MALE',
  'Ministério Teste Posts',
  'Ministry Posts Test',
  '1985-01-01',
  'ministry.posts@lambkin.local',
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
  'ministry_posts_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

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
  $CONGREGATION_ID,
  'ASSISTANT',
  'FEMALE',
  'Auxiliar Teste Posts',
  'Assistant Posts Test',
  '1992-01-01',
  'assistant.posts@lambkin.local',
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
  'assistant_posts_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

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
  $CONGREGATION_ID,
  'LAMB',
  'MALE',
  'Cordeiro Teste Posts',
  'Lamb Posts Test',
  '1995-01-01',
  'lamb.posts@lambkin.local',
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
  'lamb_posts_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

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
  $CONGREGATION_ID,
  'GUARDIAN',
  'FEMALE',
  'Responsável Teste Posts',
  'Guardian Posts Test',
  '1985-03-20',
  'guardian.posts@lambkin.local',
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
  'guardian_posts_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

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
  $CONGREGATION_ID,
  'LAMB',
  'FEMALE',
  'Adulto Autorização Posts',
  'Adult Image Posts Test',
  '1990-05-15',
  'adult.image.posts@lambkin.local',
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
  'adult_image_posts_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

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
  $CONGREGATION_ID,
  'LAMB',
  'MALE',
  'Criança Autorização Posts',
  'Child Image Posts Test',
  '2020-01-10',
  'child.image.posts@lambkin.local',
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
  'child_image_posts_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

GUARDIAN_PERSON_ID="$(
  mysql_exec "
    SELECT p.id
    FROM people p
    INNER JOIN users u
      ON u.person_id = p.id
    WHERE u.username = 'guardian_posts_test';
  "
)"

ADULT_PERSON_ID="$(
  mysql_exec "
    SELECT p.id
    FROM people p
    INNER JOIN users u
      ON u.person_id = p.id
    WHERE u.username = 'adult_image_posts_test';
  "
)"

CHILD_PERSON_ID="$(
  mysql_exec "
    SELECT p.id
    FROM people p
    INNER JOIN users u
      ON u.person_id = p.id
    WHERE u.username = 'child_image_posts_test';
  "
)"

LAMB_USER_ID="$(
  mysql_exec "
    SELECT id
    FROM users
    WHERE username = 'lamb_posts_test';
  "
)"

mysql_exec "
INSERT INTO person_guardians (
  child_person_id,
  guardian_person_id,
  relationship
)
VALUES (
  $CHILD_PERSON_ID,
  $GUARDIAN_PERSON_ID,
  'MOTHER'
);
"

echo "✅ Banco preparado"
echo

# ------------------------------------------------------------
# Login Admin
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"admin_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "1. Administrador consegue autenticar"

ADMIN_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login Ministry
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"ministry_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "2. Ministry consegue autenticar"

MINISTRY_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login Assistant
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"assistant_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "3. Assistant consegue autenticar"

ASSISTANT_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login Lamb
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"lamb_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "4. Lamb consegue autenticar"

LAMB_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login Guardian
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"guardian_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "5. Guardian consegue autenticar"

GUARDIAN_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login adulto
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"adult_image_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "6. Adulto consegue autenticar"

ADULT_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login criança
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"child_image_posts_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "7. Conta do menor consegue autenticar"

CHILD_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Segurança de Posts
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/posts")

check_status 401 "$STATUS" \
  "8. /posts exige autenticação"

# ------------------------------------------------------------
# Post vazio
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "caption":""
  }')

check_status 400 "$STATUS" \
  "9. Post sem conteúdo é bloqueado enquanto não há mídia"

# ------------------------------------------------------------
# Post pessoal
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "caption":"Minha primeira publicação de teste"
  }')

check_status 201 "$STATUS" \
  "10. Usuário autenticado cria post pessoal"

POST_ID=$(json_field "$BODY" id)

# ------------------------------------------------------------
# Consultar post
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 200 "$STATUS" \
  "11. Post pode ser consultado por ID"

HAS_PASSWORD_HASH="$(
  json_has_key_recursive \
    "$BODY" \
    "password_hash"
)"

check_value "false" "$HAS_PASSWORD_HASH" \
  "12. API não expõe password_hash no post"

# ------------------------------------------------------------
# Editar próprio post
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X PATCH \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "caption":"Publicação atualizada pelo autor"
  }')

check_status 200 "$STATUS" \
  "13. Autor consegue editar próprio post"

# ------------------------------------------------------------
# Outro usuário não edita
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X PATCH \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $ASSISTANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "caption":"Tentativa de alteração indevida"
  }')

check_status 403 "$STATUS" \
  "14. Outro usuário não pode editar post alheio"

# ------------------------------------------------------------
# Admin pode editar
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X PATCH \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "caption":"Publicação revisada pelo administrador"
  }')

check_status 200 "$STATUS" \
  "15. System Admin pode editar post"

# ------------------------------------------------------------
# Outro usuário não remove
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $ASSISTANT_TOKEN")

check_status 403 "$STATUS" \
  "16. Outro usuário não pode remover post alheio"

# ------------------------------------------------------------
# Post da congregação - Ministry
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $MINISTRY_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Publicação oficial Ministry\",
    \"congregationId\":$CONGREGATION_ID
  }")

check_status 201 "$STATUS" \
  "17. Ministry pode publicar pela própria congregação"

# ------------------------------------------------------------
# Post da congregação - Assistant
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $ASSISTANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Publicação oficial Assistant\",
    \"congregationId\":$CONGREGATION_ID
  }")

check_status 201 "$STATUS" \
  "18. Assistant pode publicar pela própria congregação"

# ------------------------------------------------------------
# Admin em outra congregação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Publicação administrativa em outra congregação\",
    \"congregationId\":$OTHER_CONGREGATION_ID
  }")

check_status 201 "$STATUS" \
  "19. System Admin pode publicar por outra congregação ativa"

# ------------------------------------------------------------
# Lamb não publica pela congregação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Tentativa Lamb\",
    \"congregationId\":$CONGREGATION_ID
  }")

check_status 403 "$STATUS" \
  "20. Lamb não pode publicar pela congregação"

# ------------------------------------------------------------
# Guardian não publica pela congregação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $GUARDIAN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Tentativa Guardian\",
    \"congregationId\":$CONGREGATION_ID
  }")

check_status 403 "$STATUS" \
  "21. Guardian não pode publicar pela congregação"

# ------------------------------------------------------------
# Ministry não publica por outra congregação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $MINISTRY_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Tentativa outra congregação\",
    \"congregationId\":$OTHER_CONGREGATION_ID
  }")

check_status 403 "$STATUS" \
  "22. Ministry não publica por congregação diferente da sua"

# ------------------------------------------------------------
# Congregação inativa
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"caption\":\"Tentativa congregação inativa\",
    \"congregationId\":$INACTIVE_CONGREGATION_ID
  }")

check_status 400 "$STATUS" \
  "23. Congregação inativa é bloqueada"

# ------------------------------------------------------------
# Congregação inexistente
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "caption":"Tentativa congregação inexistente",
    "congregationId":999999999
  }')

check_status 400 "$STATUS" \
  "24. Congregação inexistente é bloqueada"

# ------------------------------------------------------------
# Reação inválida
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts/$POST_ID/reaction" \
  -H "Authorization: Bearer $ASSISTANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reactionType":"INVALID"
  }')

check_status 400 "$STATUS" \
  "25. Tipo de reação inválido é bloqueado"

# ------------------------------------------------------------
# HEART
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts/$POST_ID/reaction" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reactionType":"HEART"
  }')

check_status 201 "$STATUS" \
  "26. Usuário consegue reagir com HEART"

# ------------------------------------------------------------
# HEART -> CLAP
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts/$POST_ID/reaction" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reactionType":"CLAP"
  }')

check_status 201 "$STATUS" \
  "27. Reação existente pode ser alterada para CLAP"

REACTION_STATE="$(
  mysql_exec "
    SELECT CONCAT(
      COUNT(*),
      ':',
      MAX(reaction_type)
    )
    FROM post_reactions
    WHERE post_id = $POST_ID
      AND user_id = $LAMB_USER_ID;
  "
)"

check_value "1:CLAP" "$REACTION_STATE" \
  "28. Existe apenas uma reação por usuário/post"

# ------------------------------------------------------------
# Remover reação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/posts/$POST_ID/reaction" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 200 "$STATUS" \
  "29. Usuário consegue remover reação"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/posts/$POST_ID/reaction" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 404 "$STATUS" \
  "30. Remover reação já inativa retorna 404"

# ------------------------------------------------------------
# Reativar reação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/posts/$POST_ID/reaction" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reactionType":"HEART"
  }')

check_status 201 "$STATUS" \
  "31. Reagir novamente reativa o mesmo registro"

REACTION_STATE="$(
  mysql_exec "
    SELECT CONCAT(
      COUNT(*),
      ':',
      MAX(reaction_type),
      ':',
      MAX(status)
    )
    FROM post_reactions
    WHERE post_id = $POST_ID
      AND user_id = $LAMB_USER_ID;
  "
)"

check_value "1:HEART:A" "$REACTION_STATE" \
  "32. Reação é reativada sem criar duplicidade"

# ------------------------------------------------------------
# Remover publicação
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 200 "$STATUS" \
  "33. Autor consegue remover própria publicação"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/posts/$POST_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 404 "$STATUS" \
  "34. Publicação removida não pode ser consultada"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/posts" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 200 "$STATUS" \
  "35. Feed continua disponível após remoção"

POST_IN_FEED="$(
  json_array_contains_id \
    "$BODY" \
    "$POST_ID"
)"

check_value "false" "$POST_IN_FEED" \
  "36. Publicação inativa não aparece no feed"

# ------------------------------------------------------------
# Autorização de imagem - adulto
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$ADULT_PERSON_ID" \
  -H "Authorization: Bearer $ADULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2026.1"
  }')

check_status 201 "$STATUS" \
  "37. Adulto pode autorizar a própria imagem"

# ------------------------------------------------------------
# Outra pessoa não autoriza adulto
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$ADULT_PERSON_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2026.1"
  }')

check_status 403 "$STATUS" \
  "38. Outra pessoa não pode autorizar imagem de adulto"

# ------------------------------------------------------------
# Admin não consente em nome de adulto
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$ADULT_PERSON_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2026.1"
  }')

check_status 403 "$STATUS" \
  "39. System Admin não pode consentir em nome de adulto"

# ------------------------------------------------------------
# Admin consulta autorização
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/image-authorizations/$ADULT_PERSON_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

check_status 200 "$STATUS" \
  "40. System Admin pode consultar autorização"

# ------------------------------------------------------------
# Pessoa aleatória não consulta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/image-authorizations/$ADULT_PERSON_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN")

check_status 403 "$STATUS" \
  "41. Usuário sem vínculo não consulta autorização alheia"

# ------------------------------------------------------------
# Adulto aceita versão nova
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$ADULT_PERSON_ID" \
  -H "Authorization: Bearer $ADULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2027.1"
  }')

check_status 201 "$STATUS" \
  "42. Adulto pode aceitar nova versão do termo"

TERMS_VERSION=$(json_field "$BODY" terms_version)

check_value "2027.1" "$TERMS_VERSION" \
  "43. Nova versão do termo fica registrada"

# ------------------------------------------------------------
# Menor não autoriza a própria imagem
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $CHILD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2026.1"
  }')

check_status 403 "$STATUS" \
  "44. Menor de 12 não autoriza a própria imagem"

# ------------------------------------------------------------
# Pessoa sem vínculo não autoriza menor
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $LAMB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2026.1"
  }')

check_status 403 "$STATUS" \
  "45. Pessoa sem vínculo não autoriza imagem do menor"

# ------------------------------------------------------------
# Responsável autoriza menor
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $GUARDIAN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2026.1"
  }')

check_status 201 "$STATUS" \
  "46. Responsável vinculado pode autorizar imagem do menor"

# ------------------------------------------------------------
# Responsável consulta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $GUARDIAN_TOKEN")

check_status 200 "$STATUS" \
  "47. Responsável pode consultar autorização do menor"

# ------------------------------------------------------------
# Revogar autorização
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $GUARDIAN_TOKEN")

check_status 200 "$STATUS" \
  "48. Responsável pode revogar autorização do menor"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $GUARDIAN_TOKEN")

check_status 404 "$STATUS" \
  "49. Autorização já revogada retorna 404"

# ------------------------------------------------------------
# Reautorizar
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/image-authorizations/$CHILD_PERSON_ID" \
  -H "Authorization: Bearer $GUARDIAN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "termsVersion":"2027.2"
  }')

check_status 201 "$STATUS" \
  "50. Responsável pode autorizar novamente com novo termo"

AUTH_STATE="$(
  mysql_exec "
    SELECT CONCAT(
      COUNT(*),
      ':',
      MAX(status),
      ':',
      MAX(terms_version)
    )
    FROM image_authorizations
    WHERE person_id = $CHILD_PERSON_ID;
  "
)"

check_value "1:A:2027.2" "$AUTH_STATE" \
  "51. Autorização reutiliza registro e mantém estado atual"

echo
echo "========================================"
echo " ✅ TODOS OS TESTES POSTS/MEDIA PASSARAM"
echo "========================================"
echo

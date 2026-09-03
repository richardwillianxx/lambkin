#!/usr/bin/env bash

set -e

API="http://localhost:3000"

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"

BODY="$(mktemp)"
TEST_FILE="$(mktemp --suffix=.png)"
DOWNLOADED_FILE="$(mktemp --suffix=.png)"

trap '
  rm -f "$BODY"
  rm -f "$TEST_FILE"
  rm -f "$DOWNLOADED_FILE"
' EXIT

cd "$ROOT_DIR"

set -a
source .env
set +a

echo
echo "========================================"
echo " LAMBKIN - TESTE MEDIA / AWS S3"
echo "========================================"
echo

TEST_NUMBER=0

# ------------------------------------------------------------
# Auxiliares
# ------------------------------------------------------------

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

check_not_status() {
  UNEXPECTED="$1"
  ACTUAL="$2"
  NAME="$3"

  next_test

  if [ "$UNEXPECTED" != "$ACTUAL" ]; then
    echo "✅ $TEST_NUMBER. $NAME"
  else
    echo "❌ $TEST_NUMBER. $NAME"
    echo "HTTP $UNEXPECTED não deveria ter sido recebido."
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

delete_s3_key() {
  KEY="$1"

  if [ -z "$KEY" ]; then
    return
  fi

  (
    cd "$ROOT_DIR/apps/api"

    S3_TEST_KEY="$KEY" node <<'NODE'
const {
  S3Client,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');

const client = new S3Client({
  region: process.env.AWS_REGION,
});

async function main() {
  await client.send(
    new DeleteObjectCommand({
      Bucket: process.env.AWS_S3_BUCKET,
      Key: process.env.S3_TEST_KEY,
    }),
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
  )
}

# ------------------------------------------------------------
# Arquivo PNG real de teste
# ------------------------------------------------------------

base64 -d > "$TEST_FILE" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
EOF

FILE_SIZE="$(
  wc -c < "$TEST_FILE" |
  tr -d ' '
)"

# ------------------------------------------------------------
# Preparação
# ------------------------------------------------------------

echo "Preparando banco e S3..."

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
# Remover objetos S3 da execução anterior
# ------------------------------------------------------------

OLD_KEYS="$(
  mysql_exec "
    SELECT m.storage_key
    FROM media m
    INNER JOIN users u
      ON u.id = m.uploaded_by_user_id
    INNER JOIN people p
      ON p.id = u.person_id
    INNER JOIN congregations c
      ON c.id = p.congregation_id
    WHERE c.name =
      'Congregação Teste Media S3';
  " || true
)"

if [ -n "$OLD_KEYS" ]; then
  while IFS= read -r KEY; do
    delete_s3_key "$KEY"
  done <<< "$OLD_KEYS"
fi

# ------------------------------------------------------------
# Limpeza do banco
# ------------------------------------------------------------

mysql_exec "
SET @cid = (
  SELECT id
  FROM congregations
  WHERE name =
    'Congregação Teste Media S3'
  LIMIT 1
);

DELETE FROM post_reactions
WHERE post_id IN (
  SELECT id
  FROM posts
  WHERE author_user_id IN (
    SELECT u.id
    FROM users u
    INNER JOIN people p
      ON p.id = u.person_id
    WHERE p.congregation_id = @cid
  )
);

DELETE FROM post_media
WHERE post_id IN (
  SELECT id
  FROM posts
  WHERE author_user_id IN (
    SELECT u.id
    FROM users u
    INNER JOIN people p
      ON p.id = u.person_id
    WHERE p.congregation_id = @cid
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
    WHERE p.congregation_id = @cid
  )
);

DELETE FROM posts
WHERE author_user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id = @cid
);

DELETE FROM media
WHERE uploaded_by_user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id = @cid
);

DELETE FROM user_tokens
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id = @cid
);

DELETE FROM user_sessions
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id = @cid
);

DELETE FROM audit_logs
WHERE user_id IN (
  SELECT u.id
  FROM users u
  INNER JOIN people p
    ON p.id = u.person_id
  WHERE p.congregation_id = @cid
);

DELETE FROM users
WHERE person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id = @cid
);

DELETE FROM people
WHERE congregation_id = @cid;

DELETE FROM congregations
WHERE id = @cid;
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
  'Congregação Teste Media S3',
  'A'
);
"

CID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name =
      'Congregação Teste Media S3';
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
  "LAMB" \
  "Uploader Media S3" \
  "uploader_media_s3_test" \
  "uploader.media.s3@lambkin.local" \
  "FALSE"

create_user \
  "LAMB" \
  "Outro Media S3" \
  "other_media_s3_test" \
  "other.media.s3@lambkin.local" \
  "FALSE"

create_user \
  "MINISTRY" \
  "Admin Media S3" \
  "admin_media_s3_test" \
  "admin.media.s3@lambkin.local" \
  "TRUE"

UPLOADER_USER_ID="$(
  mysql_exec "
    SELECT id
    FROM users
    WHERE username =
      'uploader_media_s3_test';
  "
)"

echo "✅ Banco e S3 preparados"
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
  "uploader_media_s3_test" \
  "Usuário uploader autentica" \
  "UPLOADER_TOKEN"

login_user \
  "other_media_s3_test" \
  "Outro usuário autentica" \
  "OTHER_TOKEN"

login_user \
  "admin_media_s3_test" \
  "System Admin autentica" \
  "ADMIN_TOKEN"

# ------------------------------------------------------------
# Segurança / validações
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/media/upload-url" \
    "" \
    "{
      \"originalFilename\":\"teste.png\",
      \"mimeType\":\"image/png\",
      \"sizeBytes\":$FILE_SIZE
    }"
)"

check_status \
  401 \
  "$STATUS" \
  "Gerar URL de upload exige autenticação"

STATUS="$(
  request \
    POST \
    "/media/upload-url" \
    "$UPLOADER_TOKEN" \
    '{
      "originalFilename":"arquivo.pdf",
      "mimeType":"application/pdf",
      "sizeBytes":1000
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Tipo de mídia não permitido é bloqueado"

STATUS="$(
  request \
    POST \
    "/media/upload-url" \
    "$UPLOADER_TOKEN" \
    '{
      "originalFilename":"grande.png",
      "mimeType":"image/png",
      "sizeBytes":10485761
    }'
)"

check_status \
  400 \
  "$STATUS" \
  "Imagem acima de 10 MB é bloqueada"

# ------------------------------------------------------------
# Criar Presigned URL
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/media/upload-url" \
    "$UPLOADER_TOKEN" \
    "{
      \"originalFilename\":\"teste-s3.png\",
      \"mimeType\":\"image/png\",
      \"sizeBytes\":$FILE_SIZE
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "API gera Presigned URL para upload"

STORAGE_KEY="$(
  json_path "$BODY" "storageKey"
)"

UPLOAD_URL="$(
  json_path "$BODY" "uploadUrl"
)"

EXPIRES_IN="$(
  json_path "$BODY" "expiresIn"
)"

check_value \
  "300" \
  "$EXPIRES_IN" \
  "URL de upload expira em cinco minutos"

EXPECTED_PREFIX="media/$UPLOADER_USER_ID/"

case "$STORAGE_KEY" in
  "$EXPECTED_PREFIX"*)
    PREFIX_VALID="true"
    ;;
  *)
    PREFIX_VALID="false"
    ;;
esac

check_value \
  "true" \
  "$PREFIX_VALID" \
  "Storage key é gerada dentro do diretório do usuário"

# ------------------------------------------------------------
# Confirmar antes do upload
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/media/confirm" \
    "$UPLOADER_TOKEN" \
    "{
      \"storageKey\":\"$STORAGE_KEY\",
      \"originalFilename\":\"teste-s3.png\",
      \"mimeType\":\"image/png\",
      \"sizeBytes\":$FILE_SIZE
    }"
)"

check_status \
  400 \
  "$STATUS" \
  "Arquivo não pode ser confirmado antes de existir no S3"

# ------------------------------------------------------------
# Upload real direto ao S3
# ------------------------------------------------------------

S3_UPLOAD_STATUS="$(
  curl \
    -s \
    -o /dev/null \
    -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: image/png" \
    --data-binary @"$TEST_FILE" \
    "$UPLOAD_URL"
)"

check_status \
  200 \
  "$S3_UPLOAD_STATUS" \
  "Arquivo é enviado diretamente para o AWS S3"

# ------------------------------------------------------------
# Outro usuário não confirma storage key alheia
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/media/confirm" \
    "$OTHER_TOKEN" \
    "{
      \"storageKey\":\"$STORAGE_KEY\",
      \"originalFilename\":\"teste-s3.png\",
      \"mimeType\":\"image/png\",
      \"sizeBytes\":$FILE_SIZE
    }"
)"

check_status \
  403 \
  "$STATUS" \
  "Outro usuário não pode confirmar storage key alheia"

# ------------------------------------------------------------
# Confirmar upload
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/media/confirm" \
    "$UPLOADER_TOKEN" \
    "{
      \"storageKey\":\"$STORAGE_KEY\",
      \"originalFilename\":\"teste-s3.png\",
      \"mimeType\":\"image/png\",
      \"sizeBytes\":$FILE_SIZE
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Upload existente no S3 pode ser confirmado"

MEDIA_ID="$(
  json_path "$BODY" "id"
)"

DB_STORAGE_KEY="$(
  mysql_exec "
    SELECT storage_key
    FROM media
    WHERE id = $MEDIA_ID;
  "
)"

check_value \
  "$STORAGE_KEY" \
  "$DB_STORAGE_KEY" \
  "MySQL registra a storage key do S3"

DB_SIZE="$(
  mysql_exec "
    SELECT size_bytes
    FROM media
    WHERE id = $MEDIA_ID;
  "
)"

check_value \
  "$FILE_SIZE" \
  "$DB_SIZE" \
  "MySQL registra o tamanho real do arquivo"

DB_MIME="$(
  mysql_exec "
    SELECT mime_type
    FROM media
    WHERE id = $MEDIA_ID;
  "
)"

check_value \
  "image/png" \
  "$DB_MIME" \
  "MySQL registra o MIME type"

# ------------------------------------------------------------
# Confirmação idempotente
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/media/confirm" \
    "$UPLOADER_TOKEN" \
    "{
      \"storageKey\":\"$STORAGE_KEY\",
      \"originalFilename\":\"teste-s3.png\",
      \"mimeType\":\"image/png\",
      \"sizeBytes\":$FILE_SIZE
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Confirmar novamente não cria mídia duplicada"

SECOND_MEDIA_ID="$(
  json_path "$BODY" "id"
)"

check_value \
  "$MEDIA_ID" \
  "$SECOND_MEDIA_ID" \
  "Confirmação repetida reutiliza o mesmo registro"

MEDIA_COUNT="$(
  mysql_exec "
    SELECT COUNT(*)
    FROM media
    WHERE storage_key =
      '$STORAGE_KEY';
  "
)"

check_value \
  "1" \
  "$MEDIA_COUNT" \
  "Existe apenas um registro para a storage key"

# ------------------------------------------------------------
# Mídia privada antes de ser publicada
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/media/$MEDIA_ID/access" \
    "$OTHER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Mídia ainda não publicada é privada para outro usuário"

STATUS="$(
  request \
    GET \
    "/media/$MEDIA_ID/access" \
    "$ADMIN_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "System Admin pode acessar mídia privada"

# ------------------------------------------------------------
# Uploader acessa mídia
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/media/$MEDIA_ID/access" \
    "$UPLOADER_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Uploader obtém URL privada de acesso"

ACCESS_URL="$(
  json_path "$BODY" "url"
)"

DOWNLOAD_STATUS="$(
  curl \
    -s \
    -o "$DOWNLOADED_FILE" \
    -w "%{http_code}" \
    "$ACCESS_URL"
)"

check_status \
  200 \
  "$DOWNLOAD_STATUS" \
  "Presigned URL permite baixar o arquivo privado"

if cmp -s "$TEST_FILE" "$DOWNLOADED_FILE"; then
  FILE_EQUAL="true"
else
  FILE_EQUAL="false"
fi

check_value \
  "true" \
  "$FILE_EQUAL" \
  "Arquivo baixado do S3 é igual ao enviado"

# ------------------------------------------------------------
# Criar post
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/posts" \
    "$UPLOADER_TOKEN" \
    '{
      "caption":"Publicação de teste com S3"
    }'
)"

check_status \
  201 \
  "$STATUS" \
  "Uploader cria publicação"

POST_ID="$(
  json_path "$BODY" "id"
)"

# ------------------------------------------------------------
# Associar mídia ao post
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/posts/$POST_ID/media" \
    "$UPLOADER_TOKEN" \
    "{
      \"mediaId\":$MEDIA_ID,
      \"position\":1
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Autor associa mídia à publicação"

POST_MEDIA_STATUS="$(
  mysql_exec "
    SELECT status
    FROM post_media
    WHERE post_id = $POST_ID
      AND media_id = $MEDIA_ID;
  "
)"

check_value \
  "A" \
  "$POST_MEDIA_STATUS" \
  "Vínculo post_media fica ativo"

# ------------------------------------------------------------
# Consultar post
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/posts/$POST_ID" \
    "$OTHER_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Publicação com mídia pode ser consultada"

POST_MEDIA_ID="$(
  json_path \
    "$BODY" \
    "post_media.0.media.id"
)"

check_value \
  "$MEDIA_ID" \
  "$POST_MEDIA_ID" \
  "Publicação retorna metadata da mídia"

HAS_STORAGE_KEY="$(
  json_has_key_recursive \
    "$BODY" \
    "storage_key"
)"

check_value \
  "false" \
  "$HAS_STORAGE_KEY" \
  "Publicação não expõe storage_key do S3"

# ------------------------------------------------------------
# Mídia publicada passa a ser acessível
# ------------------------------------------------------------

STATUS="$(
  request \
    GET \
    "/media/$MEDIA_ID/access" \
    "$OTHER_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Outro usuário acessa mídia de publicação ativa"

# ------------------------------------------------------------
# Outro usuário não altera associação
# ------------------------------------------------------------

STATUS="$(
  request \
    DELETE \
    "/posts/$POST_ID/media/$MEDIA_ID" \
    "$OTHER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Outro usuário não remove mídia de publicação alheia"

# ------------------------------------------------------------
# Remover mídia do post
# ------------------------------------------------------------

STATUS="$(
  request \
    DELETE \
    "/posts/$POST_ID/media/$MEDIA_ID" \
    "$UPLOADER_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Autor remove mídia da publicação"

POST_MEDIA_STATUS="$(
  mysql_exec "
    SELECT status
    FROM post_media
    WHERE post_id = $POST_ID
      AND media_id = $MEDIA_ID;
  "
)"

check_value \
  "I" \
  "$POST_MEDIA_STATUS" \
  "Remoção do vínculo utiliza soft delete"

STATUS="$(
  request \
    GET \
    "/media/$MEDIA_ID/access" \
    "$OTHER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Mídia volta a ser privada após ser desvinculada"

# ------------------------------------------------------------
# Reassociar
# ------------------------------------------------------------

STATUS="$(
  request \
    POST \
    "/posts/$POST_ID/media" \
    "$UPLOADER_TOKEN" \
    "{
      \"mediaId\":$MEDIA_ID,
      \"position\":1
    }"
)"

check_status \
  201 \
  "$STATUS" \
  "Mídia removida pode ser associada novamente"

# ------------------------------------------------------------
# Outro usuário não exclui mídia
# ------------------------------------------------------------

STATUS="$(
  request \
    DELETE \
    "/media/$MEDIA_ID" \
    "$OTHER_TOKEN"
)"

check_status \
  403 \
  "$STATUS" \
  "Outro usuário não pode excluir mídia alheia"

# ------------------------------------------------------------
# Exclusão física S3 + lógica DB
# ------------------------------------------------------------

STATUS="$(
  request \
    DELETE \
    "/media/$MEDIA_ID" \
    "$UPLOADER_TOKEN"
)"

check_status \
  200 \
  "$STATUS" \
  "Uploader remove sua mídia"

MEDIA_STATUS="$(
  mysql_exec "
    SELECT status
    FROM media
    WHERE id = $MEDIA_ID;
  "
)"

check_value \
  "I" \
  "$MEDIA_STATUS" \
  "Mídia utiliza soft delete no banco"

POST_MEDIA_STATUS="$(
  mysql_exec "
    SELECT status
    FROM post_media
    WHERE post_id = $POST_ID
      AND media_id = $MEDIA_ID;
  "
)"

check_value \
  "I" \
  "$POST_MEDIA_STATUS" \
  "Vínculos da mídia também são inativados"

STATUS="$(
  request \
    GET \
    "/media/$MEDIA_ID/access" \
    "$UPLOADER_TOKEN"
)"

check_status \
  404 \
  "$STATUS" \
  "Mídia removida não gera nova URL de acesso"

OLD_URL_STATUS="$(
  curl \
    -s \
    -o /dev/null \
    -w "%{http_code}" \
    "$ACCESS_URL"
)"

check_not_status \
  200 \
  "$OLD_URL_STATUS" \
  "Objeto foi realmente removido fisicamente do S3"

echo
echo "========================================"
echo " ✅ TODOS OS $TEST_NUMBER TESTES MEDIA/S3 PASSARAM"
echo "========================================"
echo

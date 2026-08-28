#!/usr/bin/env bash

set -e

API="http://localhost:3000"

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"

BODY="$(mktemp)"
ADMIN_COOKIE="$(mktemp)"
USER_COOKIE="$(mktemp)"
NEW_USER_COOKIE="$(mktemp)"

trap '
  rm -f \
    "$BODY" \
    "$ADMIN_COOKIE" \
    "$USER_COOKIE" \
    "$NEW_USER_COOKIE"
' EXIT

cd "$ROOT_DIR"

set -a
source .env
set +a

echo
echo "========================================"
echo " LAMBKIN - TESTE PEOPLE / USERS"
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

json_field() {
  python3 -c '
import json
import sys

data = json.load(open(sys.argv[1]))
print(data[sys.argv[2]])
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

# Limpeza de execução anterior
mysql_exec "
SET @cid = (
  SELECT id
  FROM congregations
  WHERE name = 'Congregação Teste People'
  LIMIT 1
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

DELETE FROM person_guardians
WHERE child_person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id = @cid
)
OR guardian_person_id IN (
  SELECT id
  FROM people
  WHERE congregation_id = @cid
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

# Congregação
mysql_exec "
INSERT INTO congregations (
  name,
  status
)
VALUES (
  'Congregação Teste People',
  'A'
);
"

CONGREGATION_ID="$(
  mysql_exec "
    SELECT id
    FROM congregations
    WHERE name = 'Congregação Teste People';
  "
)"

# Admin
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
  'Administrador Teste People',
  'Admin People Test',
  '1990-01-01',
  'admin.people@lambkin.local',
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
  'admin_people_test',
  '$HASH',
  TRUE,
  NOW(3),
  'A'
);
"

# Usuário comum
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
  'Usuário Comum Teste',
  'Common People Test',
  '1995-01-01',
  'common.people@lambkin.local',
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
  'common_people_test',
  '$HASH',
  FALSE,
  NOW(3),
  'A'
);
"

echo "✅ Banco preparado"
echo

# ------------------------------------------------------------
# Login admin
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -c "$ADMIN_COOKIE" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"admin_people_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "1. Administrador consegue autenticar"

ADMIN_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Login usuário comum
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -c "$USER_COOKIE" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"common_people_test",
    "password":"Teste123"
  }')

check_status 201 "$STATUS" \
  "2. Usuário comum consegue autenticar"

USER_TOKEN=$(json_field "$BODY" accessToken)

# ------------------------------------------------------------
# Segurança
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/people")

check_status 401 "$STATUS" \
  "3. /people exige autenticação"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/people" \
  -H "Authorization: Bearer $USER_TOKEN")

check_status 200 "$STATUS" \
  "4. Usuário autenticado consegue consultar pessoas"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Tentativa Não Admin\",
    \"preferredName\":\"Tentativa Não Admin\",
    \"birthDate\":\"2000-01-01\"
  }")

check_status 403 "$STATUS" \
  "5. Usuário comum não pode cadastrar pessoa"

# ------------------------------------------------------------
# Criar pessoa adulta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Pessoa Teste Completa\",
    \"preferredName\":\"Pessoa People Test\",
    \"birthDate\":\"2000-05-15\",
    \"email\":\"person.people@lambkin.local\",
    \"whatsapp\":\"5511999990001\",
    \"street\":\"Rua Teste\",
    \"number\":\"100\",
    \"complement\":\"Sala 1\",
    \"district\":\"Centro\",
    \"city\":\"São Paulo\",
    \"state\":\"SP\",
    \"zipCode\":\"01000000\",
    \"notes\":\"Cadastro criado pelo teste E2E\"
  }")

check_status 201 "$STATUS" \
  "6. Administrador consegue cadastrar pessoa"

PERSON_ID=$(json_field "$BODY" id)

# ------------------------------------------------------------
# Duplicidades
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Duplicado Preferred Name\",
    \"preferredName\":\"Pessoa People Test\",
    \"birthDate\":\"2001-01-01\"
  }")

check_status 409 "$STATUS" \
  "7. Nome preferido duplicado é bloqueado"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Duplicado Email\",
    \"preferredName\":\"Duplicado Email Test\",
    \"birthDate\":\"2001-01-01\",
    \"email\":\"person.people@lambkin.local\"
  }")

check_status 409 "$STATUS" \
  "8. E-mail duplicado é bloqueado"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Duplicado WhatsApp\",
    \"preferredName\":\"Duplicado WhatsApp Test\",
    \"birthDate\":\"2001-01-01\",
    \"whatsapp\":\"5511999990001\"
  }")

check_status 409 "$STATUS" \
  "9. WhatsApp duplicado é bloqueado"

# ------------------------------------------------------------
# Consultar pessoa
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/people/$PERSON_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

check_status 200 "$STATUS" \
  "10. Pessoa pode ser consultada por ID"

# ------------------------------------------------------------
# Atualizar
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X PATCH \
  "$API/people/$PERSON_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "preferredName":"Pessoa People Atualizada",
    "city":"Campinas"
  }')

check_status 200 "$STATUS" \
  "11. Administrador consegue atualizar pessoa"

# ------------------------------------------------------------
# Senha curta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$PERSON_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"new_people_user",
    "password":"123"
  }')

check_status 400 "$STATUS" \
  "12. Senha menor que 6 caracteres é bloqueada"

# ------------------------------------------------------------
# Criar conta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$PERSON_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"new_people_user",
    "password":"123456",
    "isSystemAdmin":false
  }')

check_status 201 "$STATUS" \
  "13. Conta é criada para pessoa adulta"

# ------------------------------------------------------------
# Segunda conta mesma pessoa
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$PERSON_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"second_people_user",
    "password":"123456"
  }')

check_status 409 "$STATUS" \
  "14. Pessoa não pode possuir duas contas"

# ------------------------------------------------------------
# Verificar a conta criada
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/verification/resend" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"new_people_user",
    "channel":"EMAIL"
  }')

check_status 201 "$STATUS" \
  "15. Conta criada pode gerar código de verificação"

VERIFICATION_CODE=$(json_field "$BODY" developmentCode)

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/auth/verification/confirm" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\":\"new_people_user\",
    \"channel\":\"EMAIL\",
    \"code\":\"$VERIFICATION_CODE\"
  }")

check_status 201 "$STATUS" \
  "16. Conta criada pode ser verificada"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -c "$NEW_USER_COOKIE" \
  -X POST \
  "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"new_people_user",
    "password":"123456"
  }')

check_status 201 "$STATUS" \
  "17. Conta criada pelo módulo consegue fazer login"

# ------------------------------------------------------------
# Pessoa adulta sem contato
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Adulto Sem Contato\",
    \"preferredName\":\"Adult No Contact Test\",
    \"birthDate\":\"2000-01-01\"
  }")

check_status 201 "$STATUS" \
  "18. Pessoa pode existir sem contato"

NO_CONTACT_ID=$(json_field "$BODY" id)

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$NO_CONTACT_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"no_contact_user",
    "password":"123456"
  }')

check_status 400 "$STATUS" \
  "19. Pessoa com 12+ sem contato não pode criar conta"

# ------------------------------------------------------------
# Criar responsável
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"GUARDIAN\",
    \"gender\":\"FEMALE\",
    \"fullName\":\"Responsável Teste\",
    \"preferredName\":\"Guardian People Test\",
    \"birthDate\":\"1985-03-20\",
    \"email\":\"guardian.people@lambkin.local\"
  }")

check_status 201 "$STATUS" \
  "20. Responsável pode ser cadastrado"

GUARDIAN_ID=$(json_field "$BODY" id)

# Conta do responsável
STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$GUARDIAN_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"guardian_people_user",
    "password":"123456"
  }')

check_status 201 "$STATUS" \
  "21. Responsável pode possuir conta"

# ------------------------------------------------------------
# Criar menor de 12
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"congregationId\":$CONGREGATION_ID,
    \"role\":\"LAMB\",
    \"gender\":\"MALE\",
    \"fullName\":\"Criança Teste\",
    \"preferredName\":\"Child People Test\",
    \"birthDate\":\"2020-01-10\"
  }")

check_status 201 "$STATUS" \
  "22. Menor pode ser cadastrado como pessoa"

CHILD_ID=$(json_field "$BODY" id)

# ------------------------------------------------------------
# Conta menor sem responsável
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$CHILD_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"child_people_user",
    "password":"123456"
  }')

check_status 400 "$STATUS" \
  "23. Menor de 12 sem responsável não pode criar conta"

# ------------------------------------------------------------
# Relação inválida
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$CHILD_ID/guardians" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"guardianPersonId\":$GUARDIAN_ID,
    \"relationship\":\"INVALID\"
  }")

check_status 400 "$STATUS" \
  "24. Tipo de vínculo inválido é bloqueado"

# ------------------------------------------------------------
# Vincular responsável
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$CHILD_ID/guardians" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"guardianPersonId\":$GUARDIAN_ID,
    \"relationship\":\"MOTHER\"
  }")

check_status 201 "$STATUS" \
  "25. Responsável é vinculado ao menor"

# ------------------------------------------------------------
# Duplicidade vínculo
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$CHILD_ID/guardians" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"guardianPersonId\":$GUARDIAN_ID,
    \"relationship\":\"MOTHER\"
  }")

check_status 409 "$STATUS" \
  "26. Responsável duplicado é bloqueado"

# ------------------------------------------------------------
# Responsável por si mesmo
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$GUARDIAN_ID/guardians" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"guardianPersonId\":$GUARDIAN_ID,
    \"relationship\":\"OTHER\"
  }")

check_status 400 "$STATUS" \
  "27. Pessoa não pode ser responsável por si mesma"

# ------------------------------------------------------------
# Conta do menor usando responsável
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X POST \
  "$API/people/$CHILD_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"child_people_user",
    "password":"123456"
  }')

check_status 201 "$STATUS" \
  "28. Menor com responsável e conta ativa pode criar conta"

# ------------------------------------------------------------
# Consultar menor e vínculos
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/people/$CHILD_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

check_status 200 "$STATUS" \
  "29. Cadastro retorna conta e responsáveis"

# ------------------------------------------------------------
# Usuário comum não pode promover conta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X PATCH \
  "$API/people/$PERSON_ID/account" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "isSystemAdmin":true
  }')

check_status 403 "$STATUS" \
  "30. Usuário comum não pode promover conta a System Admin"

# ------------------------------------------------------------
# Atualizar conta
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X PATCH \
  "$API/people/$PERSON_ID/account" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username":"new_people_user_updated"
  }')

check_status 200 "$STATUS" \
  "31. Administrador consegue alterar username"

# ------------------------------------------------------------
# Remover responsável
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/people/$CHILD_ID/guardians/$GUARDIAN_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

check_status 200 "$STATUS" \
  "32. Responsável pode ser desvinculado"

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  -X DELETE \
  "$API/people/$CHILD_ID/guardians/$GUARDIAN_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

check_status 404 "$STATUS" \
  "33. Vínculo inexistente retorna 404"

# ------------------------------------------------------------
# Pessoa inexistente
# ------------------------------------------------------------

STATUS=$(curl -sS \
  -o "$BODY" \
  -w "%{http_code}" \
  "$API/people/999999999" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

check_status 404 "$STATUS" \
  "34. Pessoa inexistente retorna 404"

echo
echo "========================================"
echo " ✅ TODOS OS TESTES PEOPLE/USERS PASSARAM"
echo "========================================"
echo

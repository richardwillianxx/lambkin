-- ============================================================
-- LAMBKIN
-- Banco de dados oficial
-- Database: lambkin_db
-- MySQL 8.0+
-- Engine: InnoDB
-- Charset: utf8mb4
-- ============================================================
-- ============================================================
-- 01. CONGREGATIONS
-- Congregações cadastradas no sistema
-- ============================================================

CREATE TABLE congregations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    name VARCHAR(150) NOT NULL,

    street VARCHAR(150) NULL,
    number VARCHAR(20) NULL,
    complement VARCHAR(100) NULL,
    district VARCHAR(100) NULL,
    city VARCHAR(100) NULL,
    state CHAR(2) NULL,
    zip_code CHAR(8) NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_congregations
        PRIMARY KEY (id),

    CONSTRAINT chk_congregations_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_congregations_status (
        status
    ),

    INDEX idx_congregations_name (
        name
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 02. PEOPLE
-- Pessoas reais cadastradas no sistema
-- Uma pessoa pode existir sem possuir usuário/login
-- ============================================================

CREATE TABLE people (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    congregation_id INT UNSIGNED NOT NULL,

    role ENUM(
        'MINISTRY',
        'ASSISTANT',
        'GUARDIAN',
        'LAMB'
    ) NOT NULL,

    gender ENUM(
        'MALE',
        'FEMALE'
    ) NOT NULL,

    full_name VARCHAR(180) NOT NULL,

    preferred_name VARCHAR(80) NOT NULL,

    birth_date DATE NOT NULL,

    email VARCHAR(254) NULL,

    whatsapp VARCHAR(20) NULL,

    street VARCHAR(150) NULL,
    number VARCHAR(20) NULL,
    complement VARCHAR(100) NULL,
    district VARCHAR(100) NULL,
    city VARCHAR(100) NULL,
    state CHAR(2) NULL,
    zip_code CHAR(8) NULL,

    notes TEXT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_people
        PRIMARY KEY (id),

    CONSTRAINT uq_people_preferred_name
        UNIQUE (preferred_name),

    CONSTRAINT uq_people_email
        UNIQUE (email),

    CONSTRAINT uq_people_whatsapp
        UNIQUE (whatsapp),

    CONSTRAINT fk_people_congregation
        FOREIGN KEY (congregation_id)
        REFERENCES congregations(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_people_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_people_congregation_status (
        congregation_id,
        status
    ),

    INDEX idx_people_role_status (
        role,
        status
    ),

    INDEX idx_people_full_name (
        full_name
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 03. USERS
-- Contas de acesso
-- E-mail e WhatsApp NÃO são duplicados aqui
-- Eles pertencem à tabela people
-- ============================================================

CREATE TABLE users (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    person_id INT UNSIGNED NOT NULL,

    /*
      NULL:
      utiliza o contato da própria pessoa.

      Preenchido:
      utilizado no caso de menor de 12 anos sem contato próprio,
      apontando para um responsável vinculado.
    */
    verification_person_id INT UNSIGNED NULL,

    username VARCHAR(80) NOT NULL,

    password_hash VARCHAR(255)
        CHARACTER SET ascii
        COLLATE ascii_bin
        NOT NULL,

    is_system_admin BOOLEAN NOT NULL DEFAULT FALSE,

    email_verified_at DATETIME(3) NULL,

    whatsapp_verified_at DATETIME(3) NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_users
        PRIMARY KEY (id),

    -- Uma pessoa pode possuir no máximo uma conta
    CONSTRAINT uq_users_person
        UNIQUE (person_id),

    -- Username não pode repetir
    CONSTRAINT uq_users_username
        UNIQUE (username),

    CONSTRAINT fk_users_person
        FOREIGN KEY (person_id)
        REFERENCES people(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_users_verification_person
        FOREIGN KEY (verification_person_id)
        REFERENCES people(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_users_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_users_verification_person (
        verification_person_id
    ),

    INDEX idx_users_status (
        status
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 04. PERSON_GUARDIANS
-- Relação entre crianças e responsáveis
-- ============================================================

CREATE TABLE person_guardians (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    child_person_id INT UNSIGNED NOT NULL,

    guardian_person_id INT UNSIGNED NOT NULL,

    relationship ENUM(
        'FATHER',
        'MOTHER',
        'GRANDFATHER',
        'GRANDMOTHER',
        'LEGAL_GUARDIAN',
        'OTHER'
    ) NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_person_guardians
        PRIMARY KEY (id),

    -- O mesmo responsável não pode ser vinculado duas vezes
    -- à mesma criança.
    CONSTRAINT uq_person_guardians_relationship
        UNIQUE (
            child_person_id,
            guardian_person_id
        ),

    CONSTRAINT fk_person_guardians_child
        FOREIGN KEY (child_person_id)
        REFERENCES people(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_person_guardians_guardian
        FOREIGN KEY (guardian_person_id)
        REFERENCES people(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    -- Uma pessoa não pode ser responsável por si mesma
    CONSTRAINT chk_person_guardians_different_people
        CHECK (
            child_person_id <> guardian_person_id
        ),

    CONSTRAINT chk_person_guardians_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_person_guardians_child_status (
        child_person_id,
        status
    ),

    INDEX idx_person_guardians_guardian_status (
        guardian_person_id,
        status
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 05. IMAGE_AUTHORIZATIONS
-- Estado atual da autorização de uso de imagem
-- ============================================================

CREATE TABLE image_authorizations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    person_id INT UNSIGNED NOT NULL,

    authorized_by_person_id INT UNSIGNED NOT NULL,

    terms_version VARCHAR(30) NOT NULL,

    accepted_at DATETIME(3) NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_image_authorizations
        PRIMARY KEY (id),

    -- Uma autorização atual por pessoa
    CONSTRAINT uq_image_authorizations_person
        UNIQUE (person_id),

    CONSTRAINT fk_image_authorizations_person
        FOREIGN KEY (person_id)
        REFERENCES people(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_image_authorizations_authorized_by
        FOREIGN KEY (authorized_by_person_id)
        REFERENCES people(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_image_authorizations_status
        CHECK (status IN ('A', 'I'))

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 06. POSTS
-- Publicações pessoais e das congregações
--
-- congregation_id NULL:
-- publicação pessoal do autor
--
-- congregation_id preenchido:
-- publicação institucional da congregação
-- ============================================================

CREATE TABLE posts (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    author_user_id INT UNSIGNED NOT NULL,

    congregation_id INT UNSIGNED NULL,

    caption TEXT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_posts
        PRIMARY KEY (id),

    CONSTRAINT fk_posts_author
        FOREIGN KEY (author_user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_posts_congregation
        FOREIGN KEY (congregation_id)
        REFERENCES congregations(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_posts_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_posts_author_status_created (
        author_user_id,
        status,
        created_at
    ),

    INDEX idx_posts_congregation_status_created (
        congregation_id,
        status,
        created_at
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 07. MEDIA
-- Metadados das imagens
-- Arquivos físicos ficam fora do MySQL
-- ============================================================

CREATE TABLE media (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    uploaded_by_user_id INT UNSIGNED NOT NULL,

    /*
      Chave/endereço interno do arquivo no object storage.
      Comparação binária porque a chave precisa ser exata.
    */
    storage_key VARCHAR(500)
        COLLATE utf8mb4_bin
        NOT NULL,

    original_filename VARCHAR(255) NOT NULL,

    mime_type VARCHAR(100) NOT NULL,

    size_bytes INT UNSIGNED NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_media
        PRIMARY KEY (id),

    CONSTRAINT uq_media_storage_key
        UNIQUE (storage_key),

    CONSTRAINT fk_media_uploaded_by
        FOREIGN KEY (uploaded_by_user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_media_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_media_uploaded_by_status (
        uploaded_by_user_id,
        status
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 08. POST_MEDIA
-- Relação entre posts e suas imagens
-- ============================================================

CREATE TABLE post_media (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    post_id INT UNSIGNED NOT NULL,

    media_id INT UNSIGNED NOT NULL,

    position SMALLINT UNSIGNED NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_post_media
        PRIMARY KEY (id),

    CONSTRAINT uq_post_media
        UNIQUE (
            post_id,
            media_id
        ),

    CONSTRAINT fk_post_media_post
        FOREIGN KEY (post_id)
        REFERENCES posts(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_post_media_media
        FOREIGN KEY (media_id)
        REFERENCES media(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_post_media_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_post_media_post_status_position (
        post_id,
        status,
        position
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 09. POST_REACTIONS
-- Reações HEART / CLAP
-- ============================================================

CREATE TABLE post_reactions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    post_id INT UNSIGNED NOT NULL,

    user_id INT UNSIGNED NOT NULL,

    reaction_type ENUM(
        'HEART',
        'CLAP'
    ) NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_post_reactions
        PRIMARY KEY (id),

    -- Um usuário possui no máximo uma reação por post
    CONSTRAINT uq_post_reactions_user_post
        UNIQUE (
            post_id,
            user_id
        ),

    CONSTRAINT fk_post_reactions_post
        FOREIGN KEY (post_id)
        REFERENCES posts(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_post_reactions_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_post_reactions_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_post_reactions_post_status (
        post_id,
        status
    ),

    INDEX idx_post_reactions_user_status (
        user_id,
        status
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 10. QUIZZES
-- ============================================================

CREATE TABLE quizzes (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    title VARCHAR(150) NOT NULL,

    description TEXT NULL,

    quiz_state ENUM(
        'DRAFT',
        'ACTIVE',
        'CLOSED'
    ) NOT NULL DEFAULT 'DRAFT',

    max_attempts SMALLINT UNSIGNED NOT NULL DEFAULT 1,

    created_by_user_id INT UNSIGNED NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_quizzes
        PRIMARY KEY (id),

    CONSTRAINT fk_quizzes_created_by
        FOREIGN KEY (created_by_user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    -- Quiz precisa permitir pelo menos uma tentativa
    CONSTRAINT chk_quizzes_max_attempts
        CHECK (max_attempts >= 1),

    CONSTRAINT chk_quizzes_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_quizzes_state_status (
        quiz_state,
        status
    ),

    INDEX idx_quizzes_created_by_status (
        created_by_user_id,
        status
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 11. QUIZ_QUESTIONS
-- ============================================================

CREATE TABLE quiz_questions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    quiz_id INT UNSIGNED NOT NULL,

    question_text TEXT NOT NULL,

    points SMALLINT UNSIGNED NOT NULL DEFAULT 0,

    position SMALLINT UNSIGNED NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_quiz_questions
        PRIMARY KEY (id),

    CONSTRAINT fk_quiz_questions_quiz
        FOREIGN KEY (quiz_id)
        REFERENCES quizzes(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_quiz_questions_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_quiz_questions_quiz_status_position (
        quiz_id,
        status,
        position
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 12. QUIZ_OPTIONS
-- Alternativas das perguntas
-- ============================================================

CREATE TABLE quiz_options (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    question_id INT UNSIGNED NOT NULL,

    option_text VARCHAR(500) NOT NULL,

    is_correct BOOLEAN NOT NULL DEFAULT FALSE,

    position SMALLINT UNSIGNED NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_quiz_options
        PRIMARY KEY (id),

    CONSTRAINT fk_quiz_options_question
        FOREIGN KEY (question_id)
        REFERENCES quiz_questions(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_quiz_options_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_quiz_options_question_status_position (
        question_id,
        status,
        position
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 13. QUIZ_ATTEMPTS
-- Tentativas realizadas pelos usuários
-- ============================================================

CREATE TABLE quiz_attempts (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    quiz_id INT UNSIGNED NOT NULL,

    user_id INT UNSIGNED NOT NULL,

    /*
      Snapshot da congregação da pessoa no momento
      em que a tentativa foi realizada.
    */
    congregation_id INT UNSIGNED NOT NULL,

    score INT UNSIGNED NOT NULL,

    correct_answers SMALLINT UNSIGNED NOT NULL,

    total_questions SMALLINT UNSIGNED NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_quiz_attempts
        PRIMARY KEY (id),

    CONSTRAINT fk_quiz_attempts_quiz
        FOREIGN KEY (quiz_id)
        REFERENCES quizzes(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_quiz_attempts_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_quiz_attempts_congregation
        FOREIGN KEY (congregation_id)
        REFERENCES congregations(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_quiz_attempts_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_quiz_attempts_user_quiz_status (
        user_id,
        quiz_id,
        status
    ),

    INDEX idx_quiz_attempts_congregation_status (
        congregation_id,
        status
    ),

    INDEX idx_quiz_attempts_quiz_status_created (
        quiz_id,
        status,
        created_at
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 14. QUIZ_ANSWERS
-- Respostas individuais das tentativas
-- ============================================================

CREATE TABLE quiz_answers (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    attempt_id INT UNSIGNED NOT NULL,

    question_id INT UNSIGNED NOT NULL,

    selected_option_id INT UNSIGNED NOT NULL,

    is_correct BOOLEAN NOT NULL,

    points_awarded SMALLINT UNSIGNED NOT NULL DEFAULT 0,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_quiz_answers
        PRIMARY KEY (id),

    -- Uma questão só pode possuir uma resposta
    -- dentro da mesma tentativa.
    CONSTRAINT uq_quiz_answers_attempt_question
        UNIQUE (
            attempt_id,
            question_id
        ),

    CONSTRAINT fk_quiz_answers_attempt
        FOREIGN KEY (attempt_id)
        REFERENCES quiz_attempts(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_quiz_answers_question
        FOREIGN KEY (question_id)
        REFERENCES quiz_questions(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_quiz_answers_selected_option
        FOREIGN KEY (selected_option_id)
        REFERENCES quiz_options(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_quiz_answers_status
        CHECK (status IN ('A', 'I'))

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 15. RECITATIVES
-- ============================================================

CREATE TABLE recitatives (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    name VARCHAR(150) NOT NULL,

    group_number ENUM(
        'FIRST',
        'SECOND',
        'THIRD',
        'FOURTH'
    ) NOT NULL,

    bible_book VARCHAR(60) NOT NULL,

    bible_chapter SMALLINT UNSIGNED NOT NULL,

    /*
      VARCHAR porque pode receber exemplos como:
      11
      11-13
      11,15
    */
    bible_verse VARCHAR(30) NOT NULL,

    gender ENUM(
        'MALE',
        'FEMALE'
    ) NOT NULL,

    congregation_id INT UNSIGNED NOT NULL,

    created_by_user_id INT UNSIGNED NOT NULL,

    recitative_date DATE NOT NULL,

    after_text TEXT NULL,

    reciters_count SMALLINT UNSIGNED NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_recitatives
        PRIMARY KEY (id),

    CONSTRAINT fk_recitatives_congregation
        FOREIGN KEY (congregation_id)
        REFERENCES congregations(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_recitatives_created_by
        FOREIGN KEY (created_by_user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_recitatives_bible_chapter
        CHECK (bible_chapter >= 1),

    CONSTRAINT chk_recitatives_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_recitatives_congregation_date (
        congregation_id,
        status,
        recitative_date
    ),

    INDEX idx_recitatives_congregation_gender (
        congregation_id,
        gender,
        status
    ),

    INDEX idx_recitatives_created_by (
        created_by_user_id,
        status
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 16. USER_SESSIONS
-- Sessões e refresh tokens
-- ============================================================

CREATE TABLE user_sessions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    user_id INT UNSIGNED NOT NULL,

    /*
      Hash SHA-256 em hexadecimal = 64 caracteres.
      O refresh token original nunca é salvo.
    */
    refresh_token_hash CHAR(64)
        CHARACTER SET ascii
        COLLATE ascii_bin
        NOT NULL,

    expires_at DATETIME(3) NOT NULL,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_user_sessions
        PRIMARY KEY (id),

    CONSTRAINT uq_user_sessions_refresh_token_hash
        UNIQUE (refresh_token_hash),

    CONSTRAINT fk_user_sessions_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_user_sessions_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_user_sessions_user_status_expires (
        user_id,
        status,
        expires_at
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 17. USER_TOKENS
-- Códigos temporários:
-- verificação de e-mail
-- verificação de WhatsApp
-- recuperação de senha
-- ============================================================

CREATE TABLE user_tokens (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    user_id INT UNSIGNED NOT NULL,

    token_type ENUM(
        'EMAIL_VERIFICATION',
        'WHATSAPP_VERIFICATION',
        'PASSWORD_RESET'
    ) NOT NULL,

    token_hash CHAR(64)
        CHARACTER SET ascii
        COLLATE ascii_bin
        NOT NULL,

    expires_at DATETIME(3) NOT NULL,

    used_at DATETIME(3) NULL,

    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,

    status CHAR(1) NOT NULL DEFAULT 'A',

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_user_tokens
        PRIMARY KEY (id),

    CONSTRAINT uq_user_tokens_hash
        UNIQUE (token_hash),

    CONSTRAINT fk_user_tokens_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_user_tokens_status
        CHECK (status IN ('A', 'I')),

    INDEX idx_user_tokens_user_type_status_expires (
        user_id,
        token_type,
        status,
        expires_at
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;


-- ============================================================
-- 18. AUDIT_LOGS
-- Histórico de operações administrativas e críticas
--
-- Esta tabela não possui:
-- status
-- updated_at
--
-- O log é append-only.
-- ============================================================

CREATE TABLE audit_logs (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,

    /*
      Pode ser NULL em situações como:
      - falha de login sem usuário identificado;
      - ação automática do sistema.
    */
    user_id INT UNSIGNED NULL,

    action VARCHAR(80) NOT NULL,

    entity_type VARCHAR(60) NULL,

    entity_id INT UNSIGNED NULL,

    metadata JSON NULL,

    /*
      VARCHAR(45) comporta IPv4 e IPv6.
    */
    ip_address VARCHAR(45) NULL,

    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    CONSTRAINT pk_audit_logs
        PRIMARY KEY (id),

    CONSTRAINT fk_audit_logs_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    INDEX idx_audit_logs_user_created (
        user_id,
        created_at
    ),

    INDEX idx_audit_logs_entity_created (
        entity_type,
        entity_id,
        created_at
    ),

    INDEX idx_audit_logs_action_created (
        action,
        created_at
    )

) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_as_ci;

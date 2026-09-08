CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =========================================================
-- ENUMS
-- =========================================================

CREATE TYPE account_type AS ENUM ('SIMPLE', 'FULL');
CREATE TYPE user_status AS ENUM ('ACTIVE', 'DISABLED');

CREATE TYPE credential_type AS ENUM (
    'EMAIL_PASSWORD',
    'MEMBER_PIN'
);

CREATE TYPE group_type AS ENUM (
    'CREDIT_CARD',
    'SHARED_ACCOUNT',
    'OTHER'
);

CREATE TYPE group_status AS ENUM ('ACTIVE', 'ARCHIVED');
CREATE TYPE group_member_role AS ENUM ('OWNER', 'MEMBER');
CREATE TYPE group_member_status AS ENUM ('UNCLAIMED', 'ACTIVE', 'INACTIVE');

CREATE TYPE access_code_status AS ENUM ('ACTIVE', 'REVOKED');
CREATE TYPE invite_status AS ENUM ('ACTIVE', 'REVOKED', 'EXPIRED');
CREATE TYPE join_request_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'CANCELLED'
);

CREATE TYPE billing_cycle_status AS ENUM (
    'FUTURE',
    'OPEN',
    'CLOSED',
    'SETTLED'
);

CREATE TYPE expense_source AS ENUM ('MANUAL', 'CSV_IMPORT');
CREATE TYPE expense_status AS ENUM (
    'ACTIVE',
    'CANCELLED',
    'REFUND_PENDING',
    'REFUNDED'
);

CREATE TYPE installment_status AS ENUM (
    'ACTIVE',
    'CANCELLED',
    'REFUNDED'
);

CREATE TYPE allocation_source AS ENUM (
    'SELF_CLAIM',
    'CREATED_AS_OWNER',
    'ASSIGNMENT_ACCEPTED',
    'SPLIT_ACCEPTED',
    'OWNER_ADJUSTMENT'
);

CREATE TYPE assignment_request_type AS ENUM (
    'ASSIGN',
    'SPLIT',
    'TRANSFER'
);

CREATE TYPE assignment_request_status AS ENUM (
    'PENDING',
    'ACCEPTED',
    'REJECTED',
    'CANCELLED'
);

CREATE TYPE payment_method AS ENUM (
    'PIX',
    'TRANSFER',
    'CASH',
    'OTHER'
);

CREATE TYPE payment_status AS ENUM (
    'PENDING',
    'CONFIRMED',
    'REJECTED'
);

CREATE TYPE payment_source AS ENUM (
    'MEMBER_REPORTED',
    'OWNER_RECORDED'
);

CREATE TYPE import_kind AS ENUM ('PARTIAL', 'FINAL');
CREATE TYPE import_status AS ENUM (
    'PROCESSING',
    'REVIEW',
    'COMPLETED',
    'FAILED',
    'CANCELLED'
);

CREATE TYPE statement_item_type AS ENUM (
    'PURCHASE',
    'PAYMENT',
    'REFUND',
    'OTHER'
);

CREATE TYPE statement_match_status AS ENUM (
    'UNMATCHED',
    'AUTO_MATCHED',
    'MANUAL_MATCHED',
    'REVIEW_REQUIRED',
    'IGNORED'
);

CREATE TYPE refund_review_status AS ENUM (
    'PENDING',
    'CONFIRMED',
    'REJECTED'
);

-- =========================================================
-- USERS / AUTH
-- =========================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    account_display_name VARCHAR(120) NOT NULL,
    email VARCHAR(255),

    account_type account_type NOT NULL DEFAULT 'SIMPLE',
    status user_status NOT NULL DEFAULT 'ACTIVE',

    email_verified_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_users_full_account_email
        CHECK (account_type <> 'FULL' OR email IS NOT NULL)
);

CREATE UNIQUE INDEX ux_users_email_lower
    ON users (LOWER(email))
    WHERE email IS NOT NULL;


CREATE TABLE auth_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id)
        ON DELETE CASCADE,

    type credential_type NOT NULL,
    secret_hash TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, type)
);


CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id)
        ON DELETE CASCADE,

    refresh_token_hash TEXT NOT NULL UNIQUE,

    user_agent TEXT,
    ip_hash TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT ck_user_sessions_expiry
        CHECK (expires_at > created_at)
);

CREATE INDEX idx_user_sessions_user_active
    ON user_sessions (user_id, expires_at)
    WHERE revoked_at IS NULL;


-- =========================================================
-- GROUPS / MEMBERS
-- =========================================================

CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    created_by_user_id UUID NOT NULL
        REFERENCES users(id),

    name VARCHAR(100) NOT NULL,

    type group_type NOT NULL DEFAULT 'CREDIT_CARD',
    status group_status NOT NULL DEFAULT 'ACTIVE',

    member_limit SMALLINT NOT NULL DEFAULT 12
        CHECK (member_limit BETWEEN 2 AND 12),

    credit_limit NUMERIC(14,2)
        CHECK (credit_limit IS NULL OR credit_limit >= 0),

    closing_day SMALLINT
        CHECK (closing_day BETWEEN 1 AND 31),

    due_day SMALLINT
        CHECK (due_day BETWEEN 1 AND 31),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    user_id UUID
        REFERENCES users(id)
        ON DELETE SET NULL,

    group_display_name VARCHAR(120) NOT NULL,

    role group_member_role NOT NULL DEFAULT 'MEMBER',
    status group_member_status NOT NULL DEFAULT 'UNCLAIMED',

    joined_at TIMESTAMPTZ,
    deactivated_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_group_members_claimed_state
        CHECK (
            (status = 'UNCLAIMED' AND user_id IS NULL)
            OR
            (status IN ('ACTIVE', 'INACTIVE'))
        )
);

CREATE UNIQUE INDEX ux_group_members_group_user
    ON group_members (group_id, user_id)
    WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX ux_group_members_single_owner
    ON group_members (group_id)
    WHERE role = 'OWNER' AND status <> 'INACTIVE';

CREATE INDEX idx_group_members_group_status
    ON group_members (group_id, status);


CREATE TABLE member_access_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_member_id UUID NOT NULL
        REFERENCES group_members(id)
        ON DELETE CASCADE,

    code_digest CHAR(64) NOT NULL UNIQUE,
    code_last4 CHAR(4),

    status access_code_status NOT NULL DEFAULT 'ACTIVE',

    activated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX ux_member_access_codes_one_active
    ON member_access_codes (group_member_id)
    WHERE status = 'ACTIVE';


CREATE TABLE group_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    created_by_user_id UUID NOT NULL
        REFERENCES users(id),

    code_digest CHAR(64) NOT NULL UNIQUE,
    code_last4 CHAR(4),

    status invite_status NOT NULL DEFAULT 'ACTIVE',
    expires_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_group_invites_group_active
    ON group_invites (group_id)
    WHERE status = 'ACTIVE';


CREATE TABLE group_join_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    invite_id UUID
        REFERENCES group_invites(id)
        ON DELETE SET NULL,

    requested_user_id UUID NOT NULL
        REFERENCES users(id),

    requested_group_display_name VARCHAR(120) NOT NULL,

    status join_request_status NOT NULL DEFAULT 'PENDING',

    reviewed_by_user_id UUID
        REFERENCES users(id),

    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX ux_join_requests_pending
    ON group_join_requests (group_id, requested_user_id)
    WHERE status = 'PENDING';


-- =========================================================
-- BILLING
-- =========================================================

CREATE TABLE billing_cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    reference_month DATE NOT NULL,

    status billing_cycle_status NOT NULL DEFAULT 'FUTURE',

    due_date DATE,

    closed_at TIMESTAMPTZ,
    settled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_billing_cycles_first_day
        CHECK (EXTRACT(DAY FROM reference_month) = 1),

    UNIQUE (group_id, reference_month)
);

CREATE INDEX idx_billing_cycles_group_status
    ON billing_cycles (group_id, status, reference_month);


-- =========================================================
-- EXPENSES / INSTALLMENTS
-- =========================================================

CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    created_by_member_id UUID NOT NULL
        REFERENCES group_members(id),

    description VARCHAR(255) NOT NULL,
    merchant_normalized VARCHAR(255),
    notes TEXT,

    purchase_date DATE NOT NULL,

    total_amount NUMERIC(14,2) NOT NULL
        CHECK (total_amount > 0),

    installment_count SMALLINT NOT NULL DEFAULT 1
        CHECK (installment_count BETWEEN 1 AND 12),

    source expense_source NOT NULL DEFAULT 'MANUAL',
    status expense_status NOT NULL DEFAULT 'ACTIVE',

    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_expenses_group_date
    ON expenses (group_id, purchase_date DESC);

CREATE INDEX idx_expenses_merchant_trgm
    ON expenses
    USING GIN (merchant_normalized gin_trgm_ops);


CREATE TABLE installments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    expense_id UUID NOT NULL
        REFERENCES expenses(id)
        ON DELETE CASCADE,

    billing_cycle_id UUID NOT NULL
        REFERENCES billing_cycles(id),

    installment_number SMALLINT NOT NULL
        CHECK (installment_number BETWEEN 1 AND 12),

    amount NUMERIC(14,2) NOT NULL
        CHECK (amount > 0),

    charge_date DATE,

    status installment_status NOT NULL DEFAULT 'ACTIVE',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (expense_id, installment_number)
);

CREATE INDEX idx_installments_cycle
    ON installments (billing_cycle_id, status);

CREATE INDEX idx_installments_expense
    ON installments (expense_id, installment_number);


CREATE TABLE installment_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    installment_id UUID NOT NULL
        REFERENCES installments(id)
        ON DELETE RESTRICT,

    group_member_id UUID NOT NULL
        REFERENCES group_members(id)
        ON DELETE RESTRICT,

    amount NUMERIC(14,2) NOT NULL
        CHECK (amount > 0),

    source allocation_source NOT NULL,

    created_by_user_id UUID NOT NULL
        REFERENCES users(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (installment_id, group_member_id)
);

CREATE INDEX idx_allocations_member
    ON installment_allocations (group_member_id, installment_id);


-- =========================================================
-- ASSIGNMENTS / SPLITS
-- =========================================================

CREATE TABLE assignment_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    expense_id UUID NOT NULL
        REFERENCES expenses(id)
        ON DELETE RESTRICT,

    requested_by_member_id UUID NOT NULL
        REFERENCES group_members(id)
        ON DELETE RESTRICT,

    from_group_member_id UUID
        REFERENCES group_members(id)
        ON DELETE RESTRICT,

    to_group_member_id UUID NOT NULL
        REFERENCES group_members(id)
        ON DELETE RESTRICT,

    type assignment_request_type NOT NULL,
    status assignment_request_status NOT NULL DEFAULT 'PENDING',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,

    CONSTRAINT ck_assignment_different_members
        CHECK (
            from_group_member_id IS NULL
            OR from_group_member_id <> to_group_member_id
        )
);

CREATE INDEX idx_assignment_requests_target_pending
    ON assignment_requests (to_group_member_id, created_at DESC)
    WHERE status = 'PENDING';


CREATE TABLE assignment_request_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    assignment_request_id UUID NOT NULL
        REFERENCES assignment_requests(id)
        ON DELETE CASCADE,

    installment_id UUID NOT NULL
        REFERENCES installments(id)
        ON DELETE RESTRICT,

    amount NUMERIC(14,2) NOT NULL
        CHECK (amount > 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (assignment_request_id, installment_id)
);

CREATE INDEX idx_assignment_items_installment
    ON assignment_request_items (installment_id);


-- =========================================================
-- PAYMENTS
-- =========================================================

CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    billing_cycle_id UUID NOT NULL
        REFERENCES billing_cycles(id)
        ON DELETE RESTRICT,

    payer_group_member_id UUID NOT NULL
        REFERENCES group_members(id)
        ON DELETE RESTRICT,

    submitted_by_user_id UUID NOT NULL
        REFERENCES users(id),

    source payment_source NOT NULL,
    amount NUMERIC(14,2) NOT NULL
        CHECK (amount > 0),

    method payment_method,
    status payment_status NOT NULL DEFAULT 'PENDING',

    notes TEXT,
    receipt_storage_key TEXT,

    reviewed_by_user_id UUID
        REFERENCES users(id),

    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,

    CONSTRAINT ck_owner_recorded_payment_confirmed
        CHECK (
            source <> 'OWNER_RECORDED'
            OR status = 'CONFIRMED'
        )
);

CREATE INDEX idx_payments_member_cycle
    ON payments (
        payer_group_member_id,
        billing_cycle_id,
        status
    );


-- =========================================================
-- STATEMENT IMPORT / RECONCILIATION
-- =========================================================

CREATE TABLE import_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    billing_cycle_id UUID NOT NULL
        REFERENCES billing_cycles(id)
        ON DELETE RESTRICT,

    imported_by_user_id UUID NOT NULL
        REFERENCES users(id),

    original_filename VARCHAR(255) NOT NULL,
    file_sha256 CHAR(64) NOT NULL,

    kind import_kind NOT NULL,
    status import_status NOT NULL DEFAULT 'PROCESSING',

    row_count INTEGER NOT NULL DEFAULT 0
        CHECK (row_count >= 0),

    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,

    UNIQUE (group_id, file_sha256)
);


CREATE TABLE statement_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    import_batch_id UUID NOT NULL
        REFERENCES import_batches(id)
        ON DELETE CASCADE,

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    row_number INTEGER NOT NULL
        CHECK (row_number > 0),

    transaction_date DATE NOT NULL,

    title_raw TEXT NOT NULL,
    title_normalized TEXT NOT NULL,

    amount NUMERIC(14,2) NOT NULL,

    type statement_item_type NOT NULL,

    fingerprint CHAR(64) NOT NULL,

    match_status statement_match_status NOT NULL DEFAULT 'UNMATCHED',

    matched_installment_id UUID
        REFERENCES installments(id)
        ON DELETE SET NULL,

    match_confidence NUMERIC(5,4)
        CHECK (
            match_confidence IS NULL
            OR match_confidence BETWEEN 0 AND 1
        ),

    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (import_batch_id, row_number)
);

CREATE INDEX idx_statement_items_group_fingerprint
    ON statement_items (group_id, fingerprint);

CREATE INDEX idx_statement_items_match_status
    ON statement_items (group_id, match_status);

CREATE INDEX idx_statement_items_title_trgm
    ON statement_items
    USING GIN (title_normalized gin_trgm_ops);


-- =========================================================
-- REFUNDS
-- =========================================================

CREATE TABLE refund_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL
        REFERENCES groups(id)
        ON DELETE CASCADE,

    statement_item_id UUID NOT NULL UNIQUE
        REFERENCES statement_items(id)
        ON DELETE RESTRICT,

    expense_id UUID
        REFERENCES expenses(id)
        ON DELETE RESTRICT,

    refund_amount NUMERIC(14,2) NOT NULL
        CHECK (refund_amount > 0),

    status refund_review_status NOT NULL DEFAULT 'PENDING',

    reviewed_by_user_id UUID
        REFERENCES users(id),

    review_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

CREATE INDEX idx_refund_reviews_pending
    ON refund_reviews (group_id, created_at DESC)
    WHERE status = 'PENDING';


-- =========================================================
-- NOTIFICATIONS / AUDIT
-- =========================================================

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id)
        ON DELETE CASCADE,

    group_id UUID
        REFERENCES groups(id)
        ON DELETE CASCADE,

    type VARCHAR(60) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,

    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_unread
    ON notifications (user_id, created_at DESC)
    WHERE read_at IS NULL;


CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID
        REFERENCES groups(id)
        ON DELETE SET NULL,

    actor_user_id UUID
        REFERENCES users(id)
        ON DELETE SET NULL,

    entity_type VARCHAR(60) NOT NULL,
    entity_id UUID,

    action VARCHAR(60) NOT NULL,

    reason TEXT,

    before_data JSONB,
    after_data JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_group_created
    ON audit_logs (group_id, created_at DESC);

CREATE INDEX idx_audit_logs_entity
    ON audit_logs (entity_type, entity_id, created_at DESC);


-- =========================================================
-- UPDATED_AT TRIGGER
-- =========================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_auth_credentials_updated_at
BEFORE UPDATE ON auth_credentials
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_groups_updated_at
BEFORE UPDATE ON groups
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_group_members_updated_at
BEFORE UPDATE ON group_members
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_billing_cycles_updated_at
BEFORE UPDATE ON billing_cycles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_expenses_updated_at
BEFORE UPDATE ON expenses
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_installments_updated_at
BEFORE UPDATE ON installments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_installment_allocations_updated_at
BEFORE UPDATE ON installment_allocations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
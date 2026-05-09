-- =============================================================================
-- ExpenseTrack Database Schema
-- CIS761 Class Project – Matin Marjani
-- PostgreSQL
-- =============================================================================


-- =============================================================================
-- ENUM TYPES
-- =============================================================================

CREATE TYPE account_type AS ENUM ('checking', 'savings', 'cash', 'credit_card');

CREATE TYPE category_type AS ENUM ('income', 'expense');

CREATE TYPE transaction_type AS ENUM ('income', 'expense', 'transfer');

CREATE TYPE receipt_file_type AS ENUM ('pdf', 'jpg', 'png');


-- =============================================================================
-- TABLES
-- =============================================================================

CREATE TABLE Users (
    user_id       SERIAL          PRIMARY KEY,
    email         VARCHAR(255)    NOT NULL UNIQUE,
    username      VARCHAR(100)    NOT NULL UNIQUE,
    password_hash VARCHAR(255)    NOT NULL,
    full_name     VARCHAR(255)    NOT NULL,
    created_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);


CREATE TABLE Accounts (
    account_id      SERIAL          PRIMARY KEY,
    user_id         INTEGER         NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    name            VARCHAR(100)    NOT NULL,
    type            account_type    NOT NULL,
    initial_balance NUMERIC(15, 2)  NOT NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, name)
);


CREATE TABLE Categories (
    category_id SERIAL          PRIMARY KEY,
    user_id     INTEGER         NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    name        VARCHAR(100)    NOT NULL,
    type        category_type   NOT NULL,

    UNIQUE (user_id, name)
);


CREATE TABLE Tags (
    tag_id  SERIAL          PRIMARY KEY,
    user_id INTEGER         NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    name    VARCHAR(100)    NOT NULL,

    UNIQUE (user_id, name)
);


CREATE TABLE Transactions (
    transaction_id          SERIAL              PRIMARY KEY,
    account_id              INTEGER             NOT NULL REFERENCES Accounts(account_id),
    counterparty_account_id INTEGER             REFERENCES Accounts(account_id),
    category_id             INTEGER             REFERENCES Categories(category_id) ON DELETE SET NULL,
    type                    transaction_type    NOT NULL,
    amount                  NUMERIC(15, 2)      NOT NULL,
    transaction_date        DATE                NOT NULL,
    entry_date              DATE                NOT NULL DEFAULT CURRENT_DATE,
    description             TEXT,

    -- amount must always be positive; direction is encoded in type
    CHECK (amount > 0),

    -- a transfer cannot reference itself as the counterparty
    CHECK (counterparty_account_id IS NULL OR counterparty_account_id <> account_id),

    -- type-specific structural rules:
    --   transfer  → counterparty required, category forbidden
    --   income / expense → no counterparty allowed
    CHECK (
        (type = 'transfer'
            AND counterparty_account_id IS NOT NULL
            AND category_id IS NULL)
        OR
        (type IN ('income', 'expense')
            AND counterparty_account_id IS NULL)
    )
);

-- Cross-table business rules that cannot be expressed as CHECK constraints
-- and must be enforced by triggers (added in triggers.sql):
--
--   1. category.type must match transaction.type
--      (an income transaction may only use an income category, etc.)
--
--   2. category.user_id must equal the user who owns account_id
--      (a user cannot assign another user's category to their transaction)
--
--   3. Every tag in TransactionTags must belong to the same user as
--      the transaction's account owner
--
--   4. counterparty_account_id must belong to the same user as account_id


CREATE TABLE Receipts (
    receipt_id          SERIAL              PRIMARY KEY,
    transaction_id      INTEGER             NOT NULL UNIQUE
                                                REFERENCES Transactions(transaction_id) ON DELETE CASCADE,
    file_name           VARCHAR(255)        NOT NULL,
    file_type           receipt_file_type   NOT NULL,
    storage_location    TEXT                NOT NULL,
    uploaded_at         TIMESTAMPTZ         NOT NULL DEFAULT NOW()
    -- UNIQUE on transaction_id enforces the 1-to-1 relationship:
    -- each transaction has at most one receipt
);


CREATE TABLE TransactionTags (
    transaction_id  INTEGER NOT NULL REFERENCES Transactions(transaction_id) ON DELETE CASCADE,
    tag_id          INTEGER NOT NULL REFERENCES Tags(tag_id)               ON DELETE CASCADE,

    PRIMARY KEY (transaction_id, tag_id)
);


-- =============================================================================
-- INDEXES
-- (PKs are indexed automatically; these cover common query patterns)
-- =============================================================================

-- Filter / join by owner
CREATE INDEX idx_accounts_user       ON Accounts(user_id);
CREATE INDEX idx_categories_user     ON Categories(user_id);
CREATE INDEX idx_tags_user           ON Tags(user_id);

-- Most queries filter transactions by account or date range
CREATE INDEX idx_transactions_account       ON Transactions(account_id);
CREATE INDEX idx_transactions_date          ON Transactions(transaction_date);
CREATE INDEX idx_transactions_category      ON Transactions(category_id);
CREATE INDEX idx_transactions_counterparty  ON Transactions(counterparty_account_id);

-- Tag lookups from either direction
CREATE INDEX idx_transactiontags_tag ON TransactionTags(tag_id);


-- =============================================================================
-- VIEWS
-- =============================================================================

-- AccountBalances: computes the current balance of every account.
--
-- Balance = initial_balance
--         + SUM of incoming amounts  (income transactions, incoming transfer legs)
--         - SUM of outgoing amounts  (expense transactions, outgoing transfer legs)
--
-- A transfer produces two effects:
--   - the source account (account_id)              loses the amount  → negative effect
--   - the destination account (counterparty_account_id) gains the amount → positive effect
-- Both legs are captured by the UNION ALL inside the CTE.

CREATE VIEW AccountBalances AS
WITH effects AS (
    -- Direct transactions: income/expense on the main account,
    -- plus the outgoing leg of every transfer
    SELECT
        account_id,
        CASE type
            WHEN 'income'   THEN  amount
            WHEN 'expense'  THEN -amount
            WHEN 'transfer' THEN -amount   -- money leaving this account
        END AS effect
    FROM Transactions

    UNION ALL

    -- Incoming leg of every transfer (credit to the counterparty account)
    SELECT
        counterparty_account_id AS account_id,
        amount                  AS effect
    FROM Transactions
    WHERE type = 'transfer'
)
SELECT
    a.account_id,
    a.user_id,
    a.name,
    a.type,
    a.initial_balance,
    a.initial_balance + COALESCE(SUM(e.effect), 0) AS current_balance
FROM Accounts a
LEFT JOIN effects e ON e.account_id = a.account_id
GROUP BY a.account_id, a.user_id, a.name, a.type, a.initial_balance;

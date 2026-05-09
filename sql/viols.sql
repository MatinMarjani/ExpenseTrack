-- =============================================================================
-- ExpenseTrack – Constraint Violation Demonstrations (viols.sql)
-- CIS761 Class Project – Matin Marjani
-- PostgreSQL
--
-- Every command in this file is INTENTIONALLY designed to fail.
-- Each one targets a specific constraint defined in table.sql and proves
-- the database correctly rejects bad data.
--
-- Instructions: run each block separately and screenshot the error message.
-- The expected error is described in the comment above each command.
--
-- Prerequisite: table.sql and records.sql must have been run first.
-- =============================================================================


-- =============================================================================
-- (a) INSERT creating a KEY violation
--
-- Rule violated: Users.email must be UNIQUE across the entire table.
-- alice.johnson@email.com already belongs to user_id = 1 (Alice Johnson).
-- Attempting to insert a second user with the same email must be rejected.
--
-- Expected error:
--   ERROR: duplicate key value violates unique constraint "users_email_key"
--   DETAIL: Key (email)=(alice.johnson@email.com) already exists.
-- =============================================================================

INSERT INTO Users (email, username, password_hash, full_name)
VALUES ('alice.johnson@email.com', 'newuser', 'hashed_pw_new', 'New User');


-- =============================================================================
-- (b) UPDATE creating a KEY violation
--
-- Rule violated: (user_id, name) must be UNIQUE within Accounts.
-- Alice already has an account named 'Chase Savings' (account_id = 2).
-- Renaming her Chase Checking account to the same name creates a duplicate
-- (user_id=1, name='Chase Savings') pair, which is not allowed.
--
-- Expected error:
--   ERROR: duplicate key value violates unique constraint "accounts_user_id_name_key"
--   DETAIL: Key (user_id, name)=(1, Chase Savings) already exists.
-- =============================================================================

UPDATE Accounts
SET name = 'Chase Savings'
WHERE account_id = 1;


-- =============================================================================
-- (c) INSERT creating a REFERENTIAL INTEGRITY violation
--
-- Rule violated: Transactions.account_id must reference a valid Accounts.account_id.
-- No account with account_id = 999 exists in the database.
-- The foreign key constraint prevents inserting a transaction that points
-- to a non-existent account.
--
-- Expected error:
--   ERROR: insert or update on table "transactions" violates foreign key
--          constraint "transactions_account_id_fkey"
--   DETAIL: Key (account_id)=(999) is not present in table "accounts".
-- =============================================================================

INSERT INTO Transactions (account_id, counterparty_account_id, category_id,
                          type, amount, transaction_date, entry_date, description)
VALUES (999, NULL, NULL, 'income', 500.00, CURRENT_DATE, CURRENT_DATE,
        'Ghost transaction on non-existent account');


-- =============================================================================
-- (d) DELETE creating a REFERENTIAL INTEGRITY violation
--
-- Rule violated: Transactions.account_id references Accounts.account_id
--               with the default ON DELETE RESTRICT behaviour.
-- Account_id = 1 (Alice's Chase Checking) is referenced by many transactions.
-- Deleting it would leave those transactions pointing at nothing, so the
-- database blocks the delete entirely.
--
-- Expected error:
--   ERROR: update or delete on table "accounts" violates foreign key
--          constraint "transactions_account_id_fkey" on table "transactions"
--   DETAIL: Key (account_id)=(1) is still referenced from table "transactions".
-- =============================================================================

DELETE FROM Accounts
WHERE account_id = 1;


-- =============================================================================
-- (e) UPDATE creating a REFERENTIAL INTEGRITY violation
--
-- Rule violated: Transactions.category_id must reference a valid category_id
--               in the Categories table.
-- Changing transaction 1's category to 999 points it at a category that does
-- not exist, violating the foreign key constraint.
--
-- Expected error:
--   ERROR: insert or update on table "transactions" violates foreign key
--          constraint "transactions_category_id_fkey"
--   DETAIL: Key (category_id)=(999) is not present in table "categories".
-- =============================================================================

UPDATE Transactions
SET category_id = 999
WHERE transaction_id = 1;

-- =============================================================================
-- ExpenseTrack Triggers
-- CIS761 Class Project – Matin Marjani
-- PostgreSQL
--
-- Enforces the four cross-table business rules that cannot be expressed
-- as CHECK constraints because they require looking up other tables.
--
-- Run this file after table.sql.
-- =============================================================================


-- =============================================================================
-- TRIGGER 1: Category type must match transaction type
--
-- Rule: if a transaction has a category, the category's type must equal
--       the transaction's type (income↔income, expense↔expense).
--       Transfer transactions cannot have a category at all — that is
--       already blocked by the CHECK constraint in table.sql, so this
--       trigger only needs to handle income/expense.
-- Fires: BEFORE INSERT OR UPDATE on Transactions
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_check_category_type_match()
RETURNS TRIGGER AS $$
DECLARE
    cat_type category_type;
BEGIN
    IF NEW.category_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT type INTO cat_type
    FROM Categories
    WHERE category_id = NEW.category_id;

    IF cat_type::text <> NEW.type::text THEN
        RAISE EXCEPTION
            'Category type "%" does not match transaction type "%". '
            'An income transaction requires an income category and vice versa.',
            cat_type, NEW.type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_category_type_match
BEFORE INSERT OR UPDATE ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_check_category_type_match();


-- =============================================================================
-- TRIGGER 2: Category must belong to the same user as the transaction's account
--
-- Rule: the user_id on the assigned category must equal the user_id of the
--       account referenced by the transaction. A user cannot use another
--       user's categories.
-- Fires: BEFORE INSERT OR UPDATE on Transactions
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_check_category_ownership()
RETURNS TRIGGER AS $$
DECLARE
    acct_user_id INTEGER;
    cat_user_id  INTEGER;
BEGIN
    IF NEW.category_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT user_id INTO acct_user_id
    FROM Accounts
    WHERE account_id = NEW.account_id;

    SELECT user_id INTO cat_user_id
    FROM Categories
    WHERE category_id = NEW.category_id;

    IF acct_user_id <> cat_user_id THEN
        RAISE EXCEPTION
            'Category (id=%) belongs to user % but the transaction account belongs to user %. '
            'A transaction may only use categories owned by the same user.',
            NEW.category_id, cat_user_id, acct_user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_category_ownership
BEFORE INSERT OR UPDATE ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_check_category_ownership();


-- =============================================================================
-- TRIGGER 3: Tag must belong to the same user as the transaction's account owner
--
-- Rule: when a tag is attached to a transaction via TransactionTags, the tag's
--       user_id must equal the user_id of the account on that transaction.
-- Fires: BEFORE INSERT OR UPDATE on TransactionTags
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_check_tag_ownership()
RETURNS TRIGGER AS $$
DECLARE
    acct_user_id INTEGER;
    tag_user_id  INTEGER;
BEGIN
    SELECT a.user_id INTO acct_user_id
    FROM Transactions t
    JOIN Accounts a ON a.account_id = t.account_id
    WHERE t.transaction_id = NEW.transaction_id;

    SELECT user_id INTO tag_user_id
    FROM Tags
    WHERE tag_id = NEW.tag_id;

    IF acct_user_id <> tag_user_id THEN
        RAISE EXCEPTION
            'Tag (id=%) belongs to user % but the transaction belongs to user %. '
            'A transaction may only be labelled with tags owned by the same user.',
            NEW.tag_id, tag_user_id, acct_user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_tag_ownership
BEFORE INSERT OR UPDATE ON TransactionTags
FOR EACH ROW EXECUTE FUNCTION fn_check_tag_ownership();


-- =============================================================================
-- TRIGGER 4: Counterparty account must belong to the same user as the main account
--
-- Rule: for transfer transactions, both account_id and counterparty_account_id
--       must be owned by the same user. A user cannot transfer money to or
--       from another user's account.
-- Fires: BEFORE INSERT OR UPDATE on Transactions
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_check_counterparty_ownership()
RETURNS TRIGGER AS $$
DECLARE
    main_user_id         INTEGER;
    counterparty_user_id INTEGER;
BEGIN
    IF NEW.counterparty_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT user_id INTO main_user_id
    FROM Accounts
    WHERE account_id = NEW.account_id;

    SELECT user_id INTO counterparty_user_id
    FROM Accounts
    WHERE account_id = NEW.counterparty_account_id;

    IF main_user_id <> counterparty_user_id THEN
        RAISE EXCEPTION
            'Counterparty account (id=%) belongs to user % but the main account belongs to user %. '
            'Both accounts in a transfer must belong to the same user.',
            NEW.counterparty_account_id, counterparty_user_id, main_user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_counterparty_ownership
BEFORE INSERT OR UPDATE ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_check_counterparty_ownership();

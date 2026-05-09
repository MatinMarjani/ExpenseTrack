-- =============================================================================
-- ExpenseTrack – 15 SQL Queries
-- CIS761 Class Project – Matin Marjani
-- PostgreSQL
--
-- 10 QUESTION-type queries (Q1, Q3–Q8, Q12, Q13, Q15)
--    Answer a specific question; return a focused, small result set.
--
--  5 REPORT-type queries  (Q2, Q9, Q10, Q11, Q14)
--    Summarise broad database content; designed to be human-readable
--    and return many rows in tabular form.
--
-- Where a query filters by a specific user, account, or tag, a placeholder
-- value (e.g. user_id = 1) is used. Replace it with the actual id when running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Total spending per category for a user
--
-- Adds up every expense transaction grouped by category so the user can
-- see where their money is going. Results are ordered from highest to lowest.
--
-- Demonstrates: JOIN, GROUP BY, SUM, ORDER BY
-- -----------------------------------------------------------------------------

SELECT
    c.name          AS category,
    SUM(t.amount)   AS total_spent
FROM Transactions t
JOIN Accounts   a ON a.account_id   = t.account_id
JOIN Categories c ON c.category_id  = t.category_id
WHERE a.user_id = 1
  AND t.type    = 'expense'
GROUP BY c.name
ORDER BY total_spent DESC;


-- -----------------------------------------------------------------------------
-- Query 2 [REPORT]: Monthly income vs expense summary for a user
--
-- Summarises every month on record, showing total income and total expenses
-- side by side. Designed to give the user a full historical picture of their
-- cash flow over time — one row per calendar month, all months included.
--
-- Demonstrates: EXTRACT, GROUP BY, conditional aggregation with FILTER
-- -----------------------------------------------------------------------------

SELECT
    EXTRACT(YEAR  FROM t.transaction_date) AS year,
    EXTRACT(MONTH FROM t.transaction_date) AS month,
    SUM(t.amount) FILTER (WHERE t.type = 'income')  AS total_income,
    SUM(t.amount) FILTER (WHERE t.type = 'expense') AS total_expenses
FROM Transactions t
JOIN Accounts a ON a.account_id = t.account_id
WHERE a.user_id = 1
GROUP BY year, month
ORDER BY year, month;


-- -----------------------------------------------------------------------------
-- Query 3: Current balance of every account for a user
--
-- Reads directly from the AccountBalances view defined in schema.sql.
-- The view handles the full balance calculation (initial balance plus all
-- transaction effects including both legs of transfers).
--
-- Demonstrates: querying a VIEW
-- -----------------------------------------------------------------------------

SELECT
    name,
    type,
    initial_balance,
    current_balance
FROM AccountBalances
WHERE user_id = 1
ORDER BY name;


-- -----------------------------------------------------------------------------
-- Query 4: Top 5 spending categories this month
--
-- Same idea as Query 1 but restricted to the current calendar month.
-- Useful for a "this month so far" dashboard widget.
--
-- Demonstrates: DATE_TRUNC for month bucketing, LIMIT
-- -----------------------------------------------------------------------------

SELECT
    c.name        AS category,
    SUM(t.amount) AS total_spent
FROM Transactions t
JOIN Accounts   a ON a.account_id  = t.account_id
JOIN Categories c ON c.category_id = t.category_id
WHERE a.user_id = 1
  AND t.type    = 'expense'
  AND DATE_TRUNC('month', t.transaction_date) = DATE_TRUNC('month', CURRENT_DATE)
GROUP BY c.name
ORDER BY total_spent DESC
LIMIT 5;


-- -----------------------------------------------------------------------------
-- Query 5: All transactions labelled with a specific tag
--
-- Retrieves every transaction that has been tagged with a given tag name.
-- Goes through the TransactionTags junction table to link transactions to tags.
--
-- Demonstrates: multi-table JOIN through a junction (bridge) table
-- -----------------------------------------------------------------------------

SELECT
    t.transaction_id,
    t.transaction_date,
    t.type,
    t.amount,
    t.description,
    tg.name AS tag
FROM Transactions t
JOIN TransactionTags tt ON tt.transaction_id = t.transaction_id
JOIN Tags            tg ON tg.tag_id         = tt.tag_id
JOIN Accounts         a ON  a.account_id      = t.account_id
WHERE a.user_id  = 1
  AND tg.name    = 'vacation'          -- replace with any tag name
ORDER BY t.transaction_date DESC;


-- -----------------------------------------------------------------------------
-- Query 6: Accounts currently in negative balance
--
-- Finds any account across all users where the computed balance has gone
-- below zero. Uses the AccountBalances view for the computation.
--
-- Demonstrates: filtering a VIEW result with a WHERE condition
-- -----------------------------------------------------------------------------

SELECT
    ab.account_id,
    u.username,
    ab.name             AS account_name,
    ab.type             AS account_type,
    ab.current_balance
FROM AccountBalances ab
JOIN Users u ON u.user_id = ab.user_id
WHERE ab.current_balance < 0
ORDER BY ab.current_balance;


-- -----------------------------------------------------------------------------
-- Query 7: Accounts that have no transactions recorded yet
--
-- Finds accounts that exist in the system but have no transaction history.
-- Uses a correlated NOT EXISTS subquery: for each account, check whether
-- any transaction references it.
--
-- Demonstrates: correlated subquery with NOT EXISTS
-- -----------------------------------------------------------------------------

SELECT
    a.account_id,
    u.username,
    a.name  AS account_name,
    a.type
FROM Accounts a
JOIN Users u ON u.user_id = a.user_id
WHERE NOT EXISTS (
    SELECT 1
    FROM Transactions t
    WHERE t.account_id = a.account_id
)
ORDER BY u.username, a.name;


-- -----------------------------------------------------------------------------
-- Query 8: Months where the user's income exceeded their expenses
--
-- First builds a monthly summary in a CTE, then filters to only the months
-- with a positive net (income > expenses).
--
-- Demonstrates: CTE (WITH clause), HAVING-style filter on aggregated values
-- -----------------------------------------------------------------------------

WITH monthly_summary AS (
    SELECT
        EXTRACT(YEAR  FROM t.transaction_date) AS year,
        EXTRACT(MONTH FROM t.transaction_date) AS month,
        SUM(t.amount) FILTER (WHERE t.type = 'income')  AS total_income,
        SUM(t.amount) FILTER (WHERE t.type = 'expense') AS total_expenses
    FROM Transactions t
    JOIN Accounts a ON a.account_id = t.account_id
    WHERE a.user_id = 1
    GROUP BY year, month
)
SELECT
    year,
    month,
    total_income,
    total_expenses,
    total_income - total_expenses AS net_savings
FROM monthly_summary
WHERE total_income > total_expenses
ORDER BY year, month;


-- -----------------------------------------------------------------------------
-- Query 9 [REPORT]: Running balance over time for a specific account
--
-- Full transaction-by-transaction history for an account, with a running
-- balance column that shows the account balance after each entry. Returns
-- one row per transaction — the complete ledger for that account.
--
-- Demonstrates: window function SUM() OVER (ORDER BY ...)
-- -----------------------------------------------------------------------------

SELECT
    t.transaction_date,
    t.type,
    t.amount,
    t.description,
    a.initial_balance + SUM(
        CASE t.type
            WHEN 'income'   THEN  t.amount
            WHEN 'expense'  THEN -t.amount
            WHEN 'transfer' THEN -t.amount   -- outgoing leg
        END
    ) OVER (ORDER BY t.transaction_date, t.transaction_id) AS running_balance
FROM Transactions t
JOIN Accounts a ON a.account_id = t.account_id
WHERE t.account_id = 1                       -- replace with any account_id
ORDER BY t.transaction_date, t.transaction_id;


-- -----------------------------------------------------------------------------
-- Query 10 [REPORT]: Full spending breakdown by category with percentages
--
-- Lists every expense category a user has spent money in, with the total
-- amount and its percentage share of overall spending. Gives a complete
-- picture of where the user's money goes — all categories, all time.
--
-- Demonstrates: window function SUM() OVER () for computing percentages
-- -----------------------------------------------------------------------------

SELECT
    c.name          AS category,
    SUM(t.amount)   AS category_total,
    ROUND(
        100.0 * SUM(t.amount) / SUM(SUM(t.amount)) OVER (),
        2
    )               AS percentage
FROM Transactions t
JOIN Accounts   a ON a.account_id  = t.account_id
JOIN Categories c ON c.category_id = t.category_id
WHERE a.user_id = 1
  AND t.type    = 'expense'
GROUP BY c.name
ORDER BY category_total DESC;


-- -----------------------------------------------------------------------------
-- Query 11 [REPORT]: Receipt coverage summary across all accounts
--
-- For every account belonging to a user, shows the total number of
-- transactions, how many have a receipt attached, and how many do not.
-- Gives an at-a-glance audit of documentation coverage across all accounts.
--
-- Demonstrates: LEFT JOIN, COUNT with and without NULL handling
-- -----------------------------------------------------------------------------

SELECT
    a.name                                              AS account,
    COUNT(t.transaction_id)                             AS total_transactions,
    COUNT(r.receipt_id)                                 AS with_receipt,
    COUNT(t.transaction_id) - COUNT(r.receipt_id)       AS without_receipt
FROM Accounts     a
JOIN Transactions t ON t.account_id      = a.account_id
LEFT JOIN Receipts r ON r.transaction_id = t.transaction_id
WHERE a.user_id = 1
GROUP BY a.account_id, a.name
ORDER BY a.name;


-- -----------------------------------------------------------------------------
-- Query 12: Most-used tags across all transactions
--
-- Ranks tags by how many transactions they have been applied to.
-- Useful for finding which labels users rely on most.
--
-- Demonstrates: JOIN, COUNT, GROUP BY, ORDER BY DESC, LIMIT
-- -----------------------------------------------------------------------------

SELECT
    tg.name             AS tag,
    u.username          AS owner,
    COUNT(tt.transaction_id) AS usage_count
FROM Tags            tg
JOIN Users            u ON  u.user_id = tg.user_id
JOIN TransactionTags tt ON tt.tag_id  = tg.tag_id
GROUP BY tg.tag_id, tg.name, u.username
ORDER BY usage_count DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Query 13: Users who have more than one type of account
--
-- Finds users who have diversified across account types (e.g. both a
-- checking and a savings account). COUNT(DISTINCT …) collapses duplicate
-- types before counting.
--
-- Demonstrates: COUNT(DISTINCT …), GROUP BY, HAVING
-- -----------------------------------------------------------------------------

SELECT
    u.user_id,
    u.username,
    COUNT(DISTINCT a.type) AS distinct_account_types
FROM Users    u
JOIN Accounts a ON a.user_id = u.user_id
GROUP BY u.user_id, u.username
HAVING COUNT(DISTINCT a.type) > 1
ORDER BY distinct_account_types DESC;


-- -----------------------------------------------------------------------------
-- Query 14 [REPORT]: Net worth summary across all users
--
-- Lists every user in the system with their total net worth, computed by
-- summing the current balance of all their accounts. A system-wide
-- financial overview — one row per user, all users included.
--
-- Demonstrates: aggregating over a VIEW result, GROUP BY, SUM
-- -----------------------------------------------------------------------------

SELECT
    u.username,
    u.full_name,
    SUM(ab.current_balance) AS net_worth
FROM Users           u
JOIN AccountBalances ab ON ab.user_id = u.user_id
GROUP BY u.user_id, u.username, u.full_name
ORDER BY net_worth DESC;


-- -----------------------------------------------------------------------------
-- Query 15: Categories that have never been used in any transaction
--
-- Finds categories a user created but never assigned to a transaction.
-- Uses EXCEPT: the first SELECT is all categories for the user; the second
-- is categories that appear on at least one transaction. EXCEPT removes
-- the used ones, leaving only the unused.
--
-- Demonstrates: EXCEPT set operator
-- -----------------------------------------------------------------------------

SELECT c.category_id, c.name, c.type
FROM Categories c
WHERE c.user_id = 1

EXCEPT

SELECT c.category_id, c.name, c.type
FROM Categories  c
JOIN Transactions t ON t.category_id = c.category_id
WHERE c.user_id = 1

ORDER BY type, name;

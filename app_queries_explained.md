# ExpenseTrack — Every App Query Explained
## CIS 761 — Matin Marjani

This document covers every SQL statement executed in `app.py`, grouped by the route or
feature it belongs to. For each query the explanation covers: what it does, why it is
written the way it is, and which SQL concepts it uses.

---

## Shared Helpers

These small queries run on almost every page load.

---

### Get all users (navbar switcher)

```sql
SELECT user_id, username, full_name
FROM   Users
ORDER  BY user_id
```

**What it does:** Loads every user in the system to populate the "Viewing as" dropdown in the navbar.

**How it works:** A plain SELECT with no WHERE clause returns all rows. ORDER BY user_id keeps the list stable so the dropdown order never changes. Only three columns are selected because the navbar only needs the ID (to build URLs) and the display name.

---

### Get a single user's full name

```sql
SELECT full_name FROM Users WHERE user_id = %s
```

**What it does:** Retrieves the display name shown in the top-right corner of every page.

**How it works:** A point lookup by primary key. This is as simple as a SQL query gets — the primary key index makes it instant. The `%s` is a parameter placeholder; psycopg2 substitutes the actual value safely, preventing SQL injection.

---

## Dashboard (`/`)

---

### Account balances

```sql
SELECT name, type, initial_balance, current_balance
FROM   AccountBalances
WHERE  user_id = %s
ORDER  BY name
```

**What it does:** Loads all accounts for the user with their computed current balances for the accounts table on the dashboard.

**How it works:** This reads from `AccountBalances`, which is a VIEW, not a base table. The view does all the balance computation internally (initial balance plus all transaction effects). From the application's perspective it looks like a normal SELECT — the complexity is hidden inside the view definition. ORDER BY name sorts accounts alphabetically.

---

### Net worth (total across all accounts)

```sql
SELECT COALESCE(SUM(current_balance), 0) AS net_worth
FROM   AccountBalances
WHERE  user_id = %s
```

**What it does:** Adds up all account balances to produce a single net worth number for the big card at the top of the dashboard.

**How it works:** SUM aggregates all `current_balance` values from the view into one number. COALESCE handles the edge case where a user has no accounts — without it, SUM over zero rows returns NULL, which would crash the template. COALESCE converts NULL to 0 instead.

---

### Net worth trend (monthly cumulative — line chart data)

```sql
WITH monthly_delta AS (
    SELECT
        DATE_TRUNC('month', t.transaction_date) AS month_start,
        SUM(CASE t.type
            WHEN 'income'  THEN  t.amount
            WHEN 'expense' THEN -t.amount
            ELSE 0
        END) AS delta
    FROM Transactions t
    JOIN Accounts a ON a.account_id = t.account_id
    WHERE a.user_id = %s
    GROUP BY DATE_TRUNC('month', t.transaction_date)
),
initial AS (
    SELECT COALESCE(SUM(initial_balance), 0) AS total
    FROM Accounts WHERE user_id = %s
)
SELECT
    TO_CHAR(m.month_start, 'Mon YYYY') AS label,
    ROUND((i.total + SUM(m.delta) OVER (ORDER BY m.month_start))::numeric, 2) AS net_worth
FROM monthly_delta m, initial i
ORDER BY m.month_start
```

**What it does:** Produces one data point per calendar month showing what the user's total net worth was at the end of that month. This feeds the line chart on the dashboard.

**How it works — step by step:**

1. **`monthly_delta` CTE:** For each calendar month, computes the net change in wealth. A CASE expression converts each transaction's amount into a signed value: income is positive (money in), expense is negative (money out), and transfers are 0 (they move money between accounts but don't change total wealth). DATE_TRUNC('month', ...) rounds every date down to the 1st of its month, then GROUP BY buckets all transactions in the same month together and sums their signed amounts.

2. **`initial` CTE:** Fetches the sum of all the user's `initial_balance` values. This is the starting point — the wealth the user had before any transactions were entered in the system.

3. **Outer SELECT:** Combines the two CTEs using a CROSS JOIN (the comma between table names). Since `initial` always returns exactly one row, this is safe — it just attaches that one starting-value to every row of `monthly_delta`. The window function `SUM(m.delta) OVER (ORDER BY m.month_start)` then computes a running total of the monthly deltas, ordered chronologically. Adding `i.total` to that running total gives the actual net worth at the end of each month. TO_CHAR formats the date as "Jan 2025" for the chart label. ROUND ensures two decimal places.

**SQL concepts used:** CTE (WITH clause), CASE expression for signed amounts, DATE_TRUNC for month bucketing, window function SUM() OVER (ORDER BY ...) for cumulative total, CROSS JOIN, TO_CHAR for date formatting.

---

## Transactions Page (`/transactions`)

This is the most complex route in the app. It runs several queries to build the page.

---

### User's account list (filter dropdown)

```sql
SELECT account_id, name
FROM   Accounts
WHERE  user_id = %s
ORDER  BY name
```

**What it does:** Loads the list of accounts for the "Account" dropdown at the top of the page. If this returns empty, the page shows a "no accounts" message and skips all further queries.

---

### Tags visible on this account (filter dropdown)

```sql
SELECT DISTINCT tg.tag_id, tg.name
FROM Tags tg
JOIN TransactionTags tt ON tt.tag_id       = tg.tag_id
JOIN Transactions     t  ON t.transaction_id = tt.transaction_id
WHERE t.account_id = %s
   OR (t.counterparty_account_id = %s AND t.type = 'transfer')
ORDER BY tg.name
```

**What it does:** Populates the Tag filter dropdown with only the tags that are actually used by transactions visible on this account. If a tag has never been used on this account, it doesn't appear as a filter option.

**How it works:** Joins Tags → TransactionTags → Transactions to reach from a tag to the transactions it appears on. The WHERE clause uses an OR to handle both sides of a transfer: a transaction is "visible" on an account either if the account is the main account (`t.account_id = %s`) or if the account is the destination of a transfer (`t.counterparty_account_id = %s AND t.type = 'transfer'`). DISTINCT prevents the same tag from appearing twice if it is used on multiple transactions.

---

### Categories visible on this account (filter dropdown)

```sql
SELECT DISTINCT c.category_id, c.name
FROM Categories  c
JOIN Transactions t ON t.category_id = c.category_id
WHERE t.account_id = %s
   OR (t.counterparty_account_id = %s AND t.type = 'transfer')
ORDER BY c.name
```

**What it does:** Same logic as the tags query above, but for the Category filter dropdown. Only shows categories that are actually used by transactions on this account.

---

### All user categories (for edit modal)

```sql
SELECT category_id, name, type FROM Categories
WHERE user_id = %s ORDER BY type, name
```

**What it does:** Loads every category the user has defined, including its type (income/expense). Used to populate the category dropdown inside the Edit Transaction modal, where the user might want to change a transaction's category to anything they own — not just ones already used on this account.

---

### All user tags (for edit modal)

```sql
SELECT tag_id, name FROM Tags
WHERE user_id = %s ORDER BY name
```

**What it does:** Loads every tag the user owns. Used for the tag checkboxes in the Edit Transaction modal.

---

### Main ledger query (the big one)

This is the most complex query in the entire application. It is built dynamically — optional filter clauses (`{date_filter}`, `{tag_filter}`, `{category_filter}`) are injected as strings, and their parameter values are appended to the parameter tuple. The full version (no filters active) looks like this:

```sql
WITH ledger AS (

    -- Branch 1: transactions where this account is the main account
    -- (income, expense, and outgoing transfers)
    SELECT
        t.transaction_id,
        t.transaction_date,
        t.type,
        t.amount,
        t.description,
        CASE WHEN t.type = 'transfer'
             THEN 'To: ' || cp.name
             ELSE NULL
        END                                        AS transfer_label,
        FALSE                                      AS incoming,
        CASE t.type
            WHEN 'income'   THEN  t.amount
            WHEN 'expense'  THEN -t.amount
            WHEN 'transfer' THEN -t.amount
        END                                        AS signed_amount,
        c.name                                     AS category,
        t.category_id,
        t.account_id                               AS account_id_orig,
        t.counterparty_account_id,
        (SELECT STRING_AGG(tg.name, ', ' ORDER BY tg.name)
         FROM TransactionTags tt2
         JOIN Tags tg ON tg.tag_id = tt2.tag_id
         WHERE tt2.transaction_id = t.transaction_id) AS tag_names,
        (SELECT STRING_AGG(tt2.tag_id::text, ',' ORDER BY tg.name)
         FROM TransactionTags tt2
         JOIN Tags tg ON tg.tag_id = tt2.tag_id
         WHERE tt2.transaction_id = t.transaction_id) AS tag_ids_agg
    FROM Transactions t
    LEFT JOIN Accounts   cp ON cp.account_id = t.counterparty_account_id
    LEFT JOIN Categories c  ON c.category_id = t.category_id
    WHERE t.account_id = %s

    UNION ALL

    -- Branch 2: transfers where this account is the counterparty (destination)
    SELECT
        t.transaction_id,
        t.transaction_date,
        t.type,
        t.amount,
        t.description,
        'From: ' || src.name                       AS transfer_label,
        TRUE                                       AS incoming,
        t.amount                                   AS signed_amount,
        c.name                                     AS category,
        t.category_id,
        t.account_id                               AS account_id_orig,
        t.counterparty_account_id,
        (SELECT STRING_AGG(tg.name, ', ' ORDER BY tg.name)
         FROM TransactionTags tt2
         JOIN Tags tg ON tg.tag_id = tt2.tag_id
         WHERE tt2.transaction_id = t.transaction_id) AS tag_names,
        (SELECT STRING_AGG(tt2.tag_id::text, ',' ORDER BY tg.name)
         FROM TransactionTags tt2
         JOIN Tags tg ON tg.tag_id = tt2.tag_id
         WHERE tt2.transaction_id = t.transaction_id) AS tag_ids_agg
    FROM Transactions t
    JOIN Accounts     src ON src.account_id = t.account_id
    LEFT JOIN Categories c ON c.category_id = t.category_id
    WHERE t.counterparty_account_id = %s
      AND t.type = 'transfer'
)
SELECT
    l.transaction_id,
    l.transaction_date,
    l.type,
    l.amount,
    l.description,
    l.transfer_label,
    l.incoming,
    l.category,
    l.category_id,
    l.account_id_orig,
    l.counterparty_account_id,
    l.tag_names,
    l.tag_ids_agg,
    a.initial_balance + SUM(l.signed_amount)
        OVER (ORDER BY l.transaction_date, l.transaction_id) AS running_balance
FROM ledger l
CROSS JOIN (SELECT initial_balance FROM Accounts WHERE account_id = %s) a
ORDER BY l.transaction_date DESC, l.transaction_id DESC
```

**What it does:** Returns the complete transaction ledger for a selected account — every financial event that affects that account's balance — with a running balance column, category name, and comma-separated tag names per row. This is what you see in the big table on the Transactions page.

**Why it is complicated — the transfer visibility problem:**

Transfers in this system are stored as a single row: `account_id` holds the source, `counterparty_account_id` holds the destination. If you only query `WHERE t.account_id = %s`, you see the outgoing side (money leaving) but you miss transfers where money arrived into this account. To show the full picture, you need both legs.

**How it works — the UNION ALL:**

The CTE `ledger` has two branches combined with UNION ALL:

- **Branch 1** (`WHERE t.account_id = %s`): catches all transactions where this account is the main account — income, expense, and outgoing transfers. For outgoing transfers, `transfer_label` is set to "To: [destination name]" using a CASE expression and a LEFT JOIN to the counterparty account. `signed_amount` is negative for expenses and transfers (money leaving), positive for income.

- **Branch 2** (`WHERE t.counterparty_account_id = %s AND t.type = 'transfer'`): catches incoming transfers — transactions stored on another account that ended up sending money here. `transfer_label` is set to "From: [source name]". `incoming` is set to TRUE so the template knows to display this as a credit. `signed_amount` is positive (money arriving).

UNION ALL (not UNION) is used because we want all rows, including potential duplicates, and we don't want the deduplication overhead.

**Correlated subqueries for tags:**

`STRING_AGG` is used inside a correlated subquery to collect all tag names for each transaction into a single comma-separated string. This avoids the JOIN multiplicity problem: if you JOIN Transactions to TransactionTags directly, a transaction with 3 tags would appear 3 times. The subquery runs once per row and collapses all tags into one string. A second identical subquery does the same for tag IDs (used by the edit modal to know which checkboxes to pre-check).

**The window function for running balance:**

The outer SELECT computes the running balance using:
```sql
a.initial_balance + SUM(l.signed_amount) OVER (ORDER BY l.transaction_date, l.transaction_id)
```
The window function accumulates `signed_amount` in chronological order (and by `transaction_id` to break ties on same-day transactions). Adding the account's `initial_balance` — fetched via a CROSS JOIN to a single-row subquery — gives the actual dollar balance after each transaction. This entire computation happens in one SQL pass, not in Python.

**The ORDER BY direction:**

The outer query orders by `transaction_date DESC, transaction_id DESC` so the newest transactions appear at the top. The window function inside uses its own `ORDER BY` (ascending) which is separate from the final display order — the balance accumulates chronologically regardless of how the rows are displayed.

**Dynamic filters:**

When the user applies a date range, category, or tag filter, extra SQL fragments are appended to both UNION ALL branches before the query runs:

- Date filter: `AND t.transaction_date >= %s` and/or `AND t.transaction_date <= %s`
- Tag filter: `AND EXISTS (SELECT 1 FROM TransactionTags tt WHERE tt.transaction_id = t.transaction_id AND tt.tag_id = %s)` — uses EXISTS (not a JOIN) to avoid duplicating rows when a transaction has multiple tags
- Category filter: `AND t.category_id = %s`

The same filter is applied to both branches of the UNION ALL so both outgoing and incoming transfers respect the filter.

**SQL concepts used:** CTE (WITH clause), UNION ALL, correlated subqueries, STRING_AGG, CASE expression for signed amounts, window function SUM() OVER (ORDER BY ...) for running balance, CROSS JOIN, LEFT JOIN, EXISTS subquery for tag filtering, dynamic SQL construction.

---

## Spending Page (`/spending`)

---

### Category breakdown with percentages

```sql
SELECT
    c.name          AS category,
    SUM(t.amount)   AS category_total,
    ROUND(100.0 * SUM(t.amount) / SUM(SUM(t.amount)) OVER (), 2) AS percentage
FROM Transactions t
JOIN Accounts   a ON a.account_id  = t.account_id
JOIN Categories c ON c.category_id = t.category_id
WHERE a.user_id = %s
  AND t.type    = 'expense'
  -- optional: AND t.transaction_date >= %s / AND t.transaction_date <= %s
GROUP BY c.name
ORDER BY category_total DESC
```

**What it does:** Returns one row per expense category showing the total amount spent and what percentage of the user's total spending that category represents. This powers both the doughnut chart and the breakdown table.

**How it works:** The JOIN chain connects Transactions → Accounts (to check user ownership) → Categories (to get the category name). WHERE filters to expense transactions only and to the current user's accounts.

The interesting part is the percentage calculation. `SUM(t.amount)` inside GROUP BY gives each category's total. `SUM(SUM(t.amount)) OVER ()` is a window function with no OVER clause partitioning — it operates over the entire result set, giving the grand total of all categories. Dividing each category's total by the grand total and multiplying by 100 gives the percentage. The inner SUM is evaluated during GROUP BY aggregation; the outer SUM is the window function operating on those group-level subtotals. ROUND keeps it to two decimal places.

When a date filter is active, the same query runs with `AND t.transaction_date >= %s` and/or `AND t.transaction_date <= %s` appended.

**SQL concepts used:** Three-table JOIN, SUM aggregation with GROUP BY, window function SUM() OVER () for grand total percentage, ROUND.

---

### Top 5 spending categories

```sql
SELECT c.name AS category, SUM(t.amount) AS total_spent
FROM Transactions t
JOIN Accounts   a ON a.account_id  = t.account_id
JOIN Categories c ON c.category_id = t.category_id
WHERE a.user_id = %s
  AND t.type    = 'expense'
  AND DATE_TRUNC('month', t.transaction_date) = DATE_TRUNC('month', CURRENT_DATE)
  -- or: AND t.transaction_date >= %s / AND t.transaction_date <= %s
GROUP BY c.name
ORDER BY total_spent DESC
LIMIT 5
```

**What it does:** Returns the five expense categories with the highest total spending for the current month (or for the selected date range if a filter is active).

**How it works:** Same JOIN and aggregation pattern as the breakdown query. The default date restriction uses `DATE_TRUNC('month', t.transaction_date) = DATE_TRUNC('month', CURRENT_DATE)` to compare months rather than specific days — this matches any transaction in the current calendar month regardless of the exact date. LIMIT 5 keeps it to the top five. When a date filter is active, the DATE_TRUNC condition is replaced with explicit start/end date parameters.

**SQL concepts used:** DATE_TRUNC for current-month filtering, CURRENT_DATE, GROUP BY, ORDER BY DESC, LIMIT.

---

## Monthly Report (`/monthly`)

---

### Monthly income vs. expenses

```sql
SELECT
    EXTRACT(YEAR  FROM t.transaction_date)::int AS year,
    EXTRACT(MONTH FROM t.transaction_date)::int AS month,
    COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'income'),  0) AS total_income,
    COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'expense'), 0) AS total_expenses
FROM Transactions t
JOIN Accounts a ON a.account_id = t.account_id
WHERE a.user_id = %s
GROUP BY year, month
ORDER BY year, month
```

**What it does:** Returns one row per calendar month showing total income and total expenses side by side. This feeds both the grouped bar chart and the summary table on the Monthly page.

**How it works:** EXTRACT pulls the year and month out of the transaction date as numbers. The GROUP BY groups all transactions in the same year+month together.

The aggregation uses conditional aggregation with the FILTER clause: `SUM(t.amount) FILTER (WHERE t.type = 'income')` only sums the rows where the type is income; the other rows are ignored for that column. This produces two separate sums from a single pass over the data, avoiding the need for two separate queries or a self-join. COALESCE wraps each sum to turn NULL (no transactions of that type in that month) into 0.

The `::int` cast converts EXTRACT's NUMERIC result to a plain integer for cleaner output.

**SQL concepts used:** EXTRACT for year/month, conditional aggregation with FILTER, COALESCE, GROUP BY on derived columns.

---

## Insights Page (`/insights`)

---

### Accounts with negative balance

```sql
SELECT name AS account_name, type, current_balance
FROM   AccountBalances
WHERE  user_id = %s AND current_balance < 0
ORDER  BY current_balance
```

**What it does:** Finds any of the user's accounts where the computed balance has gone below zero. Results are ordered from the most negative balance upward so the worst situation appears first.

**How it works:** Reads directly from the `AccountBalances` view. The `current_balance < 0` filter does the work. ORDER BY current_balance ASC means the account furthest into the negative is at the top.

---

### Receipt coverage per account

```sql
SELECT
    a.name                                            AS account,
    COUNT(t.transaction_id)                           AS total,
    COUNT(r.receipt_id)                               AS with_receipt,
    COUNT(t.transaction_id) - COUNT(r.receipt_id)     AS without_receipt
FROM Accounts     a
JOIN Transactions t  ON t.account_id      = a.account_id
LEFT JOIN Receipts r ON r.transaction_id  = t.transaction_id
WHERE a.user_id = %s
GROUP BY a.account_id, a.name
ORDER BY a.name
```

**What it does:** For every account, shows how many transactions exist in total, how many have a receipt attached, and how many do not. This is used on the Insights page as a documentation audit.

**How it works:** The JOIN to Transactions is a regular (inner) JOIN — only accounts with at least one transaction appear. The JOIN to Receipts is a LEFT JOIN — so transactions without a receipt still appear (with NULL in the receipt columns). COUNT(t.transaction_id) counts all transactions; COUNT(r.receipt_id) counts only the rows where a receipt was found (COUNT ignores NULLs, so unmatched LEFT JOIN rows are not counted). Subtracting the two gives the "without receipt" number. GROUP BY is on both `account_id` and `name` — using the ID ensures accounts with the same name are not accidentally merged.

**SQL concepts used:** LEFT JOIN, COUNT with NULL handling, computed column from subtraction.

---

### Categories never used in a transaction

```sql
SELECT c.name, c.type
FROM   Categories c
WHERE  c.user_id = %s

EXCEPT

SELECT c.name, c.type
FROM   Categories  c
JOIN   Transactions t ON t.category_id = c.category_id
WHERE  c.user_id = %s

ORDER  BY type, name
```

**What it does:** Returns all categories the user created that have never been assigned to any transaction. Useful for spotting labels that were defined but forgotten.

**How it works:** Uses the EXCEPT set operator. The first SELECT returns all categories for the user. The second SELECT returns only categories that have at least one transaction (the JOIN to Transactions means only matched rows appear). EXCEPT subtracts: any (name, type) pair that appears in the second set is removed from the first. What remains is categories with no transactions at all. ORDER BY applies to the final combined result.

**SQL concepts used:** EXCEPT set operator, JOIN to filter by existence.

---

### Idle accounts (no transactions at all)

```sql
SELECT a.name AS account_name, a.type
FROM   Accounts a
WHERE  a.user_id = %s
  AND  NOT EXISTS (
      SELECT 1 FROM Transactions t
      WHERE  t.account_id = a.account_id
         OR  t.counterparty_account_id = a.account_id
  )
ORDER  BY a.name
```

**What it does:** Finds accounts that have no transaction history at all — not as the source and not as the destination of any transfer.

**How it works:** The outer query loops over every account owned by the user. For each account, the correlated subquery checks whether any transaction references it — either as the main account (`t.account_id`) or as the counterparty of a transfer (`t.counterparty_account_id`). The OR handles both directions so an account that only appears as a transfer destination is still recognized as active. NOT EXISTS returns true only when no such transaction exists, leaving only genuinely idle accounts.

Note: a simpler approach using a LEFT JOIN would miss the counterparty case (the same account appearing only as a transfer destination).

**SQL concepts used:** correlated NOT EXISTS subquery, OR condition inside the subquery.

---

## Manage Accounts (`/manage-accounts`)

---

### Account list with transaction count

```sql
SELECT a.account_id, a.name, a.type, a.initial_balance,
       COUNT(t.transaction_id) AS tx_count
FROM   Accounts a
LEFT JOIN Transactions t
       ON t.account_id = a.account_id
       OR t.counterparty_account_id = a.account_id
WHERE  a.user_id = %s
GROUP  BY a.account_id, a.name, a.type, a.initial_balance
ORDER  BY a.name
```

**What it does:** Loads all accounts with a transaction count. The count is used by the template to decide whether to show or grey out the Delete button — you cannot delete an account that has transactions.

**How it works:** LEFT JOIN to Transactions with an OR condition captures both outgoing and incoming transaction references. COUNT(t.transaction_id) counts matched rows (NULL from unmatched LEFT JOIN rows is not counted). GROUP BY must include all non-aggregated columns that appear in the SELECT.

---

### Duplicate check before inserting an account

```sql
SELECT 1 FROM Accounts WHERE user_id = %s AND LOWER(name) = LOWER(%s)
```

**What it does:** Checks whether an account with the same name (case-insensitive) already exists for this user before attempting an INSERT.

**How it works:** `LOWER()` on both sides makes the comparison case-insensitive — "Chase Checking" and "chase checking" are treated as the same name. `SELECT 1` is a common pattern for existence checks: we only care whether any row matches, not what the row contains, so returning the literal value 1 is the lightest possible payload.

---

### Insert a new account

```sql
INSERT INTO Accounts (user_id, name, type, initial_balance)
VALUES (%s, %s, %s, %s)
```

**What it does:** Creates a new account record. `created_at` is not listed because it has a DEFAULT of NOW() and is filled automatically by PostgreSQL.

---

### Transaction count check before deleting an account

```sql
SELECT a.name,
       COUNT(t.transaction_id) AS tx_count
FROM   Accounts a
LEFT JOIN Transactions t
       ON t.account_id = a.account_id
       OR t.counterparty_account_id = a.account_id
WHERE  a.account_id = %s AND a.user_id = %s
GROUP  BY a.name
```

**What it does:** Confirms the account belongs to this user, retrieves its name (for the flash message), and counts its transactions — all in one query. If `tx_count > 0` the delete is blocked.

---

### Delete an account

```sql
DELETE FROM Accounts WHERE account_id = %s AND user_id = %s
```

**What it does:** Removes the account. The `AND user_id = %s` condition is an ownership guard — even if someone guesses an account ID, they cannot delete an account they do not own.

---

## Manage Categories (`/manage-categories`)

---

### Category list with transaction count

```sql
SELECT c.category_id, c.name, c.type,
       COUNT(t.transaction_id) AS tx_count
FROM   Categories c
LEFT JOIN Transactions t ON t.category_id = c.category_id
WHERE  c.user_id = %s
GROUP  BY c.category_id, c.name, c.type
ORDER  BY c.type, c.name
```

**What it does:** Loads all user categories with a count of how many transactions use each one. Categories with `tx_count > 0` get a greyed-out Delete button in the UI.

**How it works:** LEFT JOIN captures categories with zero transactions (they still appear with tx_count = 0). ORDER BY type first groups income and expense categories together visually.

---

### Duplicate check before inserting a category

```sql
SELECT 1 FROM Categories
WHERE user_id = %s AND LOWER(name) = LOWER(%s)
```

Same pattern as the account duplicate check — case-insensitive name lookup within the user's own categories.

---

### Insert a new category

```sql
INSERT INTO Categories (user_id, name, type) VALUES (%s, %s, %s)
```

---

### Transaction count check before deleting a category

```sql
SELECT COUNT(t.transaction_id) AS tx_count
FROM   Categories c
LEFT JOIN Transactions t ON t.category_id = c.category_id
WHERE  c.category_id = %s AND c.user_id = %s
```

**What it does:** Checks how many transactions use this category. If the count is greater than zero, the delete is blocked with an error message. If no row is returned at all, the category does not exist or does not belong to this user.

---

### Delete a category

```sql
DELETE FROM Categories WHERE category_id = %s AND user_id = %s
```

The ownership guard `AND user_id = %s` is always included on all delete statements.

---

## Manage Tags (`/manage-tags`)

---

### Tag list with usage count

```sql
SELECT tg.tag_id, tg.name,
       COUNT(tt.transaction_id) AS tx_count
FROM   Tags tg
LEFT JOIN TransactionTags tt ON tt.tag_id = tg.tag_id
WHERE  tg.user_id = %s
GROUP  BY tg.tag_id, tg.name
ORDER  BY tg.name
```

**What it does:** Loads all tags with a count of how many transactions they have been applied to. Unlike categories, tags can always be deleted (the delete button is never greyed out) — the count is shown purely for information.

**How it works:** LEFT JOIN to TransactionTags so tags with zero uses still appear. COUNT(tt.transaction_id) counts junction rows, which is the usage count.

---

### Duplicate check before inserting a tag

```sql
SELECT 1 FROM Tags WHERE user_id = %s AND LOWER(name) = LOWER(%s)
```

---

### Insert a new tag

```sql
INSERT INTO Tags (user_id, name) VALUES (%s, %s)
```

---

### Delete a tag

```sql
DELETE FROM Tags WHERE tag_id = %s AND user_id = %s
```

**What it does:** Removes the tag. Because `TransactionTags` has `ON DELETE CASCADE` on the `tag_id` foreign key, PostgreSQL automatically removes all rows in `TransactionTags` that reference this tag. No separate cleanup query is needed.

---

## Add Transaction (`/add-transaction`)

---

### Load accounts, categories, and tags for the form

Three separate queries populate the form dropdowns:

```sql
SELECT account_id, name FROM Accounts WHERE user_id = %s ORDER BY name
```
```sql
SELECT category_id, name, type FROM Categories WHERE user_id = %s ORDER BY type, name
```
```sql
SELECT tag_id, name FROM Tags WHERE user_id = %s ORDER BY name
```

All three are simple filtered SELECTs. The `type` column is fetched for categories so the JavaScript can filter the dropdown to show only income or expense categories depending on the transaction type the user selects.

---

### Ownership check before inserting

```sql
SELECT 1 FROM Accounts WHERE account_id = %s AND user_id = %s
```

**What it does:** Verifies that the account the user submitted in the form actually belongs to them. This prevents a malicious actor from forging a form POST with someone else's `account_id`.

---

### Insert a new transaction

```sql
INSERT INTO Transactions
    (account_id, type, amount, transaction_date, description,
     category_id, counterparty_account_id)
VALUES (%s, %s, %s, %s, %s, %s, %s)
RETURNING transaction_id
```

**What it does:** Creates the transaction record. `RETURNING transaction_id` asks PostgreSQL to send back the newly generated primary key in the same round-trip, without a separate SELECT. This ID is needed immediately to insert the transaction's tags.

---

### Insert transaction tags (one per selected tag)

```sql
INSERT INTO TransactionTags (transaction_id, tag_id)
VALUES (%s, %s) ON CONFLICT DO NOTHING
```

**What it does:** Links each selected tag to the new transaction. This runs in a loop — once per tag the user checked. `ON CONFLICT DO NOTHING` is a safety net: if the same (transaction_id, tag_id) pair somehow gets submitted twice, the second INSERT is silently ignored instead of raising an error.

---

## Edit Transaction (`/edit-transaction/<id>`)

---

### Ownership check before updating

```sql
SELECT 1 FROM Transactions t
JOIN Accounts a ON a.account_id = t.account_id
WHERE t.transaction_id = %s AND a.user_id = %s
```

**What it does:** Confirms that this transaction exists and belongs to the current user before allowing any modifications. The JOIN to Accounts is needed because Transactions does not store `user_id` directly — ownership is inferred through the account.

---

### Update the transaction

```sql
UPDATE Transactions
SET account_id              = %s,
    type                    = %s,
    amount                  = %s,
    transaction_date        = %s,
    description             = %s,
    category_id             = %s,
    counterparty_account_id = %s
WHERE transaction_id = %s
```

**What it does:** Overwrites all editable fields on the transaction in one statement. All seven columns are always updated (even unchanged ones) which keeps the logic simple — no need to build a partial SET clause dynamically.

---

### Wipe and re-save tags

```sql
DELETE FROM TransactionTags WHERE transaction_id = %s
```
Then for each selected tag:
```sql
INSERT INTO TransactionTags (transaction_id, tag_id) VALUES (%s, %s) ON CONFLICT DO NOTHING
```

**What it does:** Replaces the transaction's tag assignments. Instead of computing a diff (which tags were added, which were removed), the app deletes all existing tag links and inserts the new set from scratch. This is simpler and always correct.

---

## Delete Transaction (`/delete-transaction/<id>`)

---

### Ownership check before deleting

```sql
SELECT t.transaction_id FROM Transactions t
JOIN Accounts a ON a.account_id = t.account_id
WHERE t.transaction_id = %s AND a.user_id = %s
```

Same pattern as the edit ownership check — verify the transaction exists and belongs to the user.

---

### Delete the transaction

```sql
DELETE FROM Transactions WHERE transaction_id = %s
```

**What it does:** Removes the transaction. Because `TransactionTags` has `ON DELETE CASCADE` on `transaction_id`, all tag links for this transaction are automatically removed by PostgreSQL. No separate cleanup is needed.

# ExpenseTrack — Bulk Info for Report & Presentation
## CIS 761 — Matin Marjani

---

# PART 1 — DATABASE

---

## 1. Application Overview and Target Users

### What the system does

ExpenseTrack is a personal finance management web application. It allows users to record all of their financial activity — income they receive, expenses they pay, and transfers between their own accounts — across multiple bank accounts, credit cards, and cash wallets. Every transaction can be classified with a category and labelled with one or more tags so the user can later filter and report on their spending. The system also stores references to receipt files so users can attach documentation to transactions.

Beyond storing raw data, the system provides several analytical views:

- A **dashboard** that shows live account balances and a net worth trend over time
- A **transaction ledger** per account with a running balance and date/category/tag filters
- A **spending breakdown** showing how much was spent in each expense category, with percentage shares, presented as a doughnut chart and a table
- A **monthly income vs. expenses report** shown as a grouped bar chart and a summary table
- An **insights page** that surfaces useful anomalies: overdrawn accounts, accounts with no transactions, unused categories, and receipt coverage statistics

### Target users

The system is designed for **individual users** who want to track personal finances across more than one account. The typical user has a checking account, a savings account, and perhaps a credit card or a cash wallet, and wants to understand where their money is going month by month. They are not accountants — they need a simple, readable interface, not spreadsheet-level complexity.

### Why a relational database fits this problem

The data has multiple clearly related entities (users, accounts, transactions, categories, tags, receipts) with strict integrity rules — a transaction must belong to an account that belongs to a user; a category assigned to a transaction must match the transaction's type; a transfer must reference two accounts owned by the same person. These cross-table rules are exactly what a relational database with foreign keys, check constraints, and triggers is designed to enforce. A relational model also makes the reporting queries natural: aggregations by category, running balances with window functions, and monthly summaries with GROUP BY are all standard SQL.

---

## 2. E/R Diagram Notes

The E/R diagram from the proposal (hand-drawn, page 9 of the PDF) is structurally correct. For the final report, it should be redrawn digitally. Here is the exact content to include:

### Entities and their key attributes

| Entity | Primary Key | Other attributes |
|---|---|---|
| User | user_id | email, username, password_hash, full_name, created_at |
| Account | account_id | user_id (FK), name, type, initial_balance, created_at |
| Category | category_id | user_id (FK), name, type |
| Tag | tag_id | user_id (FK), name |
| Transaction | transaction_id | account_id (FK), counterparty_account_id (FK, nullable), category_id (FK, nullable), type, amount, transaction_date, entry_date, description |
| Receipt | receipt_id | transaction_id (FK, unique), file_name, file_type, storage_location, uploaded_at |
| TransactionTags | (transaction_id, tag_id) | composite PK, both are FKs |

### Relationships

| Relationship | Entities | Multiplicity | Notes |
|---|---|---|---|
| Owns | User — Account | 1 : N | User partial, Account total |
| Defines | User — Category | 1 : N | User partial, Category total |
| Creates | User — Tag | 1 : N | User partial, Tag total |
| Records | Account — Transaction | 1 : N | Account partial, Transaction total |
| Counterparty | Account — Transaction | 1 : N | Only for transfer transactions; both sides must be the same user |
| Classifies | Category — Transaction | 1 : N | Both partial; category type must match transaction type |
| TaggedWith | Transaction — Tag | M : N | Both partial; implemented via TransactionTags junction table |
| HasReceipt | Transaction — Receipt | 1 : 1 | Transaction partial, Receipt total |

---

## 3. Relational Schema

```
Users(user_id, email, username, password_hash, full_name, created_at)
  PK: user_id
  Unique: email, username

Accounts(account_id, user_id, name, type, initial_balance, created_at)
  PK: account_id
  FK: user_id → Users(user_id)  ON DELETE CASCADE
  Unique: (user_id, name)

Categories(category_id, user_id, name, type)
  PK: category_id
  FK: user_id → Users(user_id)  ON DELETE CASCADE
  Unique: (user_id, name)
  Check: type ∈ {income, expense}

Tags(tag_id, user_id, name)
  PK: tag_id
  FK: user_id → Users(user_id)  ON DELETE CASCADE
  Unique: (user_id, name)

Transactions(transaction_id, account_id, counterparty_account_id,
             category_id, type, amount, transaction_date, entry_date, description)
  PK: transaction_id
  FK: account_id → Accounts(account_id)
  FK: counterparty_account_id → Accounts(account_id)  nullable
  FK: category_id → Categories(category_id)  ON DELETE SET NULL, nullable
  Check: amount > 0
  Check: counterparty_account_id ≠ account_id
  Check: type = 'transfer'  → counterparty_account_id IS NOT NULL AND category_id IS NULL
  Check: type ∈ {'income','expense'}  → counterparty_account_id IS NULL

Receipts(receipt_id, transaction_id, file_name, file_type, storage_location, uploaded_at)
  PK: receipt_id
  FK: transaction_id → Transactions(transaction_id)  ON DELETE CASCADE
  Unique: transaction_id  (enforces the 1-to-1 relationship)

TransactionTags(transaction_id, tag_id)
  PK: (transaction_id, tag_id)
  FK: transaction_id → Transactions(transaction_id)  ON DELETE CASCADE
  FK: tag_id → Tags(tag_id)  ON DELETE CASCADE
```

---

## 4. CREATE TABLE Statements — Description

The schema file (`sql/table.sql`) creates the database structure in the following order.

### ENUM types

Before creating any table, four custom enumerated types are defined:

- **account_type**: `checking`, `savings`, `cash`, `credit_card` — the only legal values for an account's type column. Using an ENUM instead of a plain VARCHAR prevents misspellings and invalid values at the database level, with no extra CHECK constraint needed.
- **category_type**: `income`, `expense` — a category can only be one of these two. This pairs with the transaction type rules.
- **transaction_type**: `income`, `expense`, `transfer` — the three kinds of financial events the system records.
- **receipt_file_type**: `pdf`, `jpg`, `png` — limits what kinds of files can be attached to a receipt record.

### Users table

Stores one row per person using the system. `email` and `username` each have a UNIQUE constraint, making them alternate keys — either one can identify a user. `password_hash` stores a hashed password (the app does not store plaintext). `created_at` defaults to the current timestamp so it is filled automatically on insert.

### Accounts table

Each account belongs to exactly one user via `user_id`. The `type` column uses the `account_type` ENUM. `initial_balance` stores the account's balance at the time it was created (not a running total — the current balance is always computed from transactions). The composite unique constraint `(user_id, name)` prevents a user from having two accounts with the same name, but two different users can have an account named "Chase Checking."

When a user is deleted, all their accounts cascade-delete automatically.

### Categories table

Per-user classification labels for income and expense transactions. The `type` column (ENUM `category_type`) tells the system whether this category applies to income or expense transactions. The `(user_id, name)` uniqueness constraint prevents duplicate category names per user.

### Tags table

Per-user freeform labels. Unlike categories, tags have no type — they can be attached to any transaction regardless of its type. The structure is intentionally minimal: just an owner and a name.

### Transactions table

The central table. Each row records one financial event. Key design decisions:

- **amount is always positive.** The direction of money is encoded by the `type` column, not by the sign of the amount. This avoids ambiguity and simplifies aggregation queries.
- **Transfers use a single row.** A transfer from Account A to Account B is stored as one row with `account_id = A` (the source) and `counterparty_account_id = B` (the destination). This avoids a duplicate "mirror" row and keeps the data model clean. The `AccountBalances` view handles reading both sides correctly.
- **Three structural CHECK constraints** enforce the rules that cannot be expressed as simple column constraints:
  1. Amount must be strictly positive.
  2. A transfer's counterparty cannot be the same as its main account.
  3. Transfers must have a counterparty and cannot have a category; income/expense transactions cannot have a counterparty.
- **category_id uses ON DELETE SET NULL.** If a category is deleted, existing transactions lose their category assignment rather than being deleted — which preserves the transaction history.

### Receipts table

Attached file references for transactions. The UNIQUE constraint on `transaction_id` enforces the 1-to-1 relationship: there is at most one receipt per transaction. When a transaction is deleted, its receipt cascades automatically.

### TransactionTags table

A junction/bridge table implementing the many-to-many relationship between transactions and tags. Both foreign keys cascade on delete: if a transaction is deleted, its tag links are removed; if a tag is deleted, it is automatically unlinked from all transactions.

### Indexes

Eight indexes are created beyond the primary keys (which are automatically indexed by PostgreSQL):

```
idx_accounts_user           ON Accounts(user_id)
idx_categories_user         ON Categories(user_id)
idx_tags_user               ON Tags(user_id)
idx_transactions_account    ON Transactions(account_id)
idx_transactions_date       ON Transactions(transaction_date)
idx_transactions_category   ON Transactions(category_id)
idx_transactions_counterparty ON Transactions(counterparty_account_id)
idx_transactiontags_tag     ON TransactionTags(tag_id)
```

The most important ones for query performance are `idx_transactions_account` and `idx_transactions_date`, which together speed up the ledger query (which always filters by account and optionally by date range). `idx_transactions_category` helps the spending breakdown query. `idx_transactiontags_tag` speeds up lookups from a tag to all its transactions.

### AccountBalances VIEW

The `AccountBalances` view computes the live current balance of every account without storing it. The formula is:

```
current_balance = initial_balance
                + SUM of income amounts on this account
                - SUM of expense amounts on this account
                - SUM of outgoing transfer amounts (where account_id = this account)
                + SUM of incoming transfer amounts (where counterparty_account_id = this account)
```

Because a single transfer row represents money moving between two accounts, the view uses a `UNION ALL` internally: the first branch collects all transactions by their main account (income, expense, and outgoing transfer), and the second branch collects the incoming side of every transfer by matching `counterparty_account_id`. Both branches are then joined back to the Accounts table and summed.

---

## 5. Constraints and Triggers

### Why triggers were needed

Some business rules span multiple tables and cannot be expressed as a single CHECK constraint, because a CHECK constraint can only examine columns in the same row of the same table. Four such rules require triggers.

---

### Trigger 1 — Category type must match transaction type

**Rule:** If a transaction is an income transaction, its category must be of type `income`. If it is an expense transaction, the category must be of type `expense`.

**Why a CHECK constraint cannot do this:** The category type lives in the `Categories` table, not in the `Transactions` table. A CHECK constraint on `Transactions` cannot reach into another table.

**Implementation:** A `BEFORE INSERT OR UPDATE` trigger on `Transactions`. When a new transaction is inserted or an existing one is updated, the trigger reads the `type` column of the assigned category from the `Categories` table and compares it to the transaction's type. If they do not match, the operation is rejected with an error.

**Example violation caught:** Inserting an expense transaction and assigning it the "Salary" category (which is an income category) would be blocked.

---

### Trigger 2 — Category must belong to the same user as the transaction's account

**Rule:** A user cannot use another user's categories. The category assigned to a transaction must be owned by the same user who owns the transaction's account.

**Why a CHECK constraint cannot do this:** This requires looking up the `user_id` on the `Accounts` table and comparing it to the `user_id` on the `Categories` table — two separate tables, neither of which is `Transactions`.

**Implementation:** A `BEFORE INSERT OR UPDATE` trigger on `Transactions`. It looks up the `user_id` of the account referenced by `account_id`, then looks up the `user_id` of the category referenced by `category_id`, and rejects the operation if they differ.

---

### Trigger 3 — Tag must belong to the same user as the transaction's account

**Rule:** A user cannot tag a transaction with another user's tags.

**Why a CHECK constraint cannot do this:** The `TransactionTags` table only stores two IDs — `transaction_id` and `tag_id`. Verifying ownership requires joining to both `Transactions → Accounts` (to get the account's owner) and to `Tags` (to get the tag's owner).

**Implementation:** A `BEFORE INSERT OR UPDATE` trigger on `TransactionTags`. When a tag is attached to a transaction, the trigger traces the transaction back to its account and then to the account's user, then checks whether that user matches the tag's `user_id`.

---

### Trigger 4 — Transfer counterparty must belong to the same user

**Rule:** For transfer transactions, both the source account (`account_id`) and the destination account (`counterparty_account_id`) must be owned by the same user. A user cannot transfer money to or from another user's account.

**Why a CHECK constraint cannot do this:** Both account IDs are in the `Transactions` table, but the `user_id` of each account lives in the `Accounts` table. A CHECK constraint cannot reach into a foreign table.

**Implementation:** A `BEFORE INSERT OR UPDATE` trigger on `Transactions`. When `counterparty_account_id` is not NULL, the trigger looks up the `user_id` of both accounts and rejects the operation if they differ.

---

## 6. Seed Data

The database is populated with realistic sample data representing three fictional users — Alice, Bob, and Carol — each with multiple accounts, categories, tags, and transactions covering roughly two years of financial activity (193 transactions total).

The seed data was generated with the help of AI. The process was: we first wrote a small set of realistic sample transactions by hand to establish the style and patterns (salary every month, regular recurring expenses like rent and utilities, occasional larger purchases, periodic transfers to savings). We then provided these examples to an AI assistant and asked it to generate a much larger dataset following the same patterns, spanning more months and including more variety in categories and tags. The output was reviewed to make sure amounts, dates, and descriptions were plausible, and then formatted as SQL `INSERT` statements in `sql/records.sql`.

The seed data covers:
- 3 users with 10 accounts in total
- Expense categories: Groceries, Rent, Utilities, Transportation, Dining, Entertainment, Healthcare, Shopping, Education
- Income categories: Salary, Freelance, Investment, Refund
- Tags: recurring, work, tax-deductible, personal, vacation, essential
- 193 transactions including income, expenses, and transfers between accounts
- 8 receipt records

---

---

# PART 2 — APPLICATION ARCHITECTURE AND QUERIES

---

## 7. Application Architecture

### Technology stack

| Component | Tool | Version | Why it was chosen |
|---|---|---|---|
| Database | PostgreSQL | 16 | Full SQL support: window functions, CTEs, triggers, ENUMs, views. Much more capable than SQLite for this kind of project. |
| Backend | Python + Flask | 3.x / 3.x | Lightweight web framework. No boilerplate. Good fit for a single-developer project where you want full control over SQL rather than using an ORM. |
| DB driver | psycopg2 | 2.x | The standard Python adapter for PostgreSQL. Used directly — no ORM layer — so every query is visible and controllable. |
| Frontend | Bootstrap 5 | 5.3 | Responsive layout and ready-made components (tables, cards, modals, dropdowns, badges) without writing custom CSS. |
| Charts | Chart.js | 4.4 | Client-side charting library. No backend dependency — the server sends data as JSON and Chart.js renders it in the browser. |

### Folder structure

```
ExpenseTrack/
├── app/
│   ├── app.py              ← all Flask routes and business logic
│   ├── db.py               ← database connection and query helpers
│   └── templates/
│       ├── base.html           ← shared layout (navbar, flash messages, CDN scripts)
│       ├── dashboard.html
│       ├── transactions.html
│       ├── spending.html
│       ├── monthly.html
│       ├── insights.html
│       ├── add_transaction.html
│       ├── manage_accounts.html
│       ├── manage_categories.html
│       └── manage_tags.html
└── sql/
    ├── table.sql           ← schema: tables, ENUMs, indexes, view
    ├── triggers.sql        ← four trigger functions
    ├── records.sql         ← seed data (3 users, 193 transactions)
    └── queries/            ← standalone versions of all 15 queries (Q1–Q15)
```

### Database helper layer (db.py)

The application accesses the database through two simple functions:

**`query(sql, params)`** — opens a connection, executes a SELECT, and returns all rows as a list of Python dictionaries (using `RealDictCursor`). Every read operation in the app calls this function.

**`execute(sql, params)`** — opens a connection, executes an INSERT, UPDATE, or DELETE, commits the transaction, and closes the connection. If the statement has a `RETURNING` clause, it returns the resulting rows. Every write operation in the app calls this function.

There is no connection pool — each call opens and closes a fresh connection. This is fine for a demo application; a production system would use a pool.

### Route overview

| URL | Method | Page / Action | Key query concept used |
|---|---|---|---|
| `/` | GET | Dashboard | AccountBalances view, net worth trend CTE with window function |
| `/transactions` | GET | Transaction ledger | UNION ALL CTE, window function running balance, STRING_AGG for tags |
| `/spending` | GET | Spending breakdown | SUM with window function for percentages |
| `/monthly` | GET | Monthly report | EXTRACT, conditional aggregation with FILTER |
| `/insights` | GET | Insights | NOT EXISTS, LEFT JOIN, EXCEPT set operator |
| `/add-transaction` | GET/POST | Add transaction form | INSERT with RETURNING, INSERT into TransactionTags |
| `/edit-transaction/<id>` | POST | Edit transaction | UPDATE, DELETE + re-INSERT TransactionTags |
| `/delete-transaction/<id>` | POST | Delete transaction | DELETE with ownership check |
| `/manage-accounts` | GET | Account list + add form | COUNT with LEFT JOIN |
| `/add-account` | POST | Add account | INSERT into Accounts |
| `/delete-account/<id>` | POST | Delete account | DELETE, blocked if tx_count > 0 |
| `/manage-categories` | GET | Category list + add form | COUNT with LEFT JOIN |
| `/add-category` | POST | Add category | INSERT into Categories |
| `/delete-category/<id>` | POST | Delete category | DELETE, blocked if tx_count > 0 |
| `/manage-tags` | GET | Tag list + add form | COUNT with LEFT JOIN |
| `/add-tag` | POST | Add tag | INSERT into Tags |
| `/delete-tag/<id>` | POST | Delete tag | DELETE, cascades in TransactionTags |

### POST → Redirect → GET pattern

All write routes follow this pattern: the form submits via POST, the route performs the database write, then redirects to a GET route. This means refreshing the browser after a form submission does not re-submit the form. Flash messages (success / warning / error) carry feedback across the redirect and are displayed at the top of the next page.

### Template inheritance

All pages extend `base.html`, which provides the navbar, user switcher dropdown, flash message display, Bootstrap CSS, and the Chart.js CDN script. Child pages fill in two blocks:
- `{% block content %}` — the page body
- `{% block scripts %}` — chart initialization code, placed after the Chart.js script tag so the library is always loaded first

---

## 8. The 15 Queries — What They Do and What They Demonstrate

### Q1 — Total spending per category
Groups all expense transactions by category and sums the amounts. Ordered from highest to lowest so the user sees their biggest spending areas first.
**Demonstrates:** JOIN across three tables, GROUP BY, SUM, ORDER BY.

### Q2 — Monthly income vs. expense summary (REPORT)
Shows every month on record with total income and total expenses side by side. One row per calendar month.
**Demonstrates:** EXTRACT for year/month bucketing, conditional aggregation using `FILTER (WHERE ...)`.

### Q3 — Current balance of every account
Reads directly from the `AccountBalances` view. Returns the live computed balance for all accounts belonging to a user.
**Demonstrates:** querying a VIEW instead of a base table.

### Q4 — Top 5 spending categories this month
Same as Q1 but limited to the current calendar month, using DATE_TRUNC to bucket by month.
**Demonstrates:** DATE_TRUNC for current-month filtering, LIMIT.

### Q5 — Transactions with a specific tag
Retrieves all transactions tagged with a given tag name by joining through the `TransactionTags` junction table.
**Demonstrates:** multi-table JOIN through a bridge/junction table.

### Q6 — Accounts in negative balance
Uses the `AccountBalances` view with a WHERE filter to find any account where the computed balance is below zero.
**Demonstrates:** filtering a VIEW result.

### Q7 — Accounts with no transactions
Finds accounts that have never had any transaction recorded, using a correlated NOT EXISTS subquery.
**Demonstrates:** correlated subquery with NOT EXISTS.

### Q8 — Months where income exceeded expenses
Builds a monthly summary in a CTE (WITH clause), then filters it to keep only months where income was greater than expenses.
**Demonstrates:** CTE (WITH clause), filtering on aggregated values after grouping.

### Q9 — Running balance over time for an account (REPORT)
The full ledger for a single account, one row per transaction, with a running balance column showing the account balance after each entry.
**Demonstrates:** window function `SUM() OVER (ORDER BY ...)` for cumulative totals.

### Q10 — Spending breakdown with percentages (REPORT)
Lists all expense categories with their total and their percentage share of overall spending. The percentage is computed by dividing each category total by the grand total using a window function.
**Demonstrates:** `SUM() OVER ()` (no ORDER BY, full partition) to compute a denominator for percentage calculation.

### Q11 — Receipt coverage per account (REPORT)
For every account, shows how many transactions have a receipt attached and how many do not. Useful for auditing documentation.
**Demonstrates:** LEFT JOIN to detect missing related rows, COUNT with and without NULL values.

### Q12 — Most-used tags
Ranks all tags by how many transactions they have been applied to. Top 10.
**Demonstrates:** JOIN, COUNT, GROUP BY, ORDER BY DESC, LIMIT.

### Q13 — Users with more than one account type
Finds users who have diversified across account types (e.g., both checking and savings).
**Demonstrates:** COUNT(DISTINCT …), GROUP BY, HAVING.

### Q14 — Net worth across all users (REPORT)
A system-wide summary: one row per user, showing their total net worth (sum of current balances across all accounts). Computed by aggregating the `AccountBalances` view.
**Demonstrates:** aggregating over a VIEW, GROUP BY, SUM.

### Q15 — Unused categories
Finds categories the user defined but never used on any transaction. Uses the EXCEPT set operator: start with all user categories, subtract those that appear on at least one transaction.
**Demonstrates:** EXCEPT set operator.

---

## 9. Key Implementation Details Worth Mentioning

### Transfer design choice
A transfer between Account A and Account B is stored as a single row in the Transactions table, not two rows. `account_id` holds the source account and `counterparty_account_id` holds the destination. This means the same transaction record appears in the ledger of both accounts — the app uses a UNION ALL query to show it from both perspectives with the correct "Transfer Out" / "Transfer In" labels. This avoids data duplication and keeps the balance computation clean.

### Running balance with a window function
The transaction ledger computes the balance after each transaction using a SQL window function:
```sql
initial_balance + SUM(signed_amount) OVER (ORDER BY transaction_date, transaction_id)
```
This means the database does the accumulation in a single pass rather than the application doing it row by row in Python. The `Balance After` column is hidden when any filter is active because filtering would break the chain and show misleading partial balances.

### Dynamic category filtering in the UI
The Add Transaction and Edit Transaction forms use a JavaScript function (`onTypeChange`) that shows or hides the category dropdown vs. the counterparty account dropdown depending on the selected transaction type, and also filters the category options to only show income or expense categories matching the current type. This prevents the user from making a type/category mismatch before it even reaches the database.

### Cascade rules
- Deleting a user cascades to all their accounts, categories, and tags.
- Deleting a tag cascades to all TransactionTags rows — so deleting a tag is always safe.
- Deleting a category sets `category_id = NULL` on related transactions (ON DELETE SET NULL) — the transaction history is preserved.
- Deleting an account or category is blocked in the UI if any transactions reference them (the app checks the count first and shows an error).

### No authentication
The current implementation has no login system. The "Viewing as" dropdown in the navbar selects the active user by their `user_id` parameter in the URL. This is intentional for a class demo — it makes switching between users easy during the presentation. In a real application, each user would log in and the session would determine which user's data is shown.

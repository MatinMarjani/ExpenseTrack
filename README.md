# ExpenseTrack

A personal expense tracking web application built as the course project for CIS 761.
Users can track income, expenses, and transfers across multiple accounts, organize
transactions with categories and tags, and view spending summaries and trends over time.

---

## 1. Project Overview

ExpenseTrack lets a user manage their personal finances through a simple web interface.
The core idea is that every user has one or more accounts (checking, savings, cash,
credit card), and every dollar movement is recorded as a transaction on one of those
accounts. Transactions can be labeled with a category (like "Groceries" or "Salary")
and optional tags (like "Recurring" or "Work") to make filtering and reporting easier.

**Tech stack:**

| Layer | Tool |
|---|---|
| Backend | Python 3, Flask |
| Database | PostgreSQL 16 |
| DB driver | psycopg2 |
| Frontend | Bootstrap 5, Chart.js 4.4 |

**Pages / features:**

- **Dashboard** — account balances at a glance, net worth card, and a month-by-month net worth trend chart
- **Transactions** — full ledger for a selected account with date, category, and tag filters; running balance column
- **Spending** — category-level expense breakdown with a doughnut chart and a top-5 table
- **Monthly** — income vs. expenses per month shown as a grouped bar chart and a summary table
- **Insights** — negative-balance accounts, receipt coverage per account, unused categories, idle accounts
- **Manage** — add transactions, add/delete categories, add/delete tags

---

## 2. Database

### Tables

The database has seven tables:

- **Users** — stores each user's email, username, hashed password, and full name.

- **Accounts** — each account belongs to one user and has a type (`checking`, `savings`, `cash`, or `credit_card`) plus an initial balance recorded at account creation.

- **Categories** — user-defined labels for income or expense transactions. A category has a type (`income` or `expense`) that must match the transaction it is assigned to. Categories are per-user, so one user's categories are invisible to other users.

- **Tags** — freeform labels a user can attach to any transaction. Unlike categories, tags are optional and can be mixed freely (a transaction can have multiple tags). Tags are also per-user.

- **Transactions** — the central table. Each row records one financial event: the account it belongs to, the type (`income`, `expense`, or `transfer`), the amount (always stored as a positive number), the date, an optional description, and an optional category. Transfers also store a `counterparty_account_id` pointing to the destination account. Structural rules enforced by `CHECK` constraints:
  - Amount must be positive; direction is captured by type, not sign.
  - Transfers must have a counterparty and cannot have a category.
  - Income and expense transactions cannot have a counterparty.

- **Receipts** — optionally attached to a transaction (one per transaction). Stores a file name, file type (pdf, jpg, or png), and a storage path.

- **TransactionTags** — a junction table connecting transactions to tags. One transaction can have many tags.

### View: AccountBalances

`AccountBalances` computes the live current balance for every account without storing it. The formula is:

```
current_balance = initial_balance
                + SUM of income amounts
                - SUM of expense amounts
                - SUM of outgoing transfer amounts
                + SUM of incoming transfer amounts
```

Because a single transfer row in the Transactions table moves money between two accounts, the view uses a `UNION ALL` internally to count the same transfer row twice — once as a deduction from the source account and once as a credit to the destination account.

### Triggers

Four triggers enforce business rules that cannot be expressed as simple `CHECK` constraints because they need to look across multiple tables:

1. **Category type must match transaction type.** If a transaction is tagged as income, its category must also be of type `income`, and vice versa for expenses. This prevents accidentally assigning a "Salary" category to an expense.

2. **Category must belong to the same user.** A user cannot use a category that belongs to a different user. The trigger checks that the category's owner matches the owner of the transaction's account.

3. **Tag must belong to the same user.** Same idea as the category rule, but applied when a tag is attached to a transaction via the `TransactionTags` table.

4. **Transfer counterparty must belong to the same user.** When recording a transfer, both the source and destination accounts must be owned by the same user. This prevents cross-user transfers.

---

## 3. How the App Works

### Folder structure

```
ExpenseTrack/
├── app/
│   ├── app.py          # all routes
│   ├── db.py           # database connection helpers
│   └── templates/
│       ├── base.html               # shared layout (navbar, flash messages, Chart.js)
│       ├── dashboard.html
│       ├── transactions.html
│       ├── spending.html
│       ├── monthly.html
│       ├── insights.html
│       ├── add_transaction.html
│       ├── manage_categories.html
│       └── manage_tags.html
└── sql/
    ├── table.sql       # schema (tables, enums, indexes, view)
    ├── triggers.sql    # the four triggers
    └── records.sql     # seed data (3 users, ~10 accounts, 190+ transactions)
```

### Database helpers (`db.py`)

There are two functions:

- `query(sql, params)` — runs a `SELECT` and returns all rows as a list of dictionaries. Used everywhere data is read.
- `execute(sql, params)` — runs an `INSERT`, `UPDATE`, or `DELETE`, commits the transaction, and returns any rows from a `RETURNING` clause. Used for all write operations.

Both open a fresh connection, run the query, and close the connection. No connection pool is used since the app is a small single-user demo.

### Routes (`app.py`)

| URL | Method | What it does |
|---|---|---|
| `/` | GET | Dashboard — account balances + net worth trend |
| `/transactions` | GET | Transaction ledger with filters |
| `/spending` | GET | Spending breakdown by category |
| `/monthly` | GET | Monthly income vs. expenses |
| `/insights` | GET | Anomalies and coverage stats |
| `/add-transaction` | GET / POST | Form to add a new transaction |
| `/delete-transaction/<id>` | POST | Delete a transaction by ID |
| `/manage-categories` | GET | List categories + add form |
| `/add-category` | POST | Insert a new category |
| `/delete-category/<id>` | POST | Delete a category (blocked if in use) |
| `/manage-tags` | GET | List tags + add form |
| `/add-tag` | POST | Insert a new tag |
| `/delete-tag/<id>` | POST | Delete a tag (always allowed; junction rows cascade) |

All write routes follow the **POST → redirect → GET** pattern so that refreshing the page after a form submission does not re-submit the form. Flash messages (success / warning / error) are displayed at the top of the next page.

### Templates

All pages extend `base.html`, which provides the navbar, the user switcher dropdown, flash message display, Bootstrap CSS, and Chart.js. Child pages fill in a `{% block content %}` section for the page body and an optional `{% block scripts %}` section for any chart initialization code. Putting chart scripts in `{% block scripts %}` (which sits after the Chart.js CDN tag) ensures Chart.js is loaded before the chart code runs.

---

## 4. How to Use the App

### Prerequisites

- Python 3.10 or later
- PostgreSQL 16
- The following Python packages (install with pip):
  ```
  pip install flask psycopg2-binary
  ```

### Database setup

1. Open pgAdmin (or psql) and create a database named `expensetrack`.
2. Run `sql/table.sql` to create all tables, enums, indexes, and the view.
3. Run `sql/triggers.sql` to add the four triggers.
4. Run `sql/records.sql` to load the sample data (3 users, accounts, and 190+ transactions).

### Running the app

Inside the `app/` folder, run:

```
python app.py
```

Then open your browser and go to `http://127.0.0.1:5000`.

### Navigating the app

**Switching users** — The navbar always shows a "Viewing as" dropdown in the top-right corner. Selecting a different name reloads the current page for that user. All data (accounts, transactions, categories, tags) is scoped to the selected user.

**Dashboard** — Shows all accounts with their current balances and a line chart of net worth over time. Credit card accounts with a negative balance are highlighted in yellow (a negative credit card balance means you owe money, which is normal).

**Transactions** — Pick an account from the dropdown at the top. The table shows every transaction on that account in chronological order, including a running balance column. You can filter by date range (or use the quick presets), category, or tag. Note: the running balance column is hidden when a filter is active because filtering breaks the chain and the partial balance would be misleading.

**Spending** — Shows how your expenses are split by category, both as a doughnut chart and a percentage table. A separate panel shows the top 5 categories. You can filter by date range.

**Monthly** — A side-by-side bar chart and table showing income vs. expenses for each month. Rows where income exceeds expenses are highlighted green; deficit months are red.

**Insights** — Four diagnostic panels:
- Accounts with a negative balance (overdrawn checking/savings in red, credit cards with balance owed in yellow)
- Receipt coverage per account (how many transactions have an attached receipt)
- Categories you defined but never used on a transaction
- Accounts that have no transactions at all

**Adding a transaction** — Go to **Manage → + Add Transaction**. Select the account, pick a type (Expense, Income, or Transfer), enter the amount, and choose a category. For transfers, a destination account picker appears instead of the category dropdown. Tags are optional checkboxes. The category list automatically filters to show only expense or income categories depending on the type you selected.

**Managing categories** — Go to **Manage → Categories**. You can add a new category by giving it a name and a type. To delete a category, click the Delete button next to it. If a category is currently used by any transaction, the Delete button is greyed out and you will see an error if you try to remove it.

**Managing tags** — Go to **Manage → Tags**. Same idea as categories, but tags can always be deleted. When a tag is deleted, it is automatically removed from all transactions that used it (the database handles this via cascade).

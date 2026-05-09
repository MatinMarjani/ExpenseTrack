-- =============================================================================
-- ExpenseTrack – Seed Data (records.sql)
-- CIS761 Class Project – Matin Marjani
-- PostgreSQL
--
-- Dataset summary:
--   3 users  |  9 accounts  |  22 categories  |  14 tags
--   58 transactions  |  8 receipts  |  25 transaction-tag links
--
-- Transaction date range: January 2025 – May 2026
--
-- Notable design choices for query demonstration:
--   • Alice's Visa Credit Card and Bob's Mastercard end with negative balances (Q6)
--   • Carol's Cash Wallet has no transactions at all (Q7)
--   • Alice's "Entertainment" category is never used in any transaction (Q15)
--   • Freelance income and vacation tags on Alice's account give Q5 results
--   • Enough months of data for Q2, Q8, Q9 to show multi-row trends
--
-- IDs are inserted explicitly so Receipts and TransactionTags can reference
-- them by known values. Sequences are reset at the end of this file.
--
-- Run order: table.sql → triggers.sql → records.sql
-- =============================================================================


-- =============================================================================
-- USERS
-- =============================================================================

INSERT INTO Users (user_id, email, username, password_hash, full_name, created_at)
OVERRIDING SYSTEM VALUE VALUES
(1, 'alice.johnson@email.com', 'alicej', 'hashed_pw_alice', 'Alice Johnson', '2024-01-15 09:00:00+00'),
(2, 'bob.martinez@email.com',  'bobm',   'hashed_pw_bob',   'Bob Martinez',  '2024-02-20 10:30:00+00'),
(3, 'carol.chen@email.com',    'carolc', 'hashed_pw_carol', 'Carol Chen',    '2024-06-01 14:00:00+00');


-- =============================================================================
-- ACCOUNTS
-- =============================================================================
-- Note: account_id 9 (Carol's Cash Wallet) intentionally has no transactions.
--       It will appear in the Q7 result (accounts with no transaction history).

INSERT INTO Accounts (account_id, user_id, name, type, initial_balance, created_at)
OVERRIDING SYSTEM VALUE VALUES
-- Alice
(1, 1, 'Chase Checking',    'checking',    1000.00, '2024-01-15 09:05:00+00'),
(2, 1, 'Chase Savings',     'savings',     5000.00, '2024-01-15 09:10:00+00'),
(3, 1, 'Visa Credit Card',  'credit_card',    0.00, '2024-01-15 09:15:00+00'),
-- Bob
(4, 2, 'BofA Checking',     'checking',    2500.00, '2024-02-20 10:35:00+00'),
(5, 2, 'Savings Account',   'savings',    10000.00, '2024-02-20 10:40:00+00'),
(6, 2, 'Cash Wallet',       'cash',         200.00, '2024-02-20 10:45:00+00'),
(7, 2, 'Mastercard',        'credit_card',    0.00, '2024-02-20 10:50:00+00'),
-- Carol
(8, 3, 'Student Checking',  'checking',     500.00, '2024-06-01 14:05:00+00'),
(9, 3, 'Cash Wallet',       'cash',          50.00, '2024-06-01 14:10:00+00');


-- =============================================================================
-- CATEGORIES
-- =============================================================================
-- Note: category_id 7 (Alice's "Entertainment") is never referenced by any
--       transaction — it will appear in the Q15 result (unused categories).

INSERT INTO Categories (category_id, user_id, name, type)
OVERRIDING SYSTEM VALUE VALUES
-- Alice – income
(1,  1, 'Salary',             'income'),
(2,  1, 'Freelance',          'income'),
-- Alice – expense
(3,  1, 'Groceries',          'expense'),
(4,  1, 'Rent',               'expense'),
(5,  1, 'Transportation',     'expense'),
(6,  1, 'Dining Out',         'expense'),
(7,  1, 'Entertainment',      'expense'),   -- intentionally unused; see Q15
(8,  1, 'Utilities',          'expense'),
-- Bob – income
(9,  2, 'Salary',             'income'),
(10, 2, 'Investment Returns', 'income'),
-- Bob – expense
(11, 2, 'Groceries',          'expense'),
(12, 2, 'Mortgage',           'expense'),
(13, 2, 'Car Insurance',      'expense'),
(14, 2, 'Healthcare',         'expense'),
(15, 2, 'Subscriptions',      'expense'),
(16, 2, 'Travel',             'expense'),
-- Carol – income
(17, 3, 'Part-time Job',      'income'),
(18, 3, 'Scholarship',        'income'),
-- Carol – expense
(19, 3, 'Tuition',            'expense'),
(20, 3, 'Food',               'expense'),
(21, 3, 'Transportation',     'expense'),
(22, 3, 'Entertainment',      'expense');


-- =============================================================================
-- TAGS
-- =============================================================================

INSERT INTO Tags (tag_id, user_id, name)
OVERRIDING SYSTEM VALUE VALUES
-- Alice
(1,  1, 'work'),
(2,  1, 'personal'),
(3,  1, 'recurring'),
(4,  1, 'tax-deductible'),
(5,  1, 'vacation'),
-- Bob
(6,  2, 'business'),
(7,  2, 'personal'),
(8,  2, 'medical'),
(9,  2, 'home'),
(10, 2, 'travel'),
-- Carol
(11, 3, 'school'),
(12, 3, 'personal'),
(13, 3, 'food'),
(14, 3, 'fun');


-- =============================================================================
-- TRANSACTIONS
-- Columns: id, account_id, counterparty_account_id, category_id,
--          type, amount, transaction_date, entry_date, description
--
-- Rules enforced here:
--   transfer → counterparty IS NOT NULL, category IS NULL
--   income / expense → counterparty IS NULL
--   category type must match transaction type (enforced by trigger)
--   both accounts in a transfer belong to the same user (enforced by trigger)
-- =============================================================================

INSERT INTO Transactions
    (transaction_id, account_id, counterparty_account_id, category_id,
     type, amount, transaction_date, entry_date, description)
OVERRIDING SYSTEM VALUE VALUES

-- ── Alice – January 2025 ──────────────────────────────────────────────────
( 1, 1, NULL, 1,    'income',  4000.00, '2025-01-15', '2025-01-15', 'Monthly salary – January'),
( 2, 1, NULL, 4,    'expense', 1200.00, '2025-01-01', '2025-01-01', 'January rent payment'),
( 3, 1, NULL, 3,    'expense',  280.00, '2025-01-10', '2025-01-10', 'Grocery run – Trader Joe''s'),
( 4, 1, NULL, 8,    'expense',   95.00, '2025-01-20', '2025-01-20', 'Electric and gas bill'),
( 5, 1, 2,    NULL, 'transfer', 500.00, '2025-01-25', '2025-01-25', 'Moving surplus to savings'),
( 6, 3, NULL, 6,    'expense',   65.00, '2025-01-22', '2025-01-22', 'Dinner at Olive Garden'),
( 7, 1, NULL, 5,    'expense',   45.00, '2025-01-28', '2025-01-28', 'Monthly transit pass'),

-- ── Alice – February 2025 ─────────────────────────────────────────────────
( 8, 1, NULL, 1,    'income',  4000.00, '2025-02-15', '2025-02-15', 'Monthly salary – February'),
( 9, 1, NULL, 4,    'expense', 1200.00, '2025-02-01', '2025-02-01', 'February rent payment'),
(10, 1, NULL, 3,    'expense',  310.00, '2025-02-08', '2025-02-08', 'Grocery run – Whole Foods'),
(11, 1, NULL, 2,    'income',   800.00, '2025-02-20', '2025-02-21', 'Web design project payment'),
(12, 3, NULL, 6,    'expense',   90.00, '2025-02-14', '2025-02-14', 'Valentine''s Day dinner'),
(13, 1, NULL, 5,    'expense',   50.00, '2025-02-26', '2025-02-26', 'Monthly transit pass'),

-- ── Alice – March 2025 ────────────────────────────────────────────────────
(14, 1, NULL, 1,    'income',  4000.00, '2025-03-15', '2025-03-15', 'Monthly salary – March'),
(15, 1, NULL, 4,    'expense', 1200.00, '2025-03-01', '2025-03-01', 'March rent payment'),
(16, 1, NULL, 3,    'expense',  265.00, '2025-03-09', '2025-03-09', 'Grocery run – Costco'),
(17, 1, NULL, 8,    'expense',  110.00, '2025-03-22', '2025-03-22', 'Electric and gas bill'),
(18, 1, 2,    NULL, 'transfer',1000.00, '2025-03-28', '2025-03-28', 'Boosting savings fund'),
(19, 3, NULL, 6,    'expense',   75.00, '2025-03-18', '2025-03-18', 'Team dinner outing'),

-- ── Alice – April 2025 ────────────────────────────────────────────────────
(20, 1, NULL, 1,    'income',  4000.00, '2025-04-15', '2025-04-15', 'Monthly salary – April'),
(21, 1, NULL, 4,    'expense', 1200.00, '2025-04-01', '2025-04-01', 'April rent payment'),
(22, 1, NULL, 3,    'expense',  295.00, '2025-04-07', '2025-04-07', 'Grocery run – Trader Joe''s'),
(23, 1, NULL, 2,    'income',  1200.00, '2025-04-20', '2025-04-20', 'E-commerce site redesign'),
(24, 1, NULL, 5,    'expense',   55.00, '2025-04-25', '2025-04-25', 'Monthly transit pass'),
(25, 3, NULL, 6,    'expense',  120.00, '2025-04-30', '2025-04-30', 'Farewell dinner – vacation eve'),

-- ── Bob – January 2025 ────────────────────────────────────────────────────
(26, 4, NULL, 9,    'income',  6500.00, '2025-01-15', '2025-01-15', 'Monthly salary – January'),
(27, 4, NULL, 12,   'expense', 1800.00, '2025-01-01', '2025-01-01', 'Mortgage payment – January'),
(28, 4, NULL, 11,   'expense',  450.00, '2025-01-12', '2025-01-12', 'Weekly groceries x3'),
(29, 4, NULL, 13,   'expense',  180.00, '2025-01-08', '2025-01-08', 'Car insurance premium'),
(30, 7, NULL, 15,   'expense',   45.00, '2025-01-05', '2025-01-05', 'Netflix + Spotify subscriptions'),
(31, 4, 5,    NULL, 'transfer',1000.00, '2025-01-28', '2025-01-28', 'Monthly savings transfer'),

-- ── Bob – February 2025 ───────────────────────────────────────────────────
(32, 4, NULL, 9,    'income',  6500.00, '2025-02-15', '2025-02-15', 'Monthly salary – February'),
(33, 4, NULL, 12,   'expense', 1800.00, '2025-02-01', '2025-02-01', 'Mortgage payment – February'),
(34, 4, NULL, 11,   'expense',  380.00, '2025-02-10', '2025-02-10', 'Groceries – February'),
(35, 5, NULL, 10,   'income',   250.00, '2025-02-28', '2025-02-28', 'Quarterly dividend payment'),
(36, 7, NULL, 14,   'expense',  200.00, '2025-02-15', '2025-02-15', 'Dentist appointment'),
(37, 7, NULL, 15,   'expense',   45.00, '2025-02-05', '2025-02-05', 'Netflix + Spotify subscriptions'),

-- ── Bob – March 2025 ──────────────────────────────────────────────────────
(38, 4, NULL, 9,    'income',  6500.00, '2025-03-15', '2025-03-15', 'Monthly salary – March'),
(39, 4, NULL, 12,   'expense', 1800.00, '2025-03-01', '2025-03-01', 'Mortgage payment – March'),
(40, 4, NULL, 11,   'expense',  420.00, '2025-03-09', '2025-03-09', 'Groceries – March'),
(41, 7, NULL, 16,   'expense', 1200.00, '2025-03-20', '2025-03-20', 'Spring break flights and hotel'),
(42, 4, 6,    NULL, 'transfer', 500.00, '2025-03-25', '2025-03-25', 'Cash for weekend trip'),

-- ── Carol – January 2025 ──────────────────────────────────────────────────
(43, 8, NULL, 17,   'income',   800.00, '2025-01-31', '2025-01-31', 'Part-time job paycheck'),
(44, 8, NULL, 20,   'expense',  200.00, '2025-01-15', '2025-01-15', 'Groceries and meal prep'),
(45, 8, NULL, 21,   'expense',   60.00, '2025-01-20', '2025-01-20', 'Bus pass – January'),

-- ── Carol – February 2025 ─────────────────────────────────────────────────
(46, 8, NULL, 17,   'income',   800.00, '2025-02-28', '2025-02-28', 'Part-time job paycheck'),
(47, 8, NULL, 18,   'income',  1500.00, '2025-02-01', '2025-02-01', 'Spring semester scholarship'),
(48, 8, NULL, 19,   'expense', 1200.00, '2025-02-05', '2025-02-05', 'Spring semester tuition payment'),
(49, 8, NULL, 20,   'expense',  220.00, '2025-02-18', '2025-02-18', 'Groceries – February'),

-- ── Carol – March 2025 ────────────────────────────────────────────────────
(50, 8, NULL, 17,   'income',   800.00, '2025-03-31', '2025-03-31', 'Part-time job paycheck'),
(51, 8, NULL, 20,   'expense',  180.00, '2025-03-20', '2025-03-20', 'Groceries – March'),
(52, 8, NULL, 22,   'expense',   50.00, '2025-03-28', '2025-03-28', 'Movie night and snacks'),

-- ── Alice – May 2026 (current month – makes Q4 return results) ────────────
(53, 1, NULL, 4,    'expense', 1200.00, '2026-05-01', '2026-05-01', 'May rent payment'),
(54, 1, NULL, 3,    'expense',  310.00, '2026-05-04', '2026-05-04', 'Grocery run – Trader Joe''s'),
(55, 1, NULL, 8,    'expense',  105.00, '2026-05-07', '2026-05-07', 'Electric and gas bill'),
(56, 1, NULL, 5,    'expense',   45.00, '2026-05-09', '2026-05-09', 'Monthly transit pass'),
(57, 3, NULL, 6,    'expense',   78.00, '2026-05-08', '2026-05-08', 'Dinner out'),
(58, 1, NULL, 1,    'income',  4000.00, '2026-05-15', '2026-05-15', 'Monthly salary – May');


-- =============================================================================
-- RECEIPTS
-- (attached to 8 selected transactions as supporting evidence)
-- =============================================================================

INSERT INTO Receipts (receipt_id, transaction_id, file_name, file_type, storage_location, uploaded_at)
OVERRIDING SYSTEM VALUE VALUES
(1, 2,  'rent_jan_2025.pdf',         'pdf', 'uploads/receipts/alice/rent_jan_2025.pdf',         '2025-01-01 18:00:00+00'),
(2, 6,  'olive_garden_jan.jpg',      'jpg', 'uploads/receipts/alice/olive_garden_jan.jpg',      '2025-01-22 22:30:00+00'),
(3, 11, 'freelance_invoice_feb.pdf', 'pdf', 'uploads/receipts/alice/freelance_invoice_feb.pdf', '2025-02-21 09:00:00+00'),
(4, 30, 'subscriptions_jan.pdf',     'pdf', 'uploads/receipts/bob/subscriptions_jan.pdf',       '2025-01-05 20:00:00+00'),
(5, 36, 'dentist_feb_2025.pdf',      'pdf', 'uploads/receipts/bob/dentist_feb_2025.pdf',        '2025-02-15 17:00:00+00'),
(6, 41, 'spring_break_travel.pdf',   'pdf', 'uploads/receipts/bob/spring_break_travel.pdf',     '2025-03-20 23:00:00+00'),
(7, 44, 'groceries_jan_carol.jpg',   'jpg', 'uploads/receipts/carol/groceries_jan.jpg',         '2025-01-15 19:00:00+00'),
(8, 48, 'tuition_spring_2025.pdf',   'pdf', 'uploads/receipts/carol/tuition_spring_2025.pdf',   '2025-02-05 14:00:00+00');


-- =============================================================================
-- TRANSACTION TAGS
-- =============================================================================

INSERT INTO TransactionTags (transaction_id, tag_id) VALUES
-- Alice
( 1,  1),   -- salary Jan    → work
( 1,  3),   -- salary Jan    → recurring
( 2,  3),   -- rent Jan      → recurring
( 4,  3),   -- utilities Jan → recurring
( 7,  3),   -- transit Jan   → recurring
(11,  1),   -- freelance Feb → work
(11,  4),   -- freelance Feb → tax-deductible
(13,  3),   -- transit Feb   → recurring
(19,  2),   -- dining Mar    → personal
(23,  1),   -- freelance Apr → work
(23,  4),   -- freelance Apr → tax-deductible
(25,  2),   -- dining Apr    → personal
(25,  5),   -- dining Apr    → vacation
-- Bob
(26,  6),   -- salary Jan    → business
(27,  9),   -- mortgage Jan  → home
(30,  6),   -- subscriptions → business
(36,  8),   -- healthcare    → medical
(41, 10),   -- travel Mar    → travel
(41,  7),   -- travel Mar    → personal
(42,  7),   -- cash transfer → personal
-- Carol
(43, 11),   -- paycheck Jan  → school
(44, 13),   -- groceries Jan → food
(44, 12),   -- groceries Jan → personal
(48, 11),   -- tuition Feb   → school
(52, 14);   -- entertainment → fun


-- =============================================================================
-- RESET SEQUENCES
-- Required after explicit ID inserts so future auto-generated IDs
-- do not collide with the seeded rows.
-- =============================================================================

SELECT setval(pg_get_serial_sequence('users',        'user_id'),        (SELECT MAX(user_id)        FROM Users));
SELECT setval(pg_get_serial_sequence('accounts',     'account_id'),     (SELECT MAX(account_id)     FROM Accounts));
SELECT setval(pg_get_serial_sequence('categories',   'category_id'),    (SELECT MAX(category_id)    FROM Categories));
SELECT setval(pg_get_serial_sequence('tags',         'tag_id'),         (SELECT MAX(tag_id)         FROM Tags));
SELECT setval(pg_get_serial_sequence('transactions', 'transaction_id'), (SELECT MAX(transaction_id) FROM Transactions));
SELECT setval(pg_get_serial_sequence('receipts',     'receipt_id'),     (SELECT MAX(receipt_id)     FROM Receipts));

# Synthetic financial fixtures

Reusable fixture builders will be added with the financial domain beginning in Phase 2/3. The required catalog is:

- BRL-only
- BRL + USD multi-currency
- bank + cash + card
- installment-heavy Brazilian card
- recurring salary and bills
- assets + liabilities
- multiple acquisition lots
- two-device sync
- conflict
- offline queue

No real user financial data may be added to fixtures or snapshots.

`v1.1-schema-v6.equis.fixture` is a synthetic encrypted schema-v6 backup used
to verify restoration into schema v7. Its password is defined in
`test/database/equis_backup_service_test.dart`. The `.fixture` suffix keeps
this test data versioned while personal `*.equis` backups remain ignored.

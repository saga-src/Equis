"""Exercise both 1.1 push/format-2 activation lock orders on PostgreSQL.

Run against a disposable database whose name ends in _test, after applying the
sync migrations. The connecting user must be able to insert/delete test Auth
identities and read pg_stat_activity. Install psycopg[binary], then set an
explicit PG_TEST_DSN and run this file. For example, in PowerShell:

    python -m pip install "psycopg[binary]"
    $env:PG_TEST_DSN = "host=127.0.0.1 port=15437 user=equis_test dbname=equis_format_gate_test"
    python supabase/tests/sync_aggregate_format_floor_concurrency.py

The script creates unique test identities, checks real lock waits and removes
its rows even if an assertion fails. It has no default database connection.
"""

import os
import threading
import time
import uuid

import psycopg
from psycopg.types.json import Jsonb


FINGERPRINT = "a" * 64
LOCK_WAIT_SECONDS = 5


def connect(dsn: str, name: str, *, autocommit: bool = False):
    return psycopg.connect(dsn, application_name=name, autocommit=autocommit)


def as_owner(connection, owner_id: uuid.UUID) -> None:
    connection.execute("set role authenticated")
    connection.execute(
        "select set_config('request.jwt.claim.sub', %s, false)",
        (str(owner_id),),
    )


def mutation(record_id: uuid.UUID) -> Jsonb:
    return Jsonb(
        [
            {
                "operation_id": str(uuid.uuid4()),
                "entity_type": "transaction",
                "record_id": str(record_id),
                "expected_revision": None,
                "new_revision": 3,
                "cipher_version": 1,
                "nonce_hex": "01" * 24,
                "ciphertext_hex": "02" * 40,
                "is_deleted": False,
            }
        ]
    )


def old_push(connection, vault_id: uuid.UUID, record_id: uuid.UUID):
    return connection.execute(
        "select public.apply_sync_batch(%s,%s,%s)",
        (vault_id, mutation(record_id), FINGERPRINT),
    ).fetchone()[0]


def wait_for_lock(admin, app_name: str) -> None:
    deadline = time.monotonic() + LOCK_WAIT_SECONDS
    while time.monotonic() < deadline:
        row = admin.execute(
            """
            select wait_event_type
            from pg_stat_activity
            where application_name = %s and state = 'active'
            """,
            (app_name,),
        ).fetchone()
        if row and row[0] == "Lock":
            return
        time.sleep(0.05)
    raise AssertionError(f"{app_name} did not wait on a PostgreSQL lock")


def run_background(dsn: str, name: str, owner_id: uuid.UUID, action):
    result = {}

    def body() -> None:
        try:
            with connect(dsn, name) as connection:
                as_owner(connection, owner_id)
                try:
                    result["value"] = action(connection)
                except psycopg.Error as error:
                    result["sqlstate"] = error.sqlstate
        except BaseException as error:
            result["error"] = error

    thread = threading.Thread(target=body, daemon=True)
    thread.start()
    return thread, result


def expect_finished(thread, result: dict, expected_key: str, expected) -> None:
    thread.join(timeout=LOCK_WAIT_SECONDS)
    if thread.is_alive():
        raise AssertionError("waiting RPC did not finish")
    if result.get(expected_key) != expected:
        raise AssertionError(f"unexpected waiting RPC result: {result}")


def assert_isolated_database(admin) -> None:
    database = admin.execute("select current_database()").fetchone()[0]
    if not database.endswith("_test"):
        raise RuntimeError(
            f"Refusing to write to {database!r}; use a disposable *_test database"
        )


def run(dsn: str) -> None:
    owner_id = uuid.uuid4()
    created_vaults = []
    active_threads = []

    with connect(dsn, "format-gate-admin", autocommit=True) as admin:
        assert_isolated_database(admin)
        try:
            admin.execute(
                """
                insert into auth.users(id,aud,role)
                values(%s,'authenticated','authenticated')
                """,
                (owner_id,),
            )

            # Order 1: the 1.1 push holds the vault row; activation waits.
            old_first_vault, old_first_record = uuid.uuid4(), uuid.uuid4()
            created_vaults.append(old_first_vault)
            admin.execute(
                """
                insert into public.vaults(id,owner_id,key_fingerprint)
                values(%s,%s,%s)
                """,
                (old_first_vault, owner_id, FINGERPRINT),
            )
            with connect(dsn, "format-gate-old-first") as first:
                as_owner(first, owner_id)
                old_result = old_push(first, old_first_vault, old_first_record)
                if old_result[0]["status"] != "accepted":
                    raise AssertionError(old_result)
                thread, result = run_background(
                    dsn,
                    "format-gate-activation-waiter",
                    owner_id,
                    lambda connection: connection.execute(
                        "select public.activate_sync_aggregate_format_2(%s,%s)",
                        (old_first_vault, FINGERPRINT),
                    ).fetchone()[0],
                )
                active_threads.append(thread)
                wait_for_lock(admin, "format-gate-activation-waiter")
                first.commit()
                expect_finished(thread, result, "value", 2)
            row = admin.execute(
                """
                select v.min_aggregate_format, r.revision
                from public.vaults v
                join public.sync_records r on r.vault_id = v.id
                where v.id = %s and r.record_id = %s
                """,
                (old_first_vault, old_first_record),
            ).fetchone()
            if row != (2, 3):
                raise AssertionError(f"old-first state: {row}")
            print("PASS old push obtains vault lock before activation")

            # Order 2: activation holds the vault row; the 1.1 push waits.
            activation_first_vault, activation_first_record = (
                uuid.uuid4(),
                uuid.uuid4(),
            )
            created_vaults.append(activation_first_vault)
            admin.execute(
                """
                insert into public.vaults(id,owner_id,key_fingerprint)
                values(%s,%s,%s)
                """,
                (activation_first_vault, owner_id, FINGERPRINT),
            )
            with connect(dsn, "format-gate-activation-first") as first:
                as_owner(first, owner_id)
                floor = first.execute(
                    "select public.activate_sync_aggregate_format_2(%s,%s)",
                    (activation_first_vault, FINGERPRINT),
                ).fetchone()[0]
                if floor != 2:
                    raise AssertionError(f"unexpected format floor: {floor}")
                thread, result = run_background(
                    dsn,
                    "format-gate-old-waiter",
                    owner_id,
                    lambda connection: old_push(
                        connection, activation_first_vault, activation_first_record
                    ),
                )
                active_threads.append(thread)
                wait_for_lock(admin, "format-gate-old-waiter")
                first.commit()
                expect_finished(thread, result, "sqlstate", "EVP02")
            count = admin.execute(
                "select count(*) from public.sync_records where vault_id = %s",
                (activation_first_vault,),
            ).fetchone()[0]
            if count != 0:
                raise AssertionError(f"old push wrote {count} records after activation")
            print("PASS activation obtains vault lock before old push")
        finally:
            for thread in active_threads:
                thread.join(timeout=LOCK_WAIT_SECONDS)
            for vault_id in created_vaults:
                admin.execute(
                    "delete from public.sync_records where vault_id = %s",
                    (vault_id,),
                )
                admin.execute(
                    "delete from public.vaults where id = %s",
                    (vault_id,),
                )
            admin.execute("delete from auth.users where id = %s", (owner_id,))


if __name__ == "__main__":
    test_dsn = os.environ.get("PG_TEST_DSN")
    if not test_dsn:
        raise SystemExit("PG_TEST_DSN is required; no database default is allowed")
    run(test_dsn)

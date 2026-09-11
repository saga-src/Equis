-- Local edits are coalesced in the outbox. A first upload may already be at
-- revision 3, and subsequent uploads may skip intermediate offline revisions.
-- Keep compare-and-swap ownership/conflict checks and all existing grants.
DO $migration$
DECLARE
  definition text;
BEGIN
  definition := pg_get_functiondef('public.apply_sync_batch(uuid,jsonb)'::regprocedure);
  IF position('v_new_revision = 1)' in definition) = 0 OR
     position('v_new_revision = v_expected_revision + 1)' in definition) = 0 THEN
    RAISE EXCEPTION 'Unexpected sync protocol definition; inspect before migrating';
  END IF;
  definition := replace(definition, 'v_new_revision = 1)', 'v_new_revision >= 1)');
  definition := replace(definition, 'v_new_revision = v_expected_revision + 1)', 'v_new_revision > v_expected_revision)');
  EXECUTE definition;
END;
$migration$;

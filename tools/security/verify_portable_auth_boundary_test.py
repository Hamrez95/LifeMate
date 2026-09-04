from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify-portable-auth-boundary.py")
SPEC = importlib.util.spec_from_file_location("portable_auth_boundary", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PortableAuthBoundaryTests(unittest.TestCase):
    def test_allows_request_context_helpers(self) -> None:
        sql = """
        create policy p on app.rows
        for select to authenticated
        using (auth_subject = auth.uid() and (auth.jwt() ->> 'aal') = 'aal2');
        """
        self.assertEqual(MODULE.forbidden_auth_references(sql), [])

    def test_ignores_comments(self) -> None:
        sql = """
        -- do not create table auth.users here
        /* auth.sessions must remain provider-owned */
        select auth.uid();
        """
        self.assertEqual(MODULE.forbidden_auth_references(sql), [])

    def test_rejects_auth_table_definition(self) -> None:
        sql = "create table auth.shadow_users(id uuid);"
        self.assertEqual(MODULE.forbidden_auth_references(sql), [1])

    def test_rejects_auth_data_mutation(self) -> None:
        sql = "insert into auth.users(id) values (gen_random_uuid());"
        self.assertEqual(MODULE.forbidden_auth_references(sql), [1])

    def test_rejects_auth_grant(self) -> None:
        sql = "grant select on auth.users to authenticated;"
        self.assertEqual(MODULE.forbidden_auth_references(sql), [1])

    def test_rejects_direct_auth_table_reference(self) -> None:
        sql = "select id from auth.users;"
        self.assertEqual(MODULE.forbidden_auth_references(sql), [1])


if __name__ == "__main__":
    unittest.main()

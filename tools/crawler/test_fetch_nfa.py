import importlib.util
import unittest
from datetime import datetime
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("fetch_nfa.py")
SPEC = importlib.util.spec_from_file_location("fetch_nfa_under_test", MODULE_PATH)
nfa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nfa)


class NFACrawlerTests(unittest.TestCase):
    def test_occurred_at_keeps_title_hour_and_minute(self):
        occurred = nfa.build_occurred_at("115-07-24", 24, "06:21")
        self.assertEqual(
            occurred,
            datetime(2026, 7, 24, 6, 21, tzinfo=nfa.TZ_TAIPEI),
        )

    def test_occurred_at_handles_previous_month(self):
        occurred = nfa.build_occurred_at("115-07-01", 30, "23:58")
        self.assertEqual(
            occurred,
            datetime(2026, 6, 30, 23, 58, tzinfo=nfa.TZ_TAIPEI),
        )

    def test_parse_record_has_stable_id_time_and_resolved_state(self):
        html = """
        <table><tr>
          <td>【住宅火災】【24日06:21臺中市南區光輝街住宅火災，已撲滅，無傷亡】初(結)報</td>
          <td>消防署</td>
          <td>115-07-24</td>
        </tr></table>
        """
        records = nfa.parse_records(html)

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["occurredAt"], "2026-07-24T06:21:00+08:00")
        self.assertEqual(records[0]["county"], "台中市")
        self.assertEqual(records[0]["district"], "南區")
        self.assertTrue(records[0]["isResolved"])
        self.assertEqual(records[0]["id"], nfa.record_id(records[0]["title"]))


if __name__ == "__main__":
    unittest.main()

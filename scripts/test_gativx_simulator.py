import unittest

from gativx_simulator import ios_runtime_version, select_simulator


class SimulatorSelectionTests(unittest.TestCase):
    def test_newest_runtime_wins_over_preferred_model_on_older_runtime(self):
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                {"name": "iPhone 17 Pro", "udid": "old-pro", "isAvailable": True},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                {"name": "iPhone 17 Pro Max", "udid": "newest-pro-max", "isAvailable": True},
            ],
        }}
        selected = select_simulator(payload)
        self.assertEqual(
            (selected["runtime"], selected["name"], selected["udid"]),
            ("com.apple.CoreSimulator.SimRuntime.iOS-26-5", "iPhone 17 Pro Max", "newest-pro-max"),
        )

    def test_prefers_iphone_17_pro_within_newest_runtime(self):
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                {"name": "iPhone 17 Pro Max", "udid": "max", "isAvailable": True},
                {"name": "iPhone 17 Pro", "udid": "pro", "isAvailable": True},
            ],
        }}
        selected = select_simulator(payload)
        self.assertEqual((selected["name"], selected["udid"]), ("iPhone 17 Pro", "pro"))

    def test_patch_runtime_is_compared_numerically(self):
        self.assertEqual(ios_runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-26-4"), (26, 4, 0))
        self.assertEqual(ios_runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-26-4-1"), (26, 4, 1))
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
                {"name": "iPhone 17 Pro", "udid": "base", "isAvailable": True},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4-1": [
                {"name": "iPhone 17 Pro Max", "udid": "patch", "isAvailable": True},
            ],
        }}
        self.assertEqual(select_simulator(payload)["udid"], "patch")

    def test_unavailable_and_non_iphone_devices_are_ignored(self):
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                {"name": "iPhone 17 Pro", "udid": "unavailable", "isAvailable": False},
                {"name": "iPad Pro", "udid": "ipad", "isAvailable": True},
            ],
        }}
        self.assertIsNone(select_simulator(payload))

    def test_non_ios_runtime_is_ignored(self):
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.tvOS-26-5": [
                {"name": "iPhone 17 Pro", "udid": "tv", "isAvailable": True},
            ],
        }}
        self.assertIsNone(select_simulator(payload))


if __name__ == "__main__":
    unittest.main(verbosity=2)

import third_party.example.example
import unittest

class TestThirdParty(unittest.TestCase):
    def test_example(self):
        self.assertEqual('example', third_party.example.example.example())

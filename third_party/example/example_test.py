import third_party.example.example
import unittest

class TestExample(unittest.TestCase):
    def test_foo(self):
        self.assertEqual('example', third_party.example.example.example())

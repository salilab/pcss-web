import unittest
import saliweb.test

# Import the peptide frontend with mocks
peptide = saliweb.test.import_mocked_frontend("peptide", __file__,
                                              '../../frontend')


class Tests(saliweb.test.TestCase):

    def test_index(self):
        """Test index page"""
        c = peptide.app.test_client()
        rv = c.get('/')
        self.assertIn(b'Select PCSS Server Mode', rv.data)

    def test_contact(self):
        """Test contact page"""
        c = peptide.app.test_client()
        rv = c.get('/contact')
        self.assertIn(b'Please address inquiries to', rv.data)

    def test_help(self):
        """Test help page"""
        c = peptide.app.test_client()
        rv = c.get('/help')
        self.assertIn(b'This lets the user select', rv.data)

    def test_queue(self):
        """Test queue page"""
        c = peptide.app.test_client()
        rv = c.get('/job')
        self.assertIn(b'No pending or running jobs', rv.data)


if __name__ == '__main__':
    unittest.main()

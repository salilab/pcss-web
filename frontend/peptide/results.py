import os


class ResultFile(object):
    def __init__(self, job, name):
        self.job, self.name = job, name

    def exists(self):
        return os.path.exists(self._path)

    def empty(self):
        return not self.exists() or os.stat(self._path).st_size == 0

    _path = property(lambda self: self.job.get_path(self.name))

    url = property(lambda self: self.job.get_results_file_url(self.name))

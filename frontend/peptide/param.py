import re


class ParameterFile(dict):
    """Parameters as a set of name/value pairs.
       Format of parameter file is tab separated list of name / value pairs.
    """

    @staticmethod
    def read(fname):
        """Read global parameter file.

           @param fname: Full path of parameter filename.
           @return: a new ParameterFile object.
        """
        p = ParameterFile()
        word_re = re.compile('\w')
        with open(fname) as fh:
            for line in fh:
                if line.startswith('#') or not word_re.search(line):
                    continue
                name, value = line.rstrip('\r\n').split('\t')
                p[name] = value
        return p

    def write(self, fname):
        """Write all parameters to file"""
        with open(fname, 'w') as fh:
            for name, value in self.items():
                fh.write('%s\t%s\n' % (name, value))

    def set_unique(self, name, value, log=None):
        """Set parameter value (for example, after reading user input.)

           :param str name: name of parameter whose value is to be set.
           :param value: value to set.
           :param log: If set, write name and value to the log (useful for
                  logging values set by user at web site).
           :raises: KeyError if there is already a parameter set with this name
        """
        if name in self:
            raise KeyError("Tried to set parameter %s to %s but found "
                    "existing value '%s' for this parameter"
                    % (name, value, self[name]))
        else:
            self[name] = value
            if log:
                log.write("%s:\t%s" % (name, value))

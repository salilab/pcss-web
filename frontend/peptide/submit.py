from flask import request
import saliweb.frontend
import time
from .param import ParameterFile


def handle_new_job():
    user_input = {}

    # Read global options, save in user_input
    user_input["email"] = email = request.form.get("email")
    user_input["name"] = name = request.form.get("name")
    user_input["error_handling"] = request.form.get("error_handling")
    user_input["best_model"] = request.form.get("best_model")
    user_input["server_mode"] = server_mode = request.form.get("server_mode")

    job = saliweb.frontend.IncomingJob(name)

    user_input["directory"] = job.directory

    if server_mode == "training":
        # Read training specific options; save in user_input
        user_input["training_file"] = request.files.get("training_file")
        user_input["jackknife_fraction"] = \
            request.form.get("jackknife_fraction", type=float)
        user_input["training_iterations"] = \
            request.form.get("training_iterations", type=int)
    elif server_mode == "application":
        # Read application specific options; save in user_input
        user_input["svm_model"] = request.form.get("svm_model")
        user_input["svm_custom_model"] = request.form.get("svm_custom_model")
        user_input["rules_file"] = request.files.get("rules_file")
        user_input["application_file"] = request.files.get("application_file")
        user_input["application_specification"] = \
            request.form.get("application_specification")
    else:
        raise saliweb.frontend.InputValidationError(
            "Did not get expected server mode (expect 'training' or "
            "'application')")

    # perform all validation and create files
    # hardcoded location -- TODO -- see if there is a better way to do this
    global_parameter_file_name = \
        "/wynton/home/sali/peptide/data/globalPeptideParameters.txt"

    process_user_input(user_input, global_parameter_file_name)

    job.submit(email)

    return saliweb.frontend.render_submit_template('submit.html', job=job)


def process_user_input(user_input, param_file_name):
    """Takes web-page input provided by user, validates it, and writes
       files in preparation for backend (both training and application mode).

       This can be called from get_submit_page or by testing agents.

       :param dict user_input: dict where keys are the same field names as
              the cgi web form, and values are those entered by the user.
              In some cases these are FileHandles.  Also contains a field
              for the job's directory.
       :param str param_file_name: Name of the parameter file that is used
              throughout the job.
    """

    email = user_input["email"]
    name = user_input["name"]
    error_handling = user_input["error_handling"]
    best_model_criteria = user_input["best_model"]
    server_mode = user_input["server_mode"]
    directory = user_input["directory"]

    params = ParameterFile.read(param_file_name)

    validate_job_name(name)

    saliweb.frontend.check_email(email, required=False)

    # Initialize logging
    user_log = UserLogFile(params)
    internal_log = InternalLogFile(params)
    user_log.write("Starting run of peptide server in %s mode. Options set "
                   "for this run:" % server_mode)

    # create parameter hash; insert global options
    params.set_unique("job_name", name, log=user_log)
    params.set_unique("email", email, log=user_log)
    params.set_unique("best_model_criteria", best_model_criteria, log=user_log)
    params.set_unique("server_mode", server_mode, log=user_log)
    params.set_unique("error_handling", error_handling, log=user_log)

    if server_mode == 'training':
        training_fh = user_input["training_file"]
        jackknife_fraction = user_input["jackknife_fraction"]
        training_iterations = user_input["training_iterations"]
        params.set_unique("test_set_percentage", jackknife_fraction,
                          log=user_log)
        params.set_unique("iteration_count", training_iterations, log=user_log)
        validate_jackknife_fraction(jackknife_fraction)
        validate_training_iterations(training_iterations)
        stats = process_user_specified_peptides(training_fh, error_handling,
                directory)
        params.set_unique("peptide_length", stats.max_peptide_length)
        write_training_stats(stats, directory)




class _LogFile(object):
    def __init__(self, params):
        self.file_name = os.path.join(
                params["directory"], params[self._fname_param_key])
        self.fh = open(self.file_name, "w")

    def write(self, msg):
        """Write timestamped line to log

           :param msg: line to write to log; newline appended.
        """
        pass

    def __del__(self):
        if hasattr(self, 'fh'):
            self.fh.close()


class UserLogFile(_LogFile):
    """Log which will be presented to user after job completion"""
    _fname_param_key = 'user_log_file_name'

    def write(self, msg):
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        self.fh.write("%s:\t%s\n" % (ts, "\n\t\t\t".join(
                        get_formatted_lines(msg, 90, break_up_words=False))))

def get_formatted_lines(msg, length, break_up_words):
    """Cleanly format a long message to be wrapped to multiple lines

       :param str msg: string to be formatted
       :param int length: length of each line to be output
       :param bool break_up_words: if False, only start a new line at
              a white space character
       :return: sequence of lines
    """
    cut_point = max(len(msg), length)
    prev_cut_point = 0
    while prev_cut_point < len(msg):
        while (not break_up_words
                or (msg[cut_point-1] == ' ' and cut_point <= len(msg))):
            cut_point += 1
        yield msg[prev_cut_point:cut_point]
        prev_cut_point = cut_point
        cut_point += length


class InternalLogFile(_LogFile):
    """Internal framework log which will be presented to user after
       job completion. This is intended to be the same framework log file
       that the backend also writes to."""
    _fname_param_key = 'framework_log_file_name'

    def write(self, msg):
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        self.fh.write("%s:\t%s\n" % (ts, msg))


def validate_job_name(name):
    """Enforces user-specified job name not blank"""
    if not name:
        raise saliweb.frontend.InputValidationError(
                "Please provide a name for your job run")


def validate_jackknife_fraction(jackknife_fraction):
    """Enforces user-specified jackknife fraction to be <= 0.5."""
    if jackknife_fraction > .5:
        raise saliweb.frontend.InputValidationError(
                "Please set the Jackknife Fraction value to 0.5 or less "
                "(current value is %f)" % jackknife_fraction)
    elif jackknife_fraction == 0.:
        raise saliweb.frontend.InputValidationError(
                "Please set the Jackknife Fraction to a value greater than 0")


def validate_training_iterations(training_iterations):
    """Enforces user-specified number of iterations in training mode
       to be <= 1000 and > 0"""
    if training_iterations > 1000 or training_iterations <= 0:
        raise saliweb.frontend.InputValidationError(
                "Please set the Training Iterations value to be between "
                "1 and 1000 (current value is %d)." % training_iterations)



def process_user_specified_peptides(peptide_fh, error_handling,
        directory, params):
    """Top level method for parsing user-provided peptide file which includes
       all accessions, peptide start positions, and peptide sequences.
       Once read, retrieves sequences from modbase, does a lot of quality
       control, and writes out a file that the backend picks up in the next
       step.

       :param peptide_fh: FileHandle for uploaded file (automatically created
              upon submission).
       :param str error_handling: Either "I" or "Q". "I" ignores mismatches
              and writes them to the log. "Q" quits before the job is sent
              to the backend.
       :param str directory: webserver job directory where file will be written
       :param params: job parameters
       :return: statistics about which peptides were found or not.
    """
    peptide_file_info = read_and_validate_peptide_file(peptide_fh,
            directory, params)


def read_and_validate_peptide_file(peptide_fh, directory, params):
    """Reads user-submitted file that that specifies sequence IDs, peptide
       sequence, peptide position, and peptide classification.
       Validates formatting of all peptide attributes (see inline code for
       specific validation steps performed).
       Each line of the file represents one peptide and is of the form:

       UniprotAccession PeptideStartPosition PeptideSequence Classification

       Classification is either 'positive' or 'negative' (training mode)
       or blank (application).  If it is blank (or anything else) in
       application mode, it will be returned in peptide_file_info as
       'application'. Case doesn't matter, and it will be returned as
       lowercase.  Entries are separated by whitespace.

       :param peptide_fh: FileHandle for uploaded file (automatically
              created upon submission).
       :raises: InputValidationError for a number of reasons related to
              formatting
       :return: peptide_file_info 
    """
    if not peptide_fh:
        raise saliweb.frontend.InputValidationError(
                "No peptide file has been submitted.")
    saved_input_file_name = os.path.join(directory,
                                params["saved_input_file_name"])
    peptide_fh.save(saved_input_file_name)
    with open(saved_input_file_name, encoding='latin1') as fh:
        for line in fh:


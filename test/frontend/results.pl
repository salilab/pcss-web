#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';
use Test::Exception;
use File::Temp qw(tempdir);

BEGIN {
    use_ok('peptide');
    use_ok('saliweb::frontend');
}

my $t = new saliweb::Test('peptide');

# Check results page

sub make_parameters_file {
    my ($server_mode) = @_;
    ok(open(FH, "> parameters.txt"), "Open parameters.txt");
    print FH "server_mode\t$server_mode\n";
    print FH "training_final_result_file_name\tsvmTrainingFinalResults.txt\n";
    print FH "user_model_package_name\tuserCreatedSvmModel.txt\n";
    print FH "user_log_file_name\tuser.log\n";
    print FH "mismatch_file_name\tmismatches.fasta\n";
    print FH "application_final_result_file_name\t" .
             "applicationFinalResults.txt\n";
    ok(close(FH), "Close parameters.txt");
}

# Training mode, error occurred
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");
    make_parameters_file("training");
    my $ret = $frontend->get_results_page($job);
    like($ret, qr/an error occurred/ms,
         'get_results_page (failed training mode)');
}

# Training mode, no model file produced
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");
    make_parameters_file("training");

    my $rf = "svmTrainingFinalResults.txt";
    ok(open(FH, "> $rf"), "Open $rf");
    ok(close(FH), "Close $rf");

    my $ret = $frontend->get_results_page($job);
    like($ret, qr/benchmark results file.*No model file was produced/ms,
         'get_results_page (training, no model file)');
}

# Training mode, successful
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");
    make_parameters_file("training");

    my $rf = "svmTrainingFinalResults.txt";
    ok(open(FH, "> $rf"), "Open $rf");
    ok(close(FH), "Close $rf");

    my $m = "userCreatedSvmModel.txt";
    ok(open(FH, "> $m"), "Open $m");
    ok(close(FH), "Close $m");

    my $ret = $frontend->get_results_page($job);
    like($ret, qr/benchmark results file.*SVM model file generated/ms,
         'get_results_page (training, successful)');
}

# Application mode, error occurred
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");
    make_parameters_file("application");
    my $ret = $frontend->get_results_page($job);
    like($ret, qr/an error occurred/ms,
         'get_results_page (failed application mode)');
}

# Application mode, successful
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");
    make_parameters_file("application");

    my $m = "applicationFinalResults.txt";
    ok(open(FH, "> $m"), "Open $m");
    ok(close(FH), "Close $m");

    my $ret = $frontend->get_results_page($job);
    like($ret, qr/Download application results file/ms,
         'get_results_page (successful application mode)');
}

# Invalid mode
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");
    make_parameters_file("invalid");

    throws_ok { $frontend->get_results_page($job) }
              saliweb::frontend::InternalError,
              'get_results_page (invalid mode)';
    like($@, qr/Did not get expected server mode/,
         "get_results_page (invalid mode, exception message)");
}

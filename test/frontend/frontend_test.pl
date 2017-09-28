use saliweb::Test;
use Test::More 'no_plan';

use Test::Builder;
use Test::Exception;

use File::Basename;
use File::Temp;
use strict;
use DBI;

BEGIN {
    use_ok('peptide');
}

my $t = new saliweb::Test('peptide');

#######################################################################################################################################################
# Testing Notes:
# Test that frontend successfully completes all three modes (application scan, application user defined, training)
# 
# General testing flow:
# 1. Make frontend object.
# 2. Create input hash that simulates what the server passes to the frontend (which itself is read from the cgi object that the frontend gets from the user).
#    Input hash will have some global values and some specific to each mode.
# 3. Call $frontend->clear()
# 4. Call $frontend->process_user_input(). The "run directory", which would normally be the job directory, is local to this test.
# 5. Input files: Parameter file is read from the testPeptideServerParameters.txt file. Other input files, including those needed to create errors 
#    for testing purposes, are in their own input directory, one for each mode.
# 6. Run all tests, both normal processing and errors. Many will compare generated files to "expected output" files; again, there is one directory containing these for each mode.
# 7. Copy generatdd files to the observed output directory, which is in the expected output directory for each mode.

# Important: 1. In all tests, need to call $frontend->clear() before calling $frontend->process_user_input($input); this resets all of the frontend's parameters.
#               Frontend will remind you of this if it thinks this is the cause of an error in its setParam() method
#            2. One thing that could break many of these is if content in modbase changes. The best solution may to make a cached table that
#               copies what this test requires from modbase and doesn't change. (Would have to update peptide.pm to query live vs cached table)
########################################################################################################################################################

my $frontend = $t->make_frontend();
my $testdir = dirname($0);

my $dbh = new MockDBH("$testdir/modbase_data");
$frontend->{'dbh'} = $dbh;

my $applicationScanTestDir = "${testdir}/applicationScan/";
my $applicationDefinedTestDir = "${testdir}/applicationDefined/";
my $trainingTestDir = "${testdir}/training/";

# Use local copy of parameter file, not that from PCSS
my $parameterFileName= "${testdir}/testPeptideServerParameters.txt";

#one test for each server mode 
#&testTraining($frontend, $trainingTestDir, $parameterFileName);
&testApplicationScan($frontend, $applicationScanTestDir, $parameterFileName);
&testApplicationDefined($frontend, $applicationDefinedTestDir, $parameterFileName);




my $links = $frontend->get_navigation_links();
isa_ok($links, 'ARRAY', 'navigation links');

like($links->[0], qr#<a href="http://modbase/top/">PCSS Home</a>#,
     'Index link');

sub testTraining{
    my ($frontend, $testDir, $paramFileName) = @_;

    my $normalInputDir = $testDir . "/normalProcessing/input/";
    my $errorInputDir = $testDir . "/errors/input";
    my $expectedOutputDir = $testDir . "/normalProcessing/expectedOutput/";    
    my $errorExpectedOutputDir = $testDir . "/errors/expectedOutput/";

    &runTrainingNormalTests($normalInputDir, $expectedOutputDir, $paramFileName, $frontend);
    &runTrainingErrorTests($errorInputDir, $errorExpectedOutputDir, $paramFileName, $frontend);
}



sub runTrainingNormalTests{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;

    $frontend->clear();

    my $trainingInput = &makeTrainingInputValues($inputDir);
    my $runDirectory = $trainingInput->{"directory"};

    $frontend->process_user_input($trainingInput, $paramFileName);
    
    #main data files output correctly
    
    &compareFileLines("$expectedOutputDir/inputSequences.fasta", "$runDirectory/inputSequences.fasta", 1, []);
    &compareFileLines("$expectedOutputDir/userInputFile.txt", "$runDirectory/userInputFile.txt", 1, []);
    like(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/144\_mismatch\_negative/, "training grabbed mismatch correctly");
    &compareFileLines("$expectedOutputDir/parameters.txt", "$runDirectory/parameters.txt", 1, ["seqs_in_batch_count", "test_mode", "job_name"]);
    unlike(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/BARKAN/, "training mode didn't write fake accession to fasta file");
    unlike(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/O76094/, "training mode didn't write accession with no peptides to fasta file");
    
    #log files exist and contain proper stats
    my $userLogString = &convertFileToString("$runDirectory/user.log");
    like($userLogString, qr/peptide server in training mode/, "training user log content, server mode listed");
    
    like($userLogString, qr/accession BARKAN was not/, "training user log content, didn't find fake accession");
    like($userLogString, qr/Start Position\: 145/, "training user log content, mismatch noted");
    like($userLogString, qr/\[overrun \-\- 119\]/, "training user log content, overshot noted");
    
    like($userLogString, qr/None of the provided peptides for Uniprot Accession O76094/, "training user log content, no peptides found for a protein");
    
    like($userLogString, qr/Accessions found in modbase: 54/, "training user log content, peptides found vs missed 1");  
    like($userLogString, qr/Accessions not found in modbase \(noted above in this log file\): 2/, "training user log content, peptides found vs missed 2");  
    like($userLogString, qr/accessions read from input file: 56/, "training user log content, peptides found vs missed 3");  
    
    like($userLogString, qr/peptides supplied in modbase proteins: 521/, "training user log content, statistics 1");
    like($userLogString, qr/Positives: 52/, "training user log content, statistics 2");
    like($userLogString, qr/Negatives: 469/, "training user log content, statistics 3");
    
    like($userLogString, qr/matching modbase protein sequences: 446/, "training user log content, statistics 4");
    like($userLogString, qr/Positives: 51/, "training user log content, statistics 5");
    like($userLogString, qr/Negatives: 395/, "training user log content, statistics 6");
    
    like($userLogString, qr/containing these mismatched peptides: 3/, "training user log content, statistics 7");
    like($userLogString, qr/the sequence: 75/, "training user log content, statistics 8");

    my $frameworkLogString = &convertFileToString("$runDirectory/framework.log");
    like ($frameworkLogString, qr/read from input file: 56/, "training framework log content, total accession statistics");
    like ($frameworkLogString, qr/to make sure that/, "training framework log content, framework specific message");

    &testAndPostprocessFiles($runDirectory, $expectedOutputDir, "mismatches.fasta");
}

sub runTrainingErrorTests{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;

    &testValidPeptideFileTraining($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &validateTrainingSetRatio($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &validateTestSetPositive($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &noSeqsFoundTraining($inputDir, $expectedOutputDir, $paramFileName, $frontend);

    &testValidateUserInput($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testGlobalOptions($inputDir, $expectedOutputDir, $paramFileName, $frontend);
}

sub validateTrainingSetRatio{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Validate there are more negatives in the training set than positives

    $frontend->clear();
    my $trainingInput = &makeTrainingErrorInput($inputDir);

    my $badTrainingSetCountFile = $inputDir . "/trainingSetCountValidationFileInput";
    my $fh = FileHandle->new("<" . $badTrainingSetCountFile) || die "could not open $badTrainingSetCountFile\n";
    $trainingInput->{'training_file'} = $fh;

    #this test is cleverly designed to initially have the appropriate ratio, but goes bad after some of the negative peptides don't pass validation filters
    throws_ok { $frontend->process_user_input($trainingInput, $paramFileName) } qr/Please change the number of negative peptides/, 'exception if more training set positive than negatives';

}

sub validateTestSetPositive{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #validate positives test set > 1

    $frontend->clear();
    my $trainingInput = &makeTrainingErrorInput($inputDir);

    my $badTrainingSetCountFile = $inputDir . "/trainingSetPositiveValidationInput";
    my $fh = FileHandle->new("<" . $badTrainingSetCountFile) || die "could not open $badTrainingSetCountFile\n";
    $trainingInput->{'training_file'} = $fh;
    throws_ok { $frontend->process_user_input($trainingInput, $paramFileName) } qr/ensure that there is at least one peptide/, 'exception if not at least one positive in test set';
}


sub noSeqsFoundTraining{
   my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Ensure failure if error handling set to "I" but all seqs are mismatches or not found.
    
   $frontend->clear();
   my $trainingInput = &makeTrainingErrorInput($inputDir);

   my $trainingFakeSeqFile =  $inputDir . "/trainingFakeSeqFile";
   my $fakeSeqFileFh = FileHandle->new("<" . $trainingFakeSeqFile) || die "could not open $trainingFakeSeqFile";
   $trainingInput->{"training_file"} = $fakeSeqFileFh;
   throws_ok { $frontend->process_user_input($trainingInput, $paramFileName) } qr/due to having no input/, 'exception if no accession is found in training mode';
}

sub testValidPeptideFileTraining{

    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Valid peptide file -- all exceptions in readAndValidatePeptideFileB()
        
    my $trainingInput = &makeTrainingErrorInput($inputDir);
    my $directory = $trainingInput->{"directory"};

    my $badPeptideFileToErrors = &getBadPeptideFileToErrorsMap();
    $badPeptideFileToErrors->{invalidClassification} = "classification for a peptide";   #extra error for training mode

    # -- note -- if frontend is ever cleared before this test, it will lose its parameters and readAndValidateApplicationFile will complain    
    my $peptideFileErrorDirectory = $inputDir . "/peptideFileErrors";
    foreach my $badPeptideFile (keys %$badPeptideFileToErrors){
	
	my $peptideFh = FileHandle->new("<" . $peptideFileErrorDirectory . "/" . $badPeptideFile) || die "could not open bad peptide file $badPeptideFile";
	my $exceptionMessage = $badPeptideFileToErrors->{$badPeptideFile};
	throws_ok {$frontend->readAndValidatePeptideFile($peptideFh, $directory)}
	qr /$exceptionMessage/, "exception if training mode peptide file $badPeptideFile formatted incorrectly";
   }
    my $missingPeptideFh;
    
    throws_ok {$frontend->readAndValidatePeptideFile($missingPeptideFh)}
    qr /No peptide file has been/, "exception if training peptide file not provided";

}

sub testValidateUserInput{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Training specific user-input values
   
    throws_ok {$frontend->validateJackknifeFraction(.51)}
    qr /Please set the Jackknife Fraction/, "exception if user-specified jackknife fraction > .5";
    
    throws_ok {$frontend->validateJackknifeFraction(0)}
    qr /to a value greater than/, "exception if user-specified jackknife fraction == 0";
    
    throws_ok{$frontend->validateTrainingIterations(1001)}
    qr /Please set the Training Iterations/, "exception if user-specified training iterations > 1000";
}


sub testGlobalOptions{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Simple global options -- think it's ok if these are only tested in training mode
    
    throws_ok{$frontend->validateJobName("")}
    qr /Please provide a name for your job/, "exception if user doesn't specify job name";
    
    #TODO -- when TEST::Files module available, make sure sequences directory is created
        
    $frontend->clear();
}


sub testApplicationDefined{
    my ($frontend, $testDir, $paramFileName) = @_;
 
    my $normalInputDir = $testDir . "/normalProcessing/input/";
    my $errorInputDir = $testDir . "/errors/input";
    my $expectedOutputDir = $testDir . "/normalProcessing/expectedOutput/";    
    my $errorExpectedOutputDir = $testDir . "/errors/expectedOutput/";

    &runApplicationDefinedNormalTests($normalInputDir, $expectedOutputDir, $paramFileName, $frontend);
    &runApplicationDefinedErrorTests($errorInputDir, $errorExpectedOutputDir, $paramFileName, $frontend);
}
    

sub runApplicationDefinedNormalTests{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;

    $frontend->clear();
    my $applicationDefinedInput = &makeApplicationDefinedInput($inputDir);
    my $runDirectory = $applicationDefinedInput->{"directory"};


    #Normal functioning

    $frontend->process_user_input($applicationDefinedInput, $paramFileName);
    
    #Main data files were output correctly
    
    &compareFileLines("$expectedOutputDir/inputSequences.fasta", "$runDirectory/inputSequences.fasta", 1, []);
    &compareFileLines("$expectedOutputDir/userInputFile.txt", "$runDirectory/userInputFile.txt", 1, []);
    like(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/850\_mismatch\_Application/, "application defined wrote mismatch to fasta file");
    #TODO - after Test::File loaded	compare_ok("$expectedOutputDirecory/inputSequences.fasta", "$runDirectory/inputSequences.fasta", "application scan fasta sequences");    
    &compareFileLines("$expectedOutputDir/parameters.txt", "$runDirectory/parameters.txt", 1, ["seqs_in_batch_count", "test_mode", "job_name"]);
    &compareFileLines("$expectedOutputDir/mismatches.fasta", "$runDirectory/mismatches.fasta", 1, []);
    
    
    #missing accession not written to fasta file
    unlike(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/BARKAN/, "application defined didn't write fake acccession to fasta file");
    unlike(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/O76094/, "application defined mode didn't write accession with no peptides to fasta file");  
    
    #User log has key pieces of information written and stats
    #TODO -- user log exists (after Test::File loaded)
    
    my $userLogString = &convertFileToString("$runDirectory/user.log");
    
    like($userLogString, qr/BARKAN was not found/, "application defined user log content, didn't find fake accession");
    

    like($userLogString, qr/\[overrun \-\- 119\]/, "application defined user log content, first overshot");
    like($userLogString, qr/\[overrun \-\- 857\]/, "application defined user log content, second overshot");
    like($userLogString, qr/Start Position\: 420/, "application defined user log content, mismatch");
    like($userLogString, qr/provided peptides for Uniprot Accession Q05CV4/, "application defined user log content, no peptides found for a protein");
    
    like($userLogString, qr/Number of accessions read from input file: 20/, "application defined user log content, total accessions");
    like($userLogString, qr/Accessions found in modbase: 19/, "application defined user log content, accessions found");
    like($userLogString, qr/not found in modbase \(noted above in this log file\): 1/, "application defined user log content, accessions missed");
    
    like($userLogString, qr/peptides supplied in modbase proteins: 25/, "application defined user log content, statistics 1");
    like($userLogString, qr/matching modbase protein sequences: 22/, "application defined user log content, statistics 2");
    
    like($userLogString, qr/containing these mismatched peptides: 3/, "application defined user log content, statistics 3");
    like($userLogString, qr/user-supplied position: 3/, "application defined user log content, statistics 4");
    
    #framework log has key pieces of info written
    #TODO -- framework log exists
    my $frameworkLogString = &convertFileToString("$runDirectory/framework.log");
    like ($frameworkLogString, qr/20 provided/, "application defined framework log content, total accessions");
    like ($frameworkLogString, qr/BARKAN was not found/, "application defined framework log content, didn't find fake accession");
    like($frameworkLogString, qr/1 proteins had only mismatches/, "application defined framework log content, total number with no peptides found");
    &testAndPostprocessFiles($runDirectory, $expectedOutputDir, "mismatches.fasta");
}

sub runApplicationDefinedErrorTests{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;

    &testValidPeptideFile($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testOnlyMismatches($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testNoSeqFoundDefined($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testSeqNotFoundQuit($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testMismatchQuit($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testCustomModelErrors($inputDir, $expectedOutputDir, $paramFileName, $frontend);
}

sub testCustomModelErrors{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    
    my $applicationErrorInput = &makeApplicationErrorInput($inputDir, "D");
    my $runDirectory = $applicationErrorInput->{"directory"};

    my $badCustomModelFiles = &getBadCustomModelFiles();
        
    my $customModelErrorDirectory = $inputDir . "/customModelErrors";
    foreach my $badCustomModelFile (keys %$badCustomModelFiles){
	my $exceptionType = $badCustomModelFiles->{$badCustomModelFile};
	print STDERR "testing exception type $exceptionType\n";
	my $modelFh = FileHandle->new("<" . $customModelErrorDirectory . "/" . $badCustomModelFile) || die "could not open bad custom model file $badCustomModelFile";
	throws_ok {$frontend->processUserCreatedModel($runDirectory, $modelFh)}
	qr /expected file format for svm model generated/, "exception if user custom model formatted incorrectly ($exceptionType)";
    }
}

sub getBadCustomModelFiles{
    my $badCustomModelFiles;
    $badCustomModelFiles->{"userModelInvalidLength.txt"} = "Line 'peptideLength (#) not found";
    $badCustomModelFiles->{"userModelNoSeparator.txt"} = "Separator line not found";
    $badCustomModelFiles->{"userModelSmallBenchmark.txt"} = "benchmark model too small (< 3)";
    $badCustomModelFiles->{"userModelNoModel.txt"} = "model component not found";
    return $badCustomModelFiles;

}
sub testValidPeptideFile{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Valid peptide file -- all exceptions in readAndValidatePeptideFile()
    my $applicationErrorInput = &makeApplicationErrorInput($inputDir, "D");
    my $runDirectory = $applicationErrorInput->{"directory"};

    my $badPeptideFileToErrors = &getBadPeptideFileToErrorsMap();
    
    my $peptideFileErrorDirectory = $inputDir . "/peptideFileErrors";
    foreach my $badPeptideFile (keys %$badPeptideFileToErrors){
	
	my $peptideFh = FileHandle->new("<" . $peptideFileErrorDirectory . "/" . $badPeptideFile) || die "could not open bad peptide file $badPeptideFile";
	my $exceptionMessage = $badPeptideFileToErrors->{$badPeptideFile};
	throws_ok {$frontend->readAndValidatePeptideFile($peptideFh, $runDirectory)}
	qr /$exceptionMessage/, "exception if application defined peptide file $badPeptideFile formatted incorrectly";
    }

    my $missingPeptideFh;
    
    throws_ok {$frontend->readAndValidatePeptideFile($missingPeptideFh, $runDirectory)}
    qr /No peptide file has been/, "exception if application defined peptide file not provided";
}


sub testNoSeqFoundDefined{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Failure if error handling set to "I" but all seqs are mismatches or no accessions found.
    
    $frontend->clear();
    my $applicationErrorInput = &makeApplicationErrorInput($inputDir, "D");
    my $runDirectory = $applicationErrorInput->{"directory"};
    
    my $applicationFakeSeqFile =  $inputDir . "/applicationFakeSeqFile";
    my $fakeSeqFileFh = FileHandle->new("<" . $applicationFakeSeqFile) || die "could not open $applicationFakeSeqFile";
    $applicationErrorInput->{"application_file"} = $fakeSeqFileFh;
    throws_ok { $frontend->process_user_input($applicationErrorInput, $paramFileName) } qr/due to having no input/, 'exception if no accession is found in application defined mode';
}

sub testOnlyMismatches{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    
    $frontend->clear();
    my $applicationErrorInput = &makeApplicationErrorInput($inputDir, "D");
    my $runDirectory = $applicationErrorInput->{"directory"};

    my $applicationAllMismatchesFile = $inputDir . "/testApplicationDefinedOnlyMismatches";
    my $applicationMismatchesFh = FileHandle->new("<" . $applicationAllMismatchesFile) || die "could not open $applicationAllMismatchesFile";
    $applicationErrorInput->{"application_file"} = $applicationMismatchesFh;
    throws_ok { $frontend->process_user_input($applicationErrorInput, $paramFileName) }  qr/Make sure your numbering system/, 'exception if all provided user-defined peptides had mismatches';

}
 
sub testSeqNotFoundQuit{

    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #Failure if error handling set to "Q" and mismatches or sequences not found. This applies to training too, but error handling is global option so should be fine.
    
    $frontend->clear();
    my $applicationErrorInput = &makeApplicationErrorInput($inputDir, "D");
    my $runDirectory = $applicationErrorInput->{"directory"};
    
    my $applicationFakeSeqFile =  $inputDir . "/applicationFakeSeqFile";
    my $fakeSeqFileFh = FileHandle->new("<" . $applicationFakeSeqFile) || die "could not open $applicationFakeSeqFile";
    $applicationErrorInput->{"application_file"} = $fakeSeqFileFh;
    $applicationErrorInput->{"error_handling"} = "Q";
    throws_ok { $frontend->process_user_input($applicationErrorInput, $paramFileName) } qr/error handling option was set to/, 'exception if error handling is "Q" and accession not found';
    
}


sub testMismatchQuit{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    $frontend->clear();

    my $applicationErrorInput = &makeApplicationErrorInput($inputDir, "D");
    my $runDirectory = $applicationErrorInput->{"directory"};

    my $applicationFakeMismatchFile =  $inputDir . "/applicationFakeMismatchFile";
    my $fakeMismatchFileFh = FileHandle->new("<" . $applicationFakeMismatchFile) || die "could not open $applicationFakeMismatchFile";
    $applicationErrorInput->{"application_file"} = $fakeMismatchFileFh;
    $applicationErrorInput->{"error_handling"} = "Q";    
    throws_ok { $frontend->process_user_input($applicationErrorInput, $paramFileName) } qr/error handling option was set to/, 'exception if error handling is "Q" and get sequence mismatch';

}
	

sub testApplicationScan{
    my ($frontend, $testDir, $paramFileName) = @_;

    my $normalInputDir = $testDir . "/normalProcessing/input/";
    my $errorInputDir = $testDir . "/errors/input";
    my $expectedOutputDir = $testDir . "/normalProcessing/expectedOutput/";    
    my $errorExpectedOutputDir = $testDir . "/errors/expectedOutput/";

    &runApplicationScanNormalTests($normalInputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testApplicationCustomModel($normalInputDir, $expectedOutputDir, $paramFileName, $frontend);

    &testNoRulesFile($normalInputDir, $expectedOutputDir, $paramFileName, $frontend);
    
    &runApplicationScanErrorTests($errorInputDir, $errorExpectedOutputDir, $paramFileName, $frontend);
}

sub runApplicationScanNormalTests{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;


    $frontend->clear();
    my $applicationScanInput = &makeApplicationScanInput($inputDir);
    my $runDirectory = $applicationScanInput->{"directory"};

    #Normal functioning
    $frontend->process_user_input($applicationScanInput, $paramFileName);
	
    #Main data files were output correctly
    &compareFileLines("$expectedOutputDir/inputSequences.fasta", "$runDirectory/inputSequences.fasta", 1, []);
    &compareFileLines("$expectedOutputDir/userInputFile.txt", "$runDirectory/userInputFile.txt", 1, []);

    &compareFileLines("$expectedOutputDir/inputSequences.fasta", "$runDirectory/inputSequences.fasta", 1, []);

    &compareFileLines("$expectedOutputDir/parameters.txt", "$runDirectory/parameters.txt", 1, ["seqs_in_batch_count", "test_mode", "job_name"]);
    &compareFileLines("$expectedOutputDir/peptideRulesFile", "$runDirectory/peptideRulesFile", 1, []);
  	
    #missing accession not written to fasta file
    unlike(&convertFileToString("$expectedOutputDir/inputSequences.fasta"), qr/BARKAN/, "appliction scan does not write fake accession to fasta file");

    #User log has key pieces of information written
    #TODO -- user log exists (after Test::File loaded)
    my $userLogString = &convertFileToString("$runDirectory/user.log");
    like($userLogString, qr/BARKAN was not found/, "application scan user log content, didn't find fake accessions");
    
    like($userLogString, qr/read from input file: 103/, "application scan user log content, total accessions");
    like($userLogString, qr/accessions found in modbase: 102/, "application scan user log content, peptides found vs missed");
    like($userLogString, qr/missed \(noted above in this log file\): 1/, "application scan user log content, peptides found vs missed");
    
    #Framework log has key pieces of information written and stats
    my $frameworkLogString = &convertFileToString("$runDirectory/framework.log");
    like($frameworkLogString, qr/read from input file: 103/, "application scan framework log content, total accessions");
    like($frameworkLogString, qr/accessions found in modbase: 102/, "application scan framework log content, peptides found vs missed");
    like($frameworkLogString, qr/missed \(noted above in this log file\): 1/, "application scan framework log content, peptides found vs missed");
    like($frameworkLogString, qr/BARKAN was not found/, "application scan framework log content, didn't find fake accessions");
    
    
    &testAndPostprocessFiles($runDirectory, $expectedOutputDir, "peptideRulesFile");
}

sub testApplicationCustomModel{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    $frontend->clear();
    my $applicationScanInput = &makeApplicationScanInput($inputDir);
    
    my $packageFileName = "$inputDir/userModelPackage";
    my $packageFh = FileHandle->new("<" . $packageFileName) || die "could not open $packageFileName\n";
    $applicationScanInput->{'svm_custom_model'} = $packageFh;

    my $runDirectory = $applicationScanInput->{"directory"};
    $applicationScanInput->{"svm_model"} = "custom";
    $frontend->process_user_input($applicationScanInput, $paramFileName);
    &compareFileLines("$expectedOutputDir/inputSequences.fasta", "$runDirectory/inputSequences.fasta", 1, []);
    &compareFileLines("$expectedOutputDir/parameters.txt", "$runDirectory/parameters.txt", 1, ["seqs_in_batch_count", "test_mode", "job_name", "using_custom_model", "svm_application_model", "benchmark_score_file"]);

    &compareFileLines("$expectedOutputDir/userCustomBenchmarkFile", "$runDirectory/userCustomBenchmarkFile", 0, []);
    &compareFileLines("$expectedOutputDir/userCustomModelFile", "$runDirectory/userCustomModelFile", 0, []);

    my $parameterString = &convertFileToString("$runDirectory/parameters.txt");
    like ($parameterString, qr/using_custom_model\tyes/, "custom model parameters, using_custom_model = yes written");
    like ($parameterString, qr/using_custom_model\tyes/, "custom model parameters, using_custom_model = yes written");
    unlike($parameterString, qr/svm_application_model/, "custom model parameters, svm_application_model not written");
    unlike($parameterString, qr/^benchmark_score_file/, "custom model parameters, benchmark_score_file not written");

    &testAndPostprocessFiles($runDirectory, $expectedOutputDir, "peptideRulesFile", "userCustomModelFile", "userCustomBenchmarkFile");
}


sub runApplicationScanErrorTests{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;

    &testInvalidApplicationFile($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testNoSeqsFoundScan($inputDir, $expectedOutputDir, $paramFileName, $frontend);
    &testValidRulesFile($inputDir, $expectedOutputDir, $paramFileName, $frontend);

}

sub testInvalidApplicationFile{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    my $applicationScanInput = &makeApplicationErrorInput($inputDir, "S");
    $applicationScanInput = &makeRulesFileInput($inputDir, $applicationScanInput);
    my $runDirectory = $applicationScanInput->{"directory"};
    
    #Valid application file -- all exceptions in readAndValidateApplicationFile()
    # -- note -- if frontend is ever cleared before this test, it will lose its parameters and readAndValidateApplicationFile will complain
    my $badAppFileToErrors = &getBadAppFileToErrorsMap();

    my $appFileErrorDirectory = $inputDir . "/applicationFileErrors";
    foreach my $badAppFile (keys %$badAppFileToErrors){

	my $appFh = FileHandle->new("<" . $appFileErrorDirectory . "/" . $badAppFile) || die "could not open bad application file $badAppFile";
	my $exceptionMessage = $badAppFileToErrors->{$badAppFile};
	throws_ok {$frontend->readAndValidateApplicationFile($appFh, $runDirectory)}
	qr /$exceptionMessage/, "exception if application scan peptide file $badAppFile formatted incorrectly";
    }
    
    my $missingApplicationFh;
    
    throws_ok {$frontend->readAndValidateApplicationFile($missingApplicationFh)}
    qr /No application target file/,  "exception if application scan file not provided";
}

sub testNoRulesFile{

    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    #proper rules file output if user didn't specify anything (should be one line that says "### No rules file specified")

    $frontend->clear();
    my $applicationScanInput = &makeApplicationScanInput($inputDir);  #reload fh
    $applicationScanInput->{"rules_file"} = 0;
    $frontend->process_user_input($applicationScanInput, $paramFileName);
    my $runDirectory = $applicationScanInput->{"directory"};
    like(&convertFileToString("$runDirectory/peptideRulesFile"), qr/\#\#\# No rules file specified/, "user specified no rules has correct output");
}


sub testNoSeqsFoundScan{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
     #Fail if none of the provided sequences found in modbase at all

    $frontend->clear();
    my $applicationScanInput = &makeApplicationErrorInput($inputDir, "S");  #reload fh
    $applicationScanInput = &makeRulesFileInput($inputDir, $applicationScanInput);
    my $applicationNoSeqsFoundFile = $inputDir . "/noSeqsFoundInput";
    my $noSeqsFoundFh = FileHandle->new("<" . $applicationNoSeqsFoundFile) || die "could not open no seqs found $applicationNoSeqsFoundFile";
    $applicationScanInput->{"application_file"} = $noSeqsFoundFh;
    throws_ok { $frontend->process_user_input($applicationScanInput, $paramFileName) } 
    qr /Although the error handling option/, 'exception if no user supplied sequences found in modbase at all in application scan mode';
}

sub testValidRulesFile{
    my ($inputDir, $expectedOutputDir, $paramFileName, $frontend) = @_;
    
    #Valid rules file -- all exceptions in readAndValidateRulesFile()
    
    my $badRulesFileToErrors = &getBadRulesFileToErrorsMap();
    
    my $rulesFileErrorDirectory = $inputDir . "/rulesFileErrors";
    foreach my $badRulesFile (keys %$badRulesFileToErrors){
	
	my $rulesFh = FileHandle->new("<" . $rulesFileErrorDirectory . "/" . $badRulesFile) || die "could not open bad rules file $badRulesFile";
	my $exceptionMessage = $badRulesFileToErrors->{$badRulesFile};
	throws_ok {$frontend->readAndValidateRulesFile($rulesFh, 8)}
	qr /$exceptionMessage/, "exception if application scan peptide file $badRulesFile formatted incorrectly";
    }
}


#Skip list are lines that might be different in test vs production mode, so don't compare these
sub compareFileLines{

    my ($firstFile, $secondFile, $sortFiles, $skipList) = @_;

    if ($sortFiles){
	my $firstSortedFile = $firstFile . "_sorted";
	my $firstSortCmd = "sort $firstFile > $firstSortedFile";
	system($firstSortCmd);

	my $secondSortedFile = $secondFile . "_sorted";
	my $secondSortCmd = "sort $secondFile > $secondSortedFile";
	system($secondSortCmd);

	$firstFile = $firstSortedFile;
	$secondFile = $secondSortedFile;
    }
    my $firstFileLines = &loadFile($firstFile, $skipList);
    my $secondFileLines = &loadFile($secondFile, $skipList);

    my $secondLineCounter = 0;
    
    foreach my $firstLine (@$firstFileLines){
	my $secondLine = $secondFileLines->[$secondLineCounter];
#	print STDERR "comparing lines $firstLine and $second
	is($firstLine, $secondLine, "lines in $firstFile and $secondFile match");
	$secondLineCounter++;
    }
    

    
}

sub loadFile{
    my ($fileName, $skipList) = @_;
    my @fileLines;
    my $fh = FileHandle->new("<" . $fileName) || die "could not open file $fileName for loading lines\n";
    while (<$fh>){
	chomp;
	my $line = $_;
	next if ($line =~ /^\s*$/);
	my $skipLine = 0;
	foreach my $skip (@$skipList){
	    if ($line =~ /$skip/){
		$skipLine = 1;
	    }
	}
	next if ($skipLine == 1);
	push (@fileLines, $line);
    }
    return \@fileLines;

}


sub convertSortedFileToString{

    my ($directory, $fileName) = @_;
    my $fullFileName = $directory . "/" . $fileName;
    my $fullSortedFileName = $directory . "/" . $fileName . "_sorted";
    
    my $sortCmd = "sort $fullFileName > $fullSortedFileName";
    system ($sortCmd);

    my $sortedString = &convertFileToString($fullSortedFileName);

    my $deleteCmd = "rm $fullSortedFileName";
    system($deleteCmd);
    return $sortedString;
}


sub convertFileToString{
    my ($fileName) = @_;
    my $fh = FileHandle->new("<" . $fileName) || die "could not open $fileName\n";
    my $string = "";
    while (<$fh>){
	chomp;
	$string .= $_;
    }
    return $string;
}


sub makeApplicationDefinedInput{
    my ($testInputDir) = @_;
    my $input;

    $input = &makeGlobalInputValues($input);
    $input = &makeApplicationInputValues($input, $testInputDir);

    $input->{'application_specification'} = 'D';

    return $input;
}

sub makeApplicationErrorInput{
    my ($inputDir, $applicationMode) = @_;
    my $input;

    $input = &makeGlobalInputValues($input);
    $input->{'svm_model'} = "grb";
    $input->{'server_mode'} = "application";

    $input->{'application_specification'} = $applicationMode;
    return $input;
}


sub makeTrainingErrorInput{
    my ($inputDir) = @_;
    my $input;

    $input = &makeGlobalInputValues($input);

    $input->{'server_mode'} = "training";
    $input->{'jackknife_fraction'} = "0.1";  #have to make this a string, otherwise converts to 0.1 which messes up the parameter comparison.  Might be an issue later.
    $input->{'training_iterations'} = 10;

    return $input;
}

sub makeRulesFileInput{
    my ($inputDir, $input) = @_;
    my $rulesFileName = "$inputDir/testRulesFileInput";
    my $rulesFh = FileHandle->new("<" . $rulesFileName) || die "could not open $rulesFileName\n";
    $input->{'rules_file'} = $rulesFh;
    return $input;
}

sub makeApplicationScanInput{
    my ($testInputDir) = @_;
    my $input;

    $input = &makeGlobalInputValues($input);
    $input = &makeApplicationInputValues($input, $testInputDir);

    $input = &makeRulesFileInput($testInputDir, $input);

    $input->{'application_specification'} = 'S';

    return $input;
}



sub makeApplicationInputValues{
    my ($input, $testInputDir) = @_;

    #add application input values (global ones; independent of scan mode vs defined mode)
    my $svmModel = "grb"; 
    my $applicationFileName = "$testInputDir/testApplicationFileInput";
    my $applicationFh = FileHandle->new("<" . $applicationFileName) || die "could not open $applicationFileName\n";
    
    $input->{'svm_model'} = $svmModel;
    $input->{'application_file'} = $applicationFh;
    $input->{'server_mode'} = "application";
    return $input;

}


sub makeTrainingInputValues{
    my ($testInputDir) = @_;

    my $input;
    $input = &makeGlobalInputValues($input);
    $input->{'server_mode'} = "training";
    $input->{'jackknife_fraction'} = "0.1";  #have to make this a string, otherwise converts to 0.1 which messes up the parameter comparison.  Might be an issue later.
    $input->{'training_iterations'} = 10;
    
    my $trainingFileName = "$testInputDir/testTrainingFileInput";
    my $trainingFh = FileHandle->new("<" . $trainingFileName) || die "could not open $trainingFileName\n";
    $input->{'training_file'} = $trainingFh;

    return $input;

}

sub getBadAppFileToErrorsMap{

    my $badAppFileToErrors;
    $badAppFileToErrors->{multipleEntries} = "more than one entry";
    $badAppFileToErrors->{noValidEntries} = "did not contain any";
    return $badAppFileToErrors;

}

sub getBadPeptideFileToErrorsMap{
    my $badPeptideFileToErrors;
    $badPeptideFileToErrors->{invalidResidue} = "consist only of the 20 standard amino"; 
    $badPeptideFileToErrors->{missingColumn} = "each line must be of the format";
    $badPeptideFileToErrors->{noEntries} = "did not contain any entries";
    $badPeptideFileToErrors->{noNumber} = "start position must be a number";
    $badPeptideFileToErrors->{numberInSequence} = "must consist of valid one";
    return $badPeptideFileToErrors;
    
}

sub getBadRulesFileToErrorsMap{
    my $badRulesFileToErrors;

    $badRulesFileToErrors->{allResiduesExcluded} = "cannot exclude all 20 residues";
    $badRulesFileToErrors->{samePositionTwice} = "found in two different places";
    $badRulesFileToErrors->{outOfBounds} = "score peptides of the same length";
    $badRulesFileToErrors->{missingNumber} = "begins with a number";
    $badRulesFileToErrors->{badResidue} = "20 standard amino acids";
    $badRulesFileToErrors->{spaceMissing} = "designated by one letter";


    return $badRulesFileToErrors;

}

sub testAndPostprocessFiles{

    my ($runDirectory, $expectedOutputDir, @otherFiles) = @_;
    
    my @fileNames =  ("user.log", "framework.log", "parameters.txt",  "inputSequences.fasta",  "sequenceBatches", "userInputFile.txt");

    if (@otherFiles){
	foreach my $file (@otherFiles){
	    push(@fileNames, $file);
	}
    }

    &checkFilesExist($runDirectory, @fileNames);
    push (@fileNames, "parameters.txt_sorted");
    push (@fileNames, "inputSequences.fasta_sorted");

    
#   &copyFiles($runDirectory, "$expectedOutputDir/observedOutput", @fileNames);
}

sub checkFilesExist{
    my ($runDirectory, @fileNames) = @_;
    foreach my $file (@fileNames){
	ok(-e "$runDirectory/$file",  "file $file successfully written");
    }
}


sub copyFiles{
    my ($sourceDir, $destinationDir, @fileList) = @_;
    my $cpCmd = "cp -r ";
    foreach my $file (@fileList){
	$cpCmd .= "$sourceDir/$file ";
    }
    $cpCmd .= $destinationDir;
    system($cpCmd);
    
}


sub makeGlobalInputValues{

    my ($input) = @_;

    my $email = 'dbarkan@salilab.org';                       $input->{'email'} = $email;
    my $name = 'peptide_server_test';                        $input->{'name'} = $name; 
    my $errorHandling = 'I';                                 $input->{'error_handling'} = $errorHandling;
    my $bestModel = 'nativeOverlap';                         $input->{'best_model'} = $bestModel; 
    my $directory = 
	File::Temp->newdir(CLEANUP => 1);  $input->{'directory'} = $directory;
    
    return $input;
}

# PCSS queries ModBase via SQL to get AA sequences for UniProt accessions.
# This won't work outside of the Sali lab, and will break if any of the
# data in ModBase changes, so instead provide a mock database handle that
# returns a snapshot of the database.
package MockDBH;

sub new {
  my ($invocant, $data_file) = @_;
  my $class = ref($invocant) || $invocant;
  my $self = {};
  bless($self, $class);
  $self->{accession_map} = $self->read_modbase_data($data_file);
  return $self;
}

sub read_modbase_data {
  my ($self, $data_file) = @_;
  my $acmap = {};
  open(FH, $data_file) or die "Cannot open $data_file: $!";
  for my $line (<FH>) {
    if ($line =~ /^#/) {
      next;
    }
    chomp $line;
    my ($uniprot_id, $seq_id, $seq) = split(/\t/, $line);
    $acmap->{$uniprot_id} = [$seq_id, $seq];
  }
  close(FH);
  return $acmap;
}

sub prepare {
  my ($self, $query) = @_;
  # Really we should return a prepared query here, but rather than create
  # another class, just return ourselves:
  return $self;
}

sub execute {
  my ($self, $accession) = @_;
  $self->{accession} = $accession;
}

sub fetchrow_array {
  my ($self) = @_;
  my $data = $self->{accession_map}->{$self->{accession}};
  if (defined $data) {
    return @$data;
  }
}

1;

use saliweb::Test;
use Test::More 'no_plan';
use Test::Builder;
use Test::Exception;
use Test::File::Contents;
use lib "/netapp/sali/peptide/lib";


use strict;
use DBI;
use File::Temp;


use ApplicationPipeline;
use CleavageSiteModel;
use SvmModel;
use Pipeline;
use FastaReader;
use JackknifeBenchmarker;
use LeaveOneOutBenchmarker;
use BenchmarkerPipeline;
use Benchmarker;

use_ok('peptide');


my $t = new saliweb::Test('peptide');

my $trainingSvmTestDir = "/modbase5/home/dbarkan/peptide/test/svmTraining/normalProcessing/";
my $looSvmTestDir = "/modbase5/home/dbarkan/peptide/test/svmTraining/leaveOneOut/";
my $errorTestDir = "/modbase5/home/dbarkan/peptide/test/svmTraining/errors/";

&runTrainingSvmTests($trainingSvmTestDir);
&runLeaveOneOutBenchmarkerTest($looSvmTestDir);
&runErrorTests($errorTestDir);



sub runTrainingSvmTests{

    my ($trainingSvmTestDir) = @_;

    my $inputDir = $trainingSvmTestDir . "/input";
    my $expectedOutputDir = $trainingSvmTestDir . "/expectedOutput";

    &testNormalProcessing($inputDir, $expectedOutputDir);
}


sub runLeaveOneOutBenchmarkerTest{
    my ($looSvmTestDir) = @_;
    my $inputDir = $looSvmTestDir . "/input";
    my $expectedOutputDir = $looSvmTestDir . "/expectedOutput";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";
    &updateParameters($parameterFile, "benchmark_class", "LeaveOneOut");

    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $expectedOutputFile = "$expectedOutputDir/modelPipelineResults.txt";
    my $observedOutputFile = "$runDir/modelPipelineResults.txt";

    &compareFileLines($expectedOutputFile, $observedOutputFile, 0, []);

    my $fh = FileHandle->new("<" . $observedOutputFile);
    my $classifications;
    while (<$fh>){
	chomp;
	my $line = $_;
	my @cols = split('\t', $line);
	if (scalar(@cols) > 3){
	    my $resultId = $cols[3];
	    my @resultIdEntries = split('\s', $resultId);
	    my $classification = $resultIdEntries[2];
	    $classifications->{$classification}++;
	}
    }
    my $positiveCount = $classifications->{"positive"};
    my $negativeCount = $classifications->{"negative"};
    ok($positiveCount == 51);
    ok($negativeCount == 372);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
}    

sub testNormalProcessing{
    my ($inputDir, $expectedOutputDir) = @_;
    
    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $expectedOutputFile = "$expectedOutputDir/modelPipelineResults.txt";
    my $observedOutputFile = "$runDir/modelPipelineResults.txt";

    &checkNormalOutput($expectedOutputFile, $observedOutputFile);

    

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);

}

sub runGetResultFieldErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "Testing calling SvmModel->getResultField() on invalid input\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineResultsFakeColumn.txt");

    
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "PeptidePipeline Result Field Error Test";
    &likeGlobalError($runDir, "invalid_result_field", $testName);
    &testErrorHandled($runDir, $testName);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
}

sub runInvalidSvmTrainingFileName{
    
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "testing missing svm input training file\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "svm_training_set_file_name", "/fakeDirectory/fakeFileName");
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "missing svm input training file";

    &likeGlobalError($runDirectory, "file_missing", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);

}



sub runInvalidResidueErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "Testing appropriate handling of non-standard AA in peptide\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineResultsInvalidResidue.txt");
    
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "PeptidePipeline Invalide Residue test";
    &likeGlobalError($runDir, "invalid_residue", $testName);
    &testErrorHandled($runDir, $testName);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
}





sub runErrorTests{
    my ($errorTestDir) = @_;


    my $errorInputDir = $errorTestDir . "/input";
    my $errorExpectedOutputDir = $errorTestDir . "/expectedOutput";

    &runPeptidePipelineOutputErrorTest($errorInputDir, $errorExpectedOutputDir);
    &runPeptidePipelineGlobalErrorTest($errorInputDir, $errorExpectedOutputDir);

    &testMissingFile($errorInputDir, $errorExpectedOutputDir, "peptide_pipeline_result_file_name", "missing peptide pipeline results file name");

    &runGetResultFieldErrorTest($errorInputDir, $errorExpectedOutputDir);
    &runInvalidResidueErrorTest($errorInputDir, $errorExpectedOutputDir);

    &runInvalidSvmTrainingFileName($errorInputDir, $errorExpectedOutputDir);
    &testBadSvmTrainingResult($errorInputDir, $errorExpectedOutputDir);
    &testBadSvmTestResult($errorInputDir, $errorExpectedOutputDir);
}


sub runPeptidePipelineGlobalErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "Testing proper handling of receiving global error from peptide pipeline\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineGlobalError");
    
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "PeptidePipeline Global Error Test";
    &likeGlobalError($runDir, "file_missing", $testName);
    &testErrorHandled($runDir, $testName);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
    
}


sub testBadSvmTrainingResult{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "testing error in running SVM train command\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";

    &updateParameters($parameterFile, "svm_score_file_name", "/fake/fakeScoreFile");

    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "error in SVM training";

    &likeGlobalError($runDirectory, "svm_failure", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);

}



sub testBadSvmTestResult{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "testing error in running SVM test command\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";

    &updateParameters($parameterFile, "svm_score_file_name", "/fake/fakeScoreFile");

    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "error in SVM test";

    &likeGlobalError($runDirectory, "svm_failure", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);

}


sub runPeptidePipelineOutputErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "Testing proper handling of receiving output error from peptide pipeline\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineOutputError");
    
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
    
    my $testName = "PeptidePipeline Output Error Test";
    &likeGlobalError($runDir, "output_error", $testName);
    &testErrorHandled($runDir, $testName);
}
sub testErrorHandled{

    my ($runDirectory, $testName) = @_;
    my $logFileName = $runDirectory . "/modelPipelineLog";
    like(&convertFileToString($logFileName), qr/ERROR/, "peptide pipeline log error written in test $testName");
}


sub testMissingFile{
    
    my ($inputDir, $expectedOutputDirectory, $paramName, $testName) = @_;
    
    print STDERR "testing missing file $testName\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, $paramName, "fake_file");
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    &likeGlobalError($runDirectory, "file_missing", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDirectory/observedOutput/";
    system ($cmd);
}


sub likeGlobalError{
    my ($runDirectory, $errorName, $testName) = @_;
    
    my $resultsFile = $runDirectory . "/modelPipelineResults.txt";
    &likeColumnHeader($resultsFile, $testName);
    &likeGlobalErrorName($resultsFile, $errorName, $testName);
}
sub likeColumnHeader{
    my ($resultsFile, $testName) = @_;

    my $fh = FileHandle->new("<" . $resultsFile) || die "could not open pipeline results file (likeColumnHeader): $!\n";
    my $columnHeaderLine = <$fh>;
    chomp $columnHeaderLine;

    my $columnHeaderExpectedString = "TP_count\tFP_count\tScore";

    is($columnHeaderLine, $columnHeaderExpectedString, "column header string written correctly (testing $testName)");
    $fh->close();
}

sub likeGlobalErrorName{
    my ($resultsFile, $errorName, $testName) = @_;
    my $fh = FileHandle->new("<" . $resultsFile) || die "could not open pipeline results file (likeColumnHeader): $!\n";
    my $columnHeaderLine = <$fh>;
    my $errorLine = <$fh>;
    
    like($errorLine, qr/$errorName/, "got expected global error name $errorName (testing $testName");


}



sub convertFileToString{
    my ($fileName) = @_;

    my $fh = FileHandle->new("<" . $fileName) || die "could not open $fileName\n";
    my $string = "";
    while (<$fh>){
	chomp;
	$string .= $_;
    }
    $fh->close();

    return $string;
}




sub makeRunDirectory{
	
    my ($inputDirectory) = @_;

    #make full pipeline/runName directory
    my $tmpDirectory = File::Temp->tempdir("XXXX", CLEANUP => 1);    
    
    my $runDir = $tmpDirectory . "/testing_run";
    my $cmd = "mkdir -p $runDir";
    system ($cmd);

    #copy all input to runName
    my $cpInputCmd = "cp -r  $inputDirectory/* $runDir/";
    system($cpInputCmd);

    #update parameters with these directories
    my $parameterFile = "$runDir/parameters.txt";
    &updateParameters($parameterFile, "cluster_pipeline_directory", $tmpDirectory);
    &updateParameters($parameterFile, "head_node_preprocess_directory", $runDir);
    
    my $fh = FileHandle->new(">>" . $parameterFile) || die "could not open input parameter file $parameterFile\n";
    print $fh "run_name\ttesting_run\n";

    return $runDir;
}

sub updateParameters{
    my ($parameterFile, $newParamName, $newParamValue) = @_;
    my $fh = FileHandle->new("<" . $parameterFile) || die "could not open input parameter file $parameterFile\n";
    my @lines;
    
    while (<$fh>){
	chomp;
	my $line = $_;
	push (@lines, $line);
    }

    $fh->close();
    
    my $foundParamName = 0;

    #overwrite param file with updates
    my $outputFh = FileHandle->new(">$parameterFile") || die "could not open parameter file $parameterFile\n";
    foreach my $line (@lines){
	my ($paramName, $paramValue) = split("\t", $line);
	if ($paramName eq $newParamName){
	    my $line = $newParamName . "\t" . $newParamValue . "\n";
	    print $outputFh $line;
	    $foundParamName = 1;
	}
	else {
	    print $outputFh $line . "\n";
	}
    }

    die "did not find param name $newParamName to update\n" unless $foundParamName;
}

sub checkNormalOutput{
    my ($expectedOutputFile, $observedOutputFile) = @_;
    my $expectedFileLines = &loadFile($expectedOutputFile);
    my $observedFileLines = &loadFile($observedOutputFile);
    
    my $previousObservedNegativeCount = 0;

    my $oLineCount = 0;
    foreach my $eLine (@$expectedFileLines){
	my $oLine = $observedFileLines->[$oLineCount];
	$oLineCount++;
	my @eCols = split('\t', $eLine);
	my @oCols = split('\t', $oLine);
	if (scalar(@eCols) == 3){
	    my $ePositiveCount = $eCols[0];
	    my $oPositiveCount = $oCols[0];
	    ok($ePositiveCount == $oPositiveCount, "expected and observed positive counts match");
	    
	    my $oNegativeCount = $oCols[1];
	    ok($oNegativeCount >= $previousObservedNegativeCount, "observed negative counts increase with each line");
	    $previousObservedNegativeCount = $oNegativeCount;
	    
	    ok(scalar(@oCols) == scalar(@eCols), "observed and expected files have same number of columns");
	}
	elsif(scalar(@eCols) == 4){
	    my $eNegatives = $eCols[3];
	    my $oNegatives = $oCols[3];

	    ok($eNegatives == $oNegatives, "observed and expected files have same number of total negatives");
	}
	else {
	    die "did not get expected number of columns in expected file $expectedOutputFile\n";
	}
    }

    my $observedFileLineCount = scalar(scalar @$observedFileLines);
    ok($observedFileLineCount == 7, "Results file has expected number of positives"); #stats
    my $lastLine = $observedFileLines->[6]; #get last line
    my @cols = split('\t', $lastLine);
    my $negativeCount = $cols[3];
    ok($negativeCount == 326, "Results file has expected number of negatives"); #stats

}

sub compareFileLines{

    my ($firstFile, $secondFile, $sortFiles, $skipList) = @_;

    my $firstSortedFile;
    my $secondSortedFile;

    if ($sortFiles){

	$firstSortedFile = File::Temp->new();
	my $firstSortedFileName = $firstSortedFile->filename();
	$firstSortedFile->close();

	$secondSortedFile = File::Temp->new();
	my $secondSortedFileName = $secondSortedFile->filename();
	$secondSortedFile->close();

	my $firstSortCmd = "sort $firstFile > $firstSortedFileName";
	system($firstSortCmd);

	my $secondSortCmd = "sort $secondFile > $secondSortedFileName";
	system($secondSortCmd);

	$firstFile = $firstSortedFileName;
	$secondFile = $secondSortedFileName;
    }

    my $firstFileLines = &loadFile($firstFile, $skipList);
    my $secondFileLines = &loadFile($secondFile, $skipList);

    my $secondLineCounter = 0;
    foreach my $firstLine (@$firstFileLines){
	my $secondLine = $secondFileLines->[$secondLineCounter];

	is($firstLine, $secondLine, "lines in $firstFile and $secondFile match");
	$secondLineCounter++;
    }
    unlink $firstSortedFile;
    unlink $secondSortedFile;
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

use saliweb::Test;
use Test::More 'no_plan';
use Test::Builder;
use Test::Exception;
use Test::File::Contents;
use lib "/netapp/sali/peptide/lib";

#use PeptidePipeline;


use strict;
use DBI;
use File::Temp;


use ApplicationPipeline;
use CleavageSiteModel;
use SvmModel;
use Pipeline;
use FastaReader;

use_ok('peptide');


my $t = new saliweb::Test('peptide');


my $applicationSvmTestDir = "/modbase5/home/dbarkan/peptide/test/svmApplication/normalProcessing/";
my $errorTestDir = "/modbase5/home/dbarkan/peptide/test/svmApplication/errors/";

&runApplicationSvmTests($applicationSvmTestDir);
&runErrorTests($errorTestDir);

sub runApplicationSvmTests{

    my ($applicationSvmTestDir) = @_;

    my $inputDir = $applicationSvmTestDir . "/input";
    my $expectedOutputDir = $applicationSvmTestDir . "/expectedOutput";

    &testNormalProcessing($inputDir, $expectedOutputDir);


}

sub testNormalProcessing{
    my ($inputDir, $expectedOutputDir) = @_;
    
    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    my $pipeline = ApplicationPipeline->new($parameterFile);

    print STDERR "testing normal processing\n";

    $pipeline->execute();
    $pipeline->finalize();

    my $expectedOutputFile = "$expectedOutputDir/modelPipelineResults.txt";
    my $observedOutputFile = "$runDir/modelPipelineResults.txt";
    print STDERR "normal processing: looking at expected output file $expectedOutputFile"
    &compareFileLines($expectedOutputFile, $observedOutputFile, 1, []);

    my $logFileName = $runDir . "/modelPipelineLog";
    like(&convertFileToString($logFileName), qr/Wrote results for 49 sequences containing 936 total peptides/, "correct number of peptides and sequences processed correctly"); #stats
    like(&convertFileToString($logFileName), qr/1 sequences had no peptides parsed in the feature pipeline/, "no peptides parsed message written in log"); #stats

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
    &testMissingFile($errorInputDir, $errorExpectedOutputDir, "benchmark_score_file", "missing benchmark score file");

    &runGetResultFieldErrorTest($errorInputDir, $errorExpectedOutputDir);
    &runInvalidResidueErrorTest($errorInputDir, $errorExpectedOutputDir);

    &runInvalidSvmApplicationFileName($errorInputDir, $errorExpectedOutputDir);

    &testMissingFile($errorInputDir, $errorExpectedOutputDir, "svm_application_model", "missing svm model file");

    &testBadSvmResult($errorInputDir, $errorExpectedOutputDir);

}

sub testBadSvmResult{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "testing error in running SVM application command\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";

    &updateParameters($parameterFile, "svm_score_file_name", "/fake/fakeScoreFile");

    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "error in SVM application";

    &likeGlobalError($runDirectory, "svm_failure", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);

}


sub runInvalidSvmApplicationFileName{
    
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "testing missing svm input application file\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "svm_application_set_file_name", "/fakeDirectory/fakeFileName");
    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "missing svm input application file";

    &likeGlobalError($runDirectory, "file_missing", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);

}

sub runGetResultFieldErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "Testing calling SvmModel->getResultField() on invalid input\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineResultsFakeColumn.txt");

    
    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "PeptidePipeline Result Field Error Test";
    &likeGlobalError($runDir, "invalid_result_field", $testName);
    &testErrorHandled($runDir, $testName);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
}



sub runInvalidResidueErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "Testing appropriate handling of non-standard AA in peptide\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineResultsInvalidResidue.txt");
    
    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "PeptidePipeline Invalide Residue test";
    &likeGlobalError($runDir, "invalid_residue", $testName);
    &testErrorHandled($runDir, $testName);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
}


sub runPeptidePipelineGlobalErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "Testing proper handling of receiving global error from peptide pipeline\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineGlobalError");
    
    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $testName = "PeptidePipeline Global Error Test";
    &likeGlobalError($runDir, "file_missing", $testName);
    &testErrorHandled($runDir, $testName);

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
    
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
    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    &likeGlobalError($runDirectory, "file_missing", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDirectory/observedOutput/";
    system ($cmd);
}



sub likeOutputError{
    my ($runDirectory, $testName) = @_;
    my $resultsFile = $runDirectory . "/modelPipelineResults.txt";
    my $fh = FileHandle->new("<" . $resultsFile) || die "could not open pipeline results file $resultsFile (likeOutputError): $!\n";
    my $line = <$fh>;
    like($line, qr/output/, "got expected output error (testing $testName)");
    my $nextLine = <$fh>;
    is($nextLine, undef, "only one error line in results file $resultsFile\n");
}



sub runPeptidePipelineOutputErrorTest{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "Testing proper handling of receiving output error from peptide pipeline\n";

    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";

    &updateParameters($parameterFile, "peptide_pipeline_result_file_name", "peptidePipelineOutputError");
    
    my $pipeline = ApplicationPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $cmd = "cp -r $runDir/* $expectedOutputDir/observedOutput/";
    system($cmd);
    
    my $testName = "PeptidePipeline Output Error Test";
    &likeGlobalError($runDir, "output_error", $testName);
    &testErrorHandled($runDir, $testName);
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

    my $columnHeaderExpectedString = "Uniprot Accession	SVM Score	TPR	FPR	Peptide Sequence	Peptide Start	Peptide End	Peptide Secondary Structure Type	Peptide Accessibility Prediction	Disopred Prediction	PSIPRED Prediction	Model URL	Total Models For Sequence	Models Containing Peptide	Target Start	Target End	Model Score	Dope Score	TSVMod Native Overlap	TSVMod Method	Template Sequence Identity	Model Coverage	Loop Length	Template PDB ID	Peptide Similarity To Template	Corresponding Sequence in Template	Peptide Structure Values	Peptide Predicted Accessibility Fraction	Disopred Scores	PSIPRED Scores	Sequence ID	Model ID	Protein Name	Errors	";

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

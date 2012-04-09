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



use PeptidePipeline;
use Pipeline;
use FastaReader;
use_ok('peptide');


my $skipLongTests = 1;


my $t = new saliweb::Test('peptide');
    

my $applicationScanTestDir = "/modbase5/home/dbarkan/peptide/test/pipeline/applicationScan/";
my $applicationDefinedTestDir = "/modbase5/home/dbarkan/peptide/test/pipeline/applicationDefined/";
my $errorTestDir = "/modbase5/home/dbarkan/peptide/test/pipeline/errors";
my $noRulesTestDir = "/modbase5/home/dbarkan/peptide/test/pipeline/noRules";


&runApplicationScanTests($applicationScanTestDir);
&runApplicationDefinedTests($applicationDefinedTestDir);
&runErrorTests($errorTestDir) unless $skipLongTests;
&runNoRulesTests($noRulesTestDir) unless $skipLongTests;


################################################################################################################################
# runApplicationScanTests
# Tests normal processing of pipeline in ApplicationScan mode, where a rules file is provided and peptides are parsed from it,
# and then features are evaluated on those peptides. Also tests new generation of sequence-based structure prediction output files,
# which takes about ten minutes to run, and special cases of when no peptides are parsed from a sequence.
#
# General control flow:
# 1. Input files are read from this mode's input directory (within the sequenceBatches/seq_batch_1 directory)
#    They appear as if they had just been copied to the cluster from the backend, except this test only looks at one 'sequence batch' and 
#    uses that as input instead of using anything from the job directory
# 2. Test makes a temporary directory to run the job in, and updates the appropriate pipeline parameters to point to this directory.
# 3. All input files from input directory is copied to the temporary directory.
# 4. Pipeline runs as normal (all sequence and structure methods processed)
# 5. Expected output (located in this mode's expectedOutput directory, currently no sequence batch) is compared to observed output.
#
# Testing sequence-based methods proceeds similarly, except that a single hardcoded modbase sequence id is processed. A new input
# fasta file is generated for this, and new disopred and psipred empty directories are specified to force result file generation
# for these methods. The results are read to make sure expected structure and disorder types were written to the file (i.e. it 
# completed successfully).
#
# Testing no peptides parsed just has an overly restrictive peptide rules file applied when scanning sequences, and checks to make
# sure a keyword was written.
################################################################################################################################
sub runApplicationScanTests{
    my ($applicationScanTestDir) = @_;
    my $inputDir = $applicationScanTestDir . "/input";
    my $expectedOutputDir = $applicationScanTestDir . "/expectedOutput";

    &testNormalApplicationScan($inputDir, $expectedOutputDir);
    &testSequenceBasedMethods($inputDir, $expectedOutputDir) unless $skipLongTests;
}

sub runApplicationDefinedTests{
    my ($applicationDefinedTestDir) = @_;
    my $inputDir = $applicationDefinedTestDir . "/input";
    my $expectedOutputDir = $applicationDefinedTestDir . "/expectedOutput";

    &testNormalApplicationDefined($inputDir, $expectedOutputDir);
}


sub testNormalApplicationScan{

    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "testing normal application scan processing\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    print STDERR "testing normal processing\n";

    $peptidePipeline->parsePeptidesFromSequences();
    
    $peptidePipeline->getBestModels();
    
    $peptidePipeline->parseDsspResults();
    
    $peptidePipeline->getProteinNames();

    $peptidePipeline->runPsipred();
    
    $peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();
    
    $peptidePipeline->finalize();

    my %psipredValues = ("A" => 1, "B" => 1, "L" => 1);
    my %disopredValues = ("O" => 1, "D" => 1);

    &assessSequenceMethod($runDirectory, "PSIPRED Prediction", \%psipredValues);
    &assessSequenceMethod($runDirectory, "Disopred Prediction", \%disopredValues);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    
    system ($cmd);

    my $expectedOutputFile = "$expectedOutputDir/peptidePipelineResults.txt";
    my $observedOutputFile = "$runDirectory/peptidePipelineResults.txt";

    &compareFileLines($expectedOutputFile, $observedOutputFile, 1, []);

    my $logFile = "$runDirectory/peptidePipelineLog";

    like(&convertFileToString($logFile), qr/peptides\. 0 peptides had/, "Testing normal processing log file did not contain errors");
    like(&convertFileToString($logFile), qr/Did not parse peptides/, "Testing normal processing log correctly noted that one protein didn't have any peptides parsed");
    like(&convertFileToString($logFile), qr/lines for 50 sequences containing 936 peptides/, "Testing normal processing application scan wrote correct number of peptides"); #stats
    like(&convertFileToString($logFile), qr/and 190 peptides had a best-scoring model/, "Testing normal processing application scan found correct number of models"); #stats
    #compare peptide pipeline results output file lines
}


sub testNormalApplicationDefined{

    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "testing normal application defined processing\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    print STDERR "testing normal processing\n";

    $peptidePipeline->readPeptideInputFile();
    
    $peptidePipeline->getProteinNames();

    $peptidePipeline->getBestModels();
    
    $peptidePipeline->parseDsspResults();
    
    $peptidePipeline->runPsipred();
    
    $peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();
    
    $peptidePipeline->finalize();

    my %psipredValues = ("A" => 1, "B" => 1, "L" => 1);
    my %disopredValues = ("O" => 1, "D" => 1);

    &assessSequenceMethod($runDirectory, "PSIPRED Prediction", \%psipredValues);
    &assessSequenceMethod($runDirectory, "Disopred Prediction", \%disopredValues);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    
    system ($cmd);

    my $expectedOutputFile = "$expectedOutputDir/peptidePipelineResults.txt";
    my $observedOutputFile = "$runDirectory/peptidePipelineResults.txt";

    #compare peptide pipeline results output file lines
    &compareFileLines($expectedOutputFile, $observedOutputFile, 1, []);

    my $logFile = "$runDirectory/peptidePipelineLog";

    like(&convertFileToString($logFile), qr/peptides\. 0 peptides had/, "Testing normal processing log file did not contain errors");
    like(&convertFileToString($logFile), qr/lines for 18 sequences containing 22 peptides/, "Testing normal processing application defined wrote correct number of peptides"); #stats
    like(&convertFileToString($logFile), qr/and 13 peptides had a best-scoring model/, "Testing normal processing application defined found correct number of models"); #stats

}

sub testSequenceBasedMethods{

    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "testing sequence based methods\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";

    &updateParameters($parameterFile, "disopred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "psipred_results_dir", $runDirectory);
    my $sequenceFastaFile = "sequenceMethods.fasta";
    my $singleSequenceId = "c82f2efd57f939ee3c4e571708dd31a8MTMDEGEN";
    &createFastaFile($runDirectory, $sequenceFastaFile, $singleSequenceId);
    &updateParameters($parameterFile, "input_fasta_file_name", $sequenceFastaFile); 

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    print STDERR "testing normal processing\n";

    $peptidePipeline->parsePeptidesFromSequences();
    
    $peptidePipeline->getBestModels();
    
    $peptidePipeline->parseDsspResults();
    
    $peptidePipeline->runPsipred();
    
    $peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my %psipredValues = ("A" => 1, "B" => 1, "L" => 1);
    my %disopredValues = ("O" => 1, "D" => 1);

    &assessSequenceMethod($runDirectory, "PSIPRED Prediction", \%psipredValues);
    &assessSequenceMethod($runDirectory, "Disopred Prediction", \%disopredValues);
    
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    
    system ($cmd);
}




################################################################################################################################
sub runErrorTests{
    my ($errorTestDir) = @_;
    my $errorInputDir = $errorTestDir . "/input";
    my $errorExpectedOutputDir = $errorTestDir . "/expectedOutput";

    #Global errors
     &testNoPeptidesParsedInvalidColumn($errorInputDir, $errorExpectedOutputDir);
     &testMissingFile($errorInputDir, $errorExpectedOutputDir, "input_fasta_file_name", "missingInputFasta");
     &testMissingFile($errorInputDir, $errorExpectedOutputDir, "rules_file_name", "missingRulesFile");
     &testMissingFile($errorInputDir, $errorExpectedOutputDir, "model_table", "missingModelTable");
     &testMissingUserDefinedFasta($errorInputDir, $errorExpectedOutputDir, "input_fasta_file_name", "missingUserDefinedFasta");
     &testUserDefinedAllMismatches($errorInputDir, $errorExpectedOutputDir, "input_fasta_file_name", "userDefinedAllMismatchFasta");


     #DSSP / model Errors
     &testMissingDsspFile($errorInputDir, $errorExpectedOutputDir);
     &testDsspMismatch($errorInputDir, $errorExpectedOutputDir);
     &testInvalidModelLength($errorInputDir, $errorExpectedOutputDir);
     &testSolventExposureError($errorInputDir, $errorExpectedOutputDir);
     &testDsspRegexError($errorInputDir, $errorExpectedOutputDir);
     &testDsspNoPeptideError($errorInputDir, $errorExpectedOutputDir);
     &testDsspStructureTypeError($errorInputDir, $errorExpectedOutputDir);
    
     #PSI-PRED errors
     &testPsipredMismatch($errorInputDir, $errorExpectedOutputDir);
     &testPsipredStructureTypeError($errorInputDir, $errorExpectedOutputDir);
     &testPsipredNoPeptideError($errorInputDir, $errorExpectedOutputDir);
     &testPsipredMissingFile($errorInputDir, $errorExpectedOutputDir);        

     #Disopred errors
     &testDisopredMissingFile($errorInputDir, $errorExpectedOutputDir);
     &testDisopredMismatch($errorInputDir, $errorExpectedOutputDir);
     &testDisopredDisorderTypeError($errorInputDir, $errorExpectedOutputDir);
     &testDisopredNoPeptideError($errorInputDir, $errorExpectedOutputDir);
    
     #Column errors
     &testNoColumnInfo($errorInputDir, $errorExpectedOutputDir);
     &testInvalidColumn($errorInputDir, $errorExpectedOutputDir);
}







sub testNoPeptidesParsedInvalidColumn{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test no peptides parsed and output error with invalid column\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "rules_file_name", "restrictiveRulesFile");
    
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    $peptidePipeline->{ColumnInfo} = 0;
    $peptidePipeline->parsePeptidesFromSequences();
    

    if ($peptidePipeline->checkInput()){

	$peptidePipeline->getBestModels();
	$peptidePipeline->parseDsspResults();
	$peptidePipeline->runDisopred();
	$peptidePipeline->runPsipred();
	$peptidePipeline->printAllPeptides();
	$peptidePipeline->writeUserResults();
    }
    else {
	$peptidePipeline->writeNoInput();
    }
    my $testName = "loadColumnErrorNoPeptidesParsed";
    
    &likeOutputError($runDirectory, $testName);
    &testErrorHandled($runDirectory, $testName);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);
}


sub testInvalidColumn{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test invalid column\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";

    &updateParameters($parameterFile, "column_info_file", "$inputDir/errorColumnInfo.txt");

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->runDisopred();
    

    my $testName = "loadColumnError";
    
    &likeOutputError($runDirectory, $testName);
    &testErrorHandled($runDirectory, $testName);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);
}


sub testNoColumnInfo{

    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test no column info\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    
    $peptidePipeline->{ColumnInfo} = 0;

    $peptidePipeline->writeUserResults();
    
    my $testName = "loadColumnError";
    
    &likeOutputError($runDirectory, $testName);
    &testErrorHandled($runDirectory, $testName);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);
}



sub testDisopredMissingFile{

    my ($inputDir, $expectedOutputDir) = @_;
    
    print STDERR "test disopred missing file\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");    
    &updateParameters($parameterFile, "disopred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "run_disopred_cmd", "fake");
    
    my ($existingDisopredFh, $outputFile) = &createDisopredErrorDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    my $testName = "disopredMissingFile";
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "no_disopred_result_file", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}



sub testDisopredNoPeptideError{
    my ($inputDir, $expectedOutputDir) = @_;
    
    print STDERR "test disopred no peptide error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "disopred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    &createDisopredTruncatedFileDir($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");
    
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    my $testName = "disopredNoPeptideError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "no_disopred_peptide_sequence", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}


sub testDisopredDisorderTypeError{
    my ($inputDir, $expectedOutputDir) = @_;

    print STERR "test disopred disorder type error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "disopred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    #create fake disopred where 48e177 seq is the only sequence, rename all AAs to X's in disopred file to force mismatch
    &createDisopredFakeDisorderDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");
    
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    my $testName = "disopredDisorderTypeError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "disopred_format_error", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}


sub testDisopredMismatch{


    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test disopred mismatch\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "disopred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    #create fake disopred where 48e177 seq is the only sequence, rename all AAs to X's in disopred file to force mismatch
    &createDisopredFakeAaDir($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");
    
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    my $testName = "disopredMismatch";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "disopred_sequence_mismatch", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}





################################################################################################################################
sub testNoRulesProcessing{

   my ($inputDir, $expectedOutputDir) = @_;
   
   print STDERR "testing no rules processing\n";

   my $runDirectory = &makeRunDirectory($inputDir);

   my $parameterFile = $runDirectory . "/parameters.txt";

   my $emptyRulesFile = "emptyRulesFile";
   my $touchCmd = "touch $runDirectory/$emptyRulesFile";
   system($touchCmd);
   &updateParameters($parameterFile, "rules_file_name", $emptyRulesFile);

   my $peptidePipeline = PeptidePipeline->new($parameterFile);
   
   $peptidePipeline->parsePeptidesFromSequences();

   $peptidePipeline->getProteinNames();

   $peptidePipeline->getBestModels();
   
   $peptidePipeline->parseDsspResults();
   
   $peptidePipeline->runPsipred();
   
   $peptidePipeline->runDisopred();
   
   $peptidePipeline->writeUserResults();
   
   my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
   
   system ($cmd);

   my $expectedOutputFile = "$expectedOutputDir/peptidePipelineResults.txt";
   my $observedOutputFile = "$runDirectory/peptidePipelineResults.txt";
   
   &compareFileLines($expectedOutputFile, $observedOutputFile, 1, []);
   
   my $logFile = "$runDirectory/peptidePipelineLog";
   
   like(&convertFileToString($logFile), qr/peptides\. 0 peptides had/, "Testing normal processing log file did not contain errors");
   like(&convertFileToString($logFile), qr/lines for 5 sequences containing 1204 peptides/, "Testing normal processing no rules run wrote correct number of peptides"); #stats
   like(&convertFileToString($logFile), qr/and 1130 peptides had a best-scoring model/, "Testing normal processing no rules run found correct number of models"); #stats


}


sub runNoRulesTests{

    my ($noRulesTestDir) = @_;
    my $noRulesInputDir = $noRulesTestDir . "/input";
    my $noRulesExpectedOutputDir = $noRulesTestDir . "/expectedOutput";

    &testNoRulesProcessing($noRulesInputDir, $noRulesExpectedOutputDir);

}


sub assessSequenceMethod{

    my ($runDirectory, $columnName, $values) = @_;
    my $resultsFile = $runDirectory . "/peptidePipelineResults.txt";
    my $fh = FileHandle->new("<" . $resultsFile) || die "could not open $resultsFile in assessSequenceMethod()\n";
    my $lineCounter = 0;
    my $targetColNumber;
    while (<$fh>){
	chomp;
	my $line = $_;
	next if ($line =~ /no_peptides_parsed/);  #normal processing may have one or more examples of this. 
	if ($lineCounter == 0){
	    $lineCounter++;
	    my @cols = split('\t', $line);
	    my $columnCounter = 1;
	    foreach my $col (@cols){
		if ($col eq $columnName){
		    $targetColNumber = $columnCounter;
		}
		$columnCounter++;
	    }
	    die "did not find column name $columnName\n" unless $targetColNumber;
	}
	else {
	    my @cols = split('\t', $line);
	    my $targetValue = $cols[$targetColNumber - 1];
	    my $valueRegex = join('|', keys %$values);
	    like($targetValue, qr/^[$valueRegex]+$/, "sequenceMethod $columnName output correctly");
	}
    }
}
   




sub createDisopredErrorDirectory{

    my ($runDir, $testSequenceId, $controlSequenceId) = @_;

    #make input fasta file that is just testSequenceId and controlSequenceId
    my $inputFastaFile =  $runDir . "/inputSequences.fasta";
    my $reader = FastaReader->new($inputFastaFile, 1);
    $reader->read();
    my $sequences = $reader->getSequences();

    my $disopredDirectory = "/netapp/sali/peptide/data/landing/disopred/disopredResults/";
    my $outputFastaFile = $runDir . "/errorInput.fasta";
    my $outputFastaFh = FileHandle->new(">" . $outputFastaFile) || die "could not open $outputFastaFile";
    
    foreach my $sequenceHeader (keys %$sequences){
	my @cols = split('\|', $sequenceHeader);
	my $sequenceId = $cols[0];
	if ($sequenceId eq $testSequenceId || $sequenceId eq $controlSequenceId){
	    print $outputFastaFh ">" . $sequenceHeader . "\n";
	    my $proteinSequenceArray = $sequences->{$sequenceHeader};
	    my $proteinSequence = join("", @$proteinSequenceArray);
	    print $outputFastaFh $proteinSequence . "\n";
	}
    }
    $outputFastaFh->close();

    #copy control sequence disopred file to run directory
    $controlSequenceId =~ /^(\S\S).*/;
    my $controlPrefix = $1;
    my $controlDisopredDir = "$runDir/$controlPrefix/";
    my $controlCmd = "mkdir -p $controlDisopredDir";
    system ($controlCmd);
    my $controlCpCmd = "cp $disopredDirectory/$controlPrefix/$controlSequenceId" . ".diso $controlDisopredDir";
    system($controlCpCmd);
   
    #get filehandle for test sequence input and output
    $testSequenceId =~ /^(\S\S).*/;
    my $prefix = $1;
    my $disopredFile = "$disopredDirectory/$prefix/$testSequenceId" . ".diso";
    my $disopredFh = FileHandle->new($disopredFile) || die "could not open disopred file $disopredFile\n";
    my $fakeDisopredDir =  "$runDir/$prefix/";
    my $cmd = "mkdir -p $fakeDisopredDir";
    system ($cmd);

    my $outputFile  = $fakeDisopredDir . "/$testSequenceId" . ".diso";    


    return ($disopredFh, $outputFile);
}


sub createDisopredFakeAaDir{

    my ($runDir, $sequenceId, $controlSequenceId) = @_;
    
    my ($disopredFh, $outputFile) = &createDisopredErrorDirectory($runDir, $sequenceId, $controlSequenceId);
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output disopred file $outputFile\n";
    for (my $i = 0; $i < 5; $i++){
	<$disopredFh>;
    }

    while (<$disopredFh>){
	chomp;
	my $line = $_;
	if ($line =~ /(\s*\d+\s)(\w)(.*)/){
	    my $firstPart = $1;
	    my $residue = $2;
	    my $secondPart = $3;
	    print $outputFh $firstPart . "X" . $secondPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}


sub createDisopredTruncatedFileDir{

    my ($runDir, $sequenceId, $controlSequenceId) = @_;
    
    my ($disopredFh, $outputFile) = &createDisopredErrorDirectory($runDir, $sequenceId, $controlSequenceId);
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output disopred file $outputFile\n";
    for (my $i = 0; $i < 5; $i++){
	<$disopredFh>;
    }

    my $counter = 0;
    while (<$disopredFh>){
	$counter++;
	last if ($counter > 5);
	chomp;
	my $line = $_;
	print $outputFh $line . "\n";
    }
}



sub createDisopredFakeDisorderDirectory{

    my ($runDir, $sequenceId, $controlSequenceId) = @_;
    
    my ($disopredFh, $outputFile) = &createDisopredErrorDirectory($runDir, $sequenceId, $controlSequenceId);
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output disopred file $outputFile\n";
    for (my $i = 0; $i < 5; $i++){
	<$disopredFh>;
    }

    while (<$disopredFh>){
	chomp;
	my $line = $_;
	if ($line =~ /(\s*\d+\s\w\s)(.)(.*)/){
	    my $firstPart = $1;
	    my $disorderType = $2;
	    my $secondPart = $3;
	    print $outputFh $firstPart . "X" . $secondPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}


sub testPsipredMissingFile{

    my ($inputDir, $expectedOutputDir) = @_;
    
    print STDERR "testing psipred missing file\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");    
    &updateParameters($parameterFile, "psipred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "run_psipred_cmd", "fake");
    
    my ($existingPsipredFh, $outputFile) = &createPsipredErrorDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    $peptidePipeline->parsePeptidesFromSequences();
    
    #$peptidePipeline->getBestModels();
    
    #$peptidePipeline->parseDsspResults();
    
    $peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my $testName = "psipredMissingFile";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "no_psipred_result_file", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);


}


sub createPsipredErrorDirectory{

    my ($runDir, $testSequenceId, $controlSequenceId) = @_;

    #make input fasta file that is just testSequenceId and controlSequenceId
    my $inputFastaFile =  $runDir . "/inputSequences.fasta";
    my $reader = FastaReader->new($inputFastaFile, 1);
    $reader->read();
    my $sequences = $reader->getSequences();

    my $psipredDirectory = "/netapp/sali/peptide/data/landing/psipred/psipredResults/";
    my $outputFastaFile = $runDir . "/errorInput.fasta";
    my $outputFastaFh = FileHandle->new(">" . $outputFastaFile) || die "could not open $outputFastaFile";
    
    foreach my $sequenceHeader (keys %$sequences){
	my @cols = split('\|', $sequenceHeader);
	my $sequenceId = $cols[0];
	if ($sequenceId eq $testSequenceId || $sequenceId eq $controlSequenceId){
	    print $outputFastaFh ">" . $sequenceHeader . "\n";
	    my $proteinSequenceArray = $sequences->{$sequenceHeader};
	    my $proteinSequence = join("", @$proteinSequenceArray);
	    print $outputFastaFh $proteinSequence . "\n";
	}
    }
    $outputFastaFh->close();

    #copy control sequence disopred file to run directory
    $controlSequenceId =~ /^(\S\S).*/;
    my $controlPrefix = $1;
    my $controlPsipredDir = "$runDir/$controlPrefix/";
    my $controlCmd = "mkdir -p $controlPsipredDir";
    system ($controlCmd);
    my $controlCpCmd = "cp $psipredDirectory/$controlPrefix/$controlSequenceId" . ".ss2 $controlPsipredDir";
    system($controlCpCmd);
   
    #get filehandle for test sequence input and output
    $testSequenceId =~ /^(\S\S).*/;
    my $prefix = $1;
    my $psipredFile = "$psipredDirectory/$prefix/$testSequenceId" . ".ss2";
    my $psipredFh = FileHandle->new($psipredFile) || die "could not open psipred file $psipredFile\n";
    my $fakePsipredDir =  "$runDir/$prefix/";
    my $cmd = "mkdir -p $fakePsipredDir";
    system ($cmd);

    my $outputFile  = $fakePsipredDir . "/$testSequenceId" . ".ss2";    


    return ($psipredFh, $outputFile);
}

sub testPsipredNoPeptideError{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "testing psipred no peptide error\n";
    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "psipred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    &createPsipredTruncatedFileDir($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");
    
    $peptidePipeline->parsePeptidesFromSequences();
    
    #$peptidePipeline->getBestModels();
    
    #$peptidePipeline->parseDsspResults();
    
    $peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my $testName = "psipredNoPeptideError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "no_psipred_peptide_sequence", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);


}


sub testPsipredStructureTypeError{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "test psipred structure type error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "psipred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    #create fake psipred where 48e177 seq is the only sequence, rename all AAs to X's in psipred file to force mismatch
    &createPsipredFakeStructureDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");
    
    $peptidePipeline->parsePeptidesFromSequences();
    
    #$peptidePipeline->getBestModels();
    
    #$peptidePipeline->parseDsspResults();
    
    $peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my $testName = "psipredStructureTypeError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "psipred_format_error", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);


}


sub testPsipredMismatch{


    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test psipred mismatch\n";
    
    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "psipred_results_dir", $runDirectory);
    &updateParameters($parameterFile, "input_fasta_file_name", "errorInput.fasta");
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    #create fake psipred where 48e177 seq is the only sequence, rename all AAs to X's in psipred file to force mismatch
    &createPsipredFakeAaDir($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "628a5aef4b6c5a01ddf120003ba7dad0MRVTSLTA");
    
    $peptidePipeline->parsePeptidesFromSequences();
    
    #$peptidePipeline->getBestModels();
    
    #$peptidePipeline->parseDsspResults();
    
    $peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my $testName = "psipredMismatch";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "psipred_sequence_mismatch", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}


sub createPsipredFakeAaDir{

    my ($runDir, $sequenceId, $controlSequenceId) = @_;
    
    my ($psipredFh, $outputFile) = &createPsipredErrorDirectory($runDir, $sequenceId, $controlSequenceId);
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output psipred file $outputFile\n";
    for (my $i = 0; $i < 2; $i++){
	<$psipredFh>;
    }

    while (<$psipredFh>){
	chomp;
	my $line = $_;
	if ($line =~ /(\s*\d+\s)(\w)(.*)/){
	    my $firstPart = $1;
	    my $residue = $2;
	    my $secondPart = $3;
	    print $outputFh $firstPart . "X" . $secondPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}


sub createPsipredTruncatedFileDir{

    my ($runDir, $sequenceId, $controlSequenceId) = @_;
    
    my ($psipredFh, $outputFile) = &createPsipredErrorDirectory($runDir, $sequenceId, $controlSequenceId);
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output psipred file $outputFile\n";
    for (my $i = 0; $i < 2; $i++){
	<$psipredFh>;
    }

    my $counter = 0;
    while (<$psipredFh>){
	$counter++;
	last if ($counter > 5);
	chomp;
	my $line = $_;
	print $outputFh $line . "\n";
    }
}



sub createPsipredFakeStructureDirectory{

    my ($runDir, $sequenceId, $controlSequenceId) = @_;
    
    my ($psipredFh, $outputFile) = &createPsipredErrorDirectory($runDir, $sequenceId, $controlSequenceId);
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output psipred file $outputFile\n";
    for (my $i = 0; $i < 2; $i++){
	<$psipredFh>;
    }

    while (<$psipredFh>){
	chomp;
	my $line = $_;
	if ($line =~ /(\s*\d+\s\w\s)(\w)(.*)/){
	    my $firstPart = $1;
	    my $structureType = $2;
	    my $secondPart = $3;
	    print $outputFh $firstPart . "X" . $secondPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}





sub testDsspRegexError{
    my ($inputDir, $expectedOutputDir) = @_;
    
    print STDERR "test dssp regex error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    
    &createDsspRegexErrorDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "8164dc21e9d4a2320ab610daea6cad26");
    &updateParameters($parameterFile, "dssp_directory", $runDirectory);

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
   
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    #$peptidePipeline->runPsipred();
    #$peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();
    my $testName = "dsspRegexError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "regex_error", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);
}





sub testDsspStructureTypeError{
    my ($inputDir, $expectedOutputDir) = @_;
    
    print STDERR "test dssp structure type error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    
    &createDsspFakeStructureDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "8164dc21e9d4a2320ab610daea6cad26");
    &updateParameters($parameterFile, "dssp_directory", $runDirectory);

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
   
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    #$peptidePipeline->runPsipred();
    #$peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();
    my $testName = "dsspStructureTypeError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "dssp_format_error", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);
}

sub testDsspNoPeptideError{
    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "test dssp no peptide error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    
    &createDsspTruncatedFile($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "8164dc21e9d4a2320ab610daea6cad26");
    &updateParameters($parameterFile, "dssp_directory", $runDirectory);

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
   
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    #$peptidePipeline->runPsipred();
    #$peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();
    my $testName = "dsspNoPeptideError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "no_dssp_structure_info", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);



}


sub testSolventExposureError{

    my ($inputDir, $expectedOutputDir) = @_;
    print STDERR "Test solvent exposure error\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    
    #use input fasta with all X's to force no solvent exposure found. Adjust rules file to parse all peptides. Probably better to do this dynamically instead of getting it
    #from $errorInputDir so I don't have to make a new one if there's a new sequence
    my $cpCmd = "cp $inputDir/inputSequences_noSolventExp.fasta $runDirectory";
    system($cpCmd);
    &updateParameters($parameterFile, "input_fasta_file_name", "inputSequences_noSolventExp.fasta", $runDirectory);

    
    my $emptyRulesFile = "emptyRulesFile";
    my $cmd = "touch $runDirectory/$emptyRulesFile";
    system($cmd);
    &updateParameters($parameterFile, "rules_file_name", $emptyRulesFile, $runDirectory);

    &createDsspFakeAaDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "8164dc21e9d4a2320ab610daea6cad26");
    &updateParameters($parameterFile, "dssp_directory", $runDirectory);

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
   
    $peptidePipeline->parsePeptidesFromSequences();
    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    #$peptidePipeline->runPsipred();
    #$peptidePipeline->runDisopred();
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();
    my $testName = "solventExposureError";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "dssp_format_error", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";
    system ($cmd);
}


sub testDsspMismatch{

    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test DSSP mismatch\n";
    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "dssp_directory", $runDirectory);
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    #create fake DSSP directory where 48e177 seq is the only sequence, rename all AAs to X's in DSSP file to force mismatch
    &createDsspFakeAaDirectory($runDirectory, "48e177d057c56e9a145fd9baf7409da9MERAEPQS", "8164dc21e9d4a2320ab610daea6cad26");
    

    $peptidePipeline->parsePeptidesFromSequences();
    
    $peptidePipeline->getBestModels();
    
    $peptidePipeline->parseDsspResults();
    
    #$peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my $testName = "dsspMismatch";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "dssp_format_error", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}

sub testMissingDsspFile{
    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test missing DSSP file\n";

    my $runDirectory = &makeRunDirectory($inputDir);

    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "dssp_directory", $inputDir . "fake");
    
    print STDERR "made run dir, updated params\n";

    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    $peptidePipeline->parsePeptidesFromSequences();

    print STDERR "got peptides\n";
    
    $peptidePipeline->getBestModels();

    print STDERR "missing dssp file: got best models\n";
    
    $peptidePipeline->parseDsspResults();
    
    print STDERR "missing dssp file: parsed results\n";

    #$peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    print STDERR "missing dssp file: wrote user results\n";

    $peptidePipeline->finalize();



    my $testName = "missingDsspFile";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "no_dssp_structure_info", $testName);
       
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}



sub testInvalidModelLength{
    #switches modbase seq 48e177d057c56e9a145fd9baf7409da9MERAEPQS model id 8164dc21e9d4a2320ab610daea6cad26 target stat and target end

    my ($inputDir, $expectedOutputDir) = @_;

    print STDERR "test invalid model length\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    
    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, "model_table", $inputDir . "/human2008ModelTable_errors.txt");  #could generate this dynamically 
    
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    
    $peptidePipeline->parsePeptidesFromSequences();
    
    $peptidePipeline->getBestModels();
    
    $peptidePipeline->parseDsspResults();
    
    #$peptidePipeline->runPsipred();
    
    #$peptidePipeline->runDisopred();

    $peptidePipeline->writeUserResults();

    $peptidePipeline->finalize();

    my $testName = "invalidModelLength";
    
    &testErrorHandled($runDirectory, $testName);
    &likeFeatureError($runDirectory, "invalid_model", $testName);
    

    
    my $cmd = "cp -r $runDirectory/* $expectedOutputDir/observedOutput/";

    system ($cmd);
}

sub makeRunDirectory{

    my ($inputDirectory) = @_;

    #make full pipeline/runName directory
    my $tmpDirectory = File::Temp->tempdir("XXXX", CLEANUP => 1);    
    
    my $runDir = $tmpDirectory . "/testing_run";
    my $cmd = "mkdir -p $runDir";
    system ($cmd);

    #copy all input to runName
    my $cpInputCmd = "cp -r  $inputDirectory/sequenceBatches/seq_batch_1/* $runDir/";

    system($cpInputCmd);

    #update parameters with these directories
    my $parameterFile = "$runDir/parameters.txt";
    &updateParameters($parameterFile, "cluster_pipeline_directory", $tmpDirectory);

    my $fh = FileHandle->new(">>" . $parameterFile) || die "could not open input parameter file $parameterFile\n";
    print $fh "run_name\ttesting_run\n";

    return $runDir;
}


sub testMissingFile{
    
    my ($inputDir, $expectedOutputDirectory, $paramName, $testName) = @_;
    
    print STDERR "testing missing file $testName\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, $paramName, "fake_file");
    
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    $peptidePipeline->parsePeptidesFromSequences();

    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    $peptidePipeline->runPsipred();
    $peptidePipeline->runDisopred();
    
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    &likeGlobalError($runDirectory, "file_missing", $testName);
    &testErrorHandled($runDirectory, $testName);
    my $cmd = "cp -r $runDirectory/* $expectedOutputDirectory/observedOutput/";
    system ($cmd);
}

sub testMissingUserDefinedFasta{
    
    my ($inputDir, $expectedOutputDirectory, $paramName, $testName) = @_;
    
    print STDERR "test missing user defined fasta file\n";

    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";
    &updateParameters($parameterFile, $paramName, "fake_file");
    
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    $peptidePipeline->readPeptideInputFile();

    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    $peptidePipeline->runPsipred();
    $peptidePipeline->runDisopred();
    
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    &likeGlobalError($runDirectory, "file_missing", $testName);
    &testErrorHandled($runDirectory, $testName);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDirectory/observedOutput/";
    system ($cmd);
}



sub testUserDefinedAllMismatches{
    
    my ($inputDir, $expectedOutputDirectory, $paramName, $testName) = @_;
    
    print STDERR "test user defined all mismatches\n";
    print STDERR "test line\n";
    print STDERR "input dir: $inputDir\n";
    my $runDirectory = &makeRunDirectory($inputDir);
    my $parameterFile = $runDirectory . "/parameters.txt";
    my $cpCmd = "cp $inputDir/userDefinedAllMismatches.fasta $runDirectory";
    system($cpCmd);
    &updateParameters($parameterFile, $paramName, "userDefinedAllMismatches.fasta");
    
    my $peptidePipeline = PeptidePipeline->new($parameterFile);
    $peptidePipeline->readPeptideInputFile();

    $peptidePipeline->getBestModels();
    $peptidePipeline->parseDsspResults();
    $peptidePipeline->runPsipred();
    $peptidePipeline->runDisopred();
    
    $peptidePipeline->writeUserResults();
    $peptidePipeline->finalize();

    &likeGlobalError($runDirectory, "no_defined_peptides", $testName);
    &testErrorHandled($runDirectory, $testName);

    my $cmd = "cp -r $runDirectory/* $expectedOutputDirectory/observedOutput/";
    system ($cmd);
}


sub createDsspErrorDirectory{

    my ($runDir, $sequenceId, $modelId) = @_;

    my $dsspDirectory = "/netapp/sali/peptide/data/landing/dssp/";
    $sequenceId =~ /^(\S\S\S).*/;
    my $prefix = $1;
    my $dsspFile = "$dsspDirectory/$prefix/$sequenceId/$modelId" . ".dssp";
    my $dsspFh = FileHandle->new($dsspFile) || die "could not open dssp file $dsspFile\n";
    my $fakeDsspDir =  "$runDir/$prefix/$sequenceId";
    my $cmd = "mkdir -p $fakeDsspDir";
    system ($cmd);
    my $outputFile  = $fakeDsspDir . "/$modelId" . ".dssp";
    my $outputFh = FileHandle->new(">" . $outputFile) || die "could not open output dssp file $outputFile\n";

    return ($dsspFh, $outputFh);
}


sub createDsspRegexErrorDirectory{
    my ($runDir, $sequenceId, $modelId) = @_;

    my ($dsspFh, $outputFh) = &createDsspErrorDirectory($runDir, $sequenceId, $modelId);
    
    while (<$dsspFh>){
	chomp;
	my $line = $_;

	last if ($line =~ /^\s+$/);

	if ($line =~ /^(\s+\d+\s+\d+\s+)(\w)(.*)/){

	    my $firstPart = $1;
	    my $residueOneLetter = $2;
	    my $lastPart = $3;
	    print $outputFh $firstPart . " " . $lastPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}



sub createDsspFakeStructureDirectory{
    my ($runDir, $sequenceId, $modelId) = @_;

    my ($dsspFh, $outputFh) = &createDsspErrorDirectory($runDir, $sequenceId, $modelId);
    
    while (<$dsspFh>){
	chomp;
	my $line = $_;

	last if ($line =~ /^\s+$/);

	if ($line =~ /^(\s+\d+\s+\d+\s+\w\s\s)(.)(.*)/){

	    my $firstPart = $1;
	    my $structureType = $2;
	    my $lastPart = $3;
	    print $outputFh $firstPart . "X" . $lastPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}


sub createDsspFakeAaDirectory{
    my ($runDir, $sequenceId, $modelId) = @_;

    my ($dsspFh, $outputFh) = &createDsspErrorDirectory($runDir, $sequenceId, $modelId);
    
    while (<$dsspFh>){
	chomp;
	my $line = $_;

	last if ($line =~ /^\s+$/);

	if ($line =~ /^(\s+\d+\s+\d+\s+)(\w)(.*)/){

	    my $firstPart = $1;
	    my $residueOneLetter = $2;
	    my $lastPart = $3;
	    print $outputFh $firstPart . "X" . $lastPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
}

sub createDsspTruncatedFile{
    my ($runDir, $sequenceId, $modelId) = @_;
    
    my ($dsspFh, $outputFh) = &createDsspErrorDirectory($runDir, $sequenceId, $modelId);
    my $residueCount = 0;
    while (<$dsspFh>){
	chomp;
	last if $residueCount > 10;
	my $line = $_;

	last if ($line =~ /^\s+$/);
	if ($line =~ /^(\s+\d+\s+\d+\s+)(\w)(.*)/){
	    $residueCount++;
	    my $firstPart = $1;
	    my $residueOneLetter = $2;
	    my $lastPart = $3;
	    print $outputFh $firstPart . "X" . $lastPart . "\n";
	}
	else {
	    print $outputFh $line . "\n";
	}
    }
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


sub likeFeatureError{
    my ($runDirectory, $errorName, $testName) = @_;
    my $resultsFile = $runDirectory . "/peptidePipelineResults.txt";
    &likeColumnHeader($resultsFile, $testName);
    like(&convertFileToString($resultsFile), qr/$errorName/, "Testing feature error $errorName was written (testing $testName)");
}


sub likeGlobalError{
    my ($runDirectory, $errorName, $testName) = @_;
    
    my $resultsFile = $runDirectory . "/peptidePipelineResults.txt";
    &likeColumnHeader($resultsFile, $testName);
    &likeGlobalErrorName($resultsFile, $errorName, $testName);
}


sub likeOutputError{
    my ($runDirectory, $testName) = @_;
    my $resultsFile = $runDirectory . "/peptidePipelineResults.txt";
    my $fh = FileHandle->new("<" . $resultsFile) || die "could not open pipeline results file $resultsFile (likeColumnHeader): $!\n";
    my $line = <$fh>;
    like($line, qr/output/, "got expected output error (testing $testName)");
    my $nextLine = <$fh>;
    is($nextLine, undef, "only one error line in results file $resultsFile\n");
}
	


sub testErrorHandled{

    my ($runDirectory, $testName) = @_;
    my $logFileName = $runDirectory . "/peptidePipelineLog";
    like(&convertFileToString($logFileName), qr/ERROR/, "peptide pipeline log error written in test $testName");
}


sub likeColumnHeader{
    my ($resultsFile, $testName) = @_;

    my $fh = FileHandle->new("<" . $resultsFile) || die "could not open pipeline results file (likeColumnHeader): $!\n";
    my $columnHeaderLine = <$fh>;
    chomp $columnHeaderLine;

    my $columnHeaderExpectedString =  "Uniprot Accession	Classification	Peptide Sequence	Peptide Start	Peptide End	Peptide Secondary Structure Type	Peptide Accessibility Prediction	Disopred Prediction	PSIPRED Prediction	Model URL	Total Models For Sequence	Models Containing Peptide	Dataset	Target Start	Target End	Model Score	Dope Score	TSVMod Native Overlap	TSVMod Method	Template Sequence Identity	Model Coverage	Loop Length	Template PDB ID	Peptide Similarity To Template	Corresponding Sequence in Template	Peptide Structure Values	Peptide Predicted Accessibility Fraction	Disopred Scores	PSIPRED Scores	Alignment File Path	Sequence ID	Model ID	Protein Name	Errors	";

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

sub createFastaFile{
    my ($runDir, $fileName, $singleSequenceId) = @_;

    my $inputFastaFile =  $runDir . "/inputSequences.fasta";
    my $reader = FastaReader->new($inputFastaFile, 1);
    $reader->read();
    my $sequences = $reader->getSequences();

    my $outputFastaFile = $runDir . "/" . $fileName;
    print STDERR "creating output fasta file $outputFastaFile\n";
    my $outputFastaFh = FileHandle->new(">" . $outputFastaFile) || die "could not open $fileName";
    
    foreach my $sequenceHeader (keys %$sequences){
	my @cols = split('\|', $sequenceHeader);
	my $sequenceId = $cols[0];
	if ($sequenceId eq $singleSequenceId){
	    print $outputFastaFh ">" . $sequenceHeader . "\n";
	    my $proteinSequenceArray = $sequences->{$sequenceHeader};
	    my $proteinSequence = join("", @$proteinSequenceArray);
	    print $outputFastaFh $proteinSequence . "\n";
	}
    }
    $outputFastaFh->close();

}

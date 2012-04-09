
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


my $trainingSvmTestDir = "/modbase5/home/dbarkan/peptide/test/svmTraining/specificInput/";


my $inputDir = $trainingSvmTestDir . "/input";
my $outputDir = $trainingSvmTestDir . "/output";


print STDERR "starting tests\n";

&runSpecificInputTest($inputDir, $outputDir);

sub runSpecificInputTest{
    my ($inputDir, $outputDir) = @_;
    
    my $runDir = &makeRunDirectory($inputDir);
    my $parameterFile = $runDir . "/parameters.txt";
    print STDERR "made run dir and parameter file $parameterFile\n";
    my $pipeline = BenchmarkerPipeline->new($parameterFile);

    $pipeline->execute();
    $pipeline->finalize();

    my $cmd = "cp -r $runDir/* $outputDir";
    system($cmd);


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

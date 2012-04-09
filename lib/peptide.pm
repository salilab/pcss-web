package peptide;
use strict;
use saliweb::frontend;
our @ISA = "saliweb::frontend";

use POSIX qw(ceil floor);


sub new {
    return saliweb::frontend::new(@_, @CONFIG@);
}

sub get_index_page {
    my ($self) = @_;
    my $q = $self->cgi;

    my $errorHandlingValues = ['Q', 'I'];
    my $errorHandlingLabels;
    $errorHandlingLabels->{"Q"} = "Quit";
    $errorHandlingLabels->{"I"} = "Ignore";
   
    my $serverModeValues = ['training', 'application'];
    my $serverModeLabels;
    $serverModeLabels->{"training"} = "Training Mode";
    $serverModeLabels->{"application"} = "Application Mode";

    my $applicationSpecificationValues = ['D', 'S'];
    my $applicationSpecificationLabels;
    $applicationSpecificationLabels->{"D"} = "User Specified";
    $applicationSpecificationLabels->{"S"} = "Full Sequence Scan";


    my $bestModelValues = ['modelScore', 'coverage', 'nativeOverlap'];
    my $bestModelLabels;
    $bestModelLabels->{"modelScore"} = "Model Score";
    $bestModelLabels->{"nativeOverlap"} = "Predicted Native Overlap";
    $bestModelLabels->{"coverage"} = "Model Target Coverage";


    my $svmModelValues = ['grb', 'caspase', 'hiv', 'none'];
    my $svmModelLabels;
    $svmModelLabels->{"grb"} = "Granzyme B";
    $svmModelLabels->{"caspase"} = "Caspase";
    $svmModelLabels->{"hiv"} = "HIV Protease";
    $svmModelLabels->{"none"} = "<None>";

    return "<div id=\"resulttable\">\n" .
	$q->h2({-align=>"center"},
	       "PCSS: Peptide Classification using Sequence and Structure") . 
	       $q->start_form({-name=>"peptideform", -method=>"post",
			       -action=>$self->submit_url}) .
			       $q->table(
					 $q->Tr($q->td("<u><b>Global options for running the PCSS Server<b></u>")) . 

					 $q->Tr($q->td("Select PCSS Server Mode",
						       $self->help_link("server_mode"),
						       $q->td($q->radio_group("server_mode", $serverModeValues, "training", 0, $serverModeLabels)))) . 

					 $q->Tr($q->td("Email address"),
						$q->td($q->textfield({-name=>"email",
								      -value=>$self->email,
								      -size=>"25"}))) .

					 $q->Tr($q->td("Name your model"),
						$q->td($q->textfield({-name=>"name",
								      -size=>"9"}))) .
				      
					 $q->Tr($q->td("Best Protein Structure Model Criteria",
						       $self->help_link("best_model"),
						       $q->td($q->popup_menu("best_model", $bestModelValues, "nativeOverlap", $bestModelLabels)))) . 

					 $q->Tr($q->td("Select error handling mode",
						       $self->help_link("error_handling"),
						       $q->td($q->radio_group("error_handling", $errorHandlingValues, "I", 0, $errorHandlingLabels)))) .

					 $q->Tr($q->td("<br>")) . 

					 $q->Tr($q->td("<u><b>Set these options when TRAINING a new model</b></u>")) .
					 
					 $q->Tr($q->td("Upload Training Peptide File",
						       $self->help_link("training_file"), $q->br),
						$q->td($q->filefield({-name=>"training_file"}))) .
					 
					 $q->Tr($q->td("Training Iterations",
						       $self->help_link("training_iterations")),
						       $q->td($q->textfield({-name=>"training_iterations",
									    -maxlength=>"4", -size=>"5"}))) .

					 $q->Tr($q->td("Jackknife Fraction",
						       $self->help_link("jackknife_fraction")),
						       $q->td($q->textfield({-name=>"jackknife_fraction",
									    -maxlength=>"4", -size=>"5"}))) .

					 $q->Tr($q->td("<br>")) . 

					 $q->Tr($q->td("<u><b>Set these options when APPLYING an existing model</b></u>")) .

					 $q->Tr($q->td("Upload Application Target File",
						       $self->help_link("application_file"), $q->br),
						$q->td($q->filefield({-name=>"application_file"}))) .

					 $q->Tr($q->td("Select Application Peptide Specification Method",
						       $self->help_link("application_specification"),
						       $q->td($q->radio_group("application_specification", $applicationSpecificationValues, "D", 0, $applicationSpecificationLabels)))) . 

					 $q->Tr($q->td("Upload Peptide Specifier File (Optional)",
						       $self->help_link("rules_file"), $q->br),
						$q->td($q->filefield({-name=>"rules_file"}))) .

					 $q->Tr($q->td("Upload model file created in Training mode",
						       $self->help_link("svm_model"), $q->br),
						$q->td($q->filefield({-name=>"svm_custom_model"}))) .
						
					 $q->Tr($q->td("OR use a pre-generated model for a specific system",
						       $self->help_link("svm_model"),
						       $q->td($q->popup_menu("svm_model", $svmModelValues, "none", $svmModelLabels)))) . 
					 
					 $q->Tr($q->td({-colspan=>"2"},
						       "<center>" .
						       $q->input({-type=>"submit", -value=>"Process"}) .
						       $q->input({-type=>"reset", -value=>"Reset"}) .
						       "</center><p>&nbsp;</p>"))) .
						       $q->end_form .
						       "</div>\n";
    
}

sub get_submit_page {

    my ($self) = @_;
    my $q = $self->cgi;
    my $userInput;


    #Read global options, save in $userInput
    my $email = $q->param('email')||undef;            $userInput->{"email"} = $email;
    my $name = $q->param('name')||"";                 $userInput->{"name"} = $name; 
    my $errorHandling = $q->param('error_handling');  $userInput->{"error_handling"} = $errorHandling;
    my $bestModelCriteria = $q->param('best_model');  $userInput->{"best_model"} = $bestModelCriteria;
    my $serverMode = $q->param('server_mode');        $userInput->{"server_mode"} = $serverMode;

    my $job = $self->make_job($name, $email); 
    my $directory = $job->directory;                  

    $userInput->{"directory"} = $directory;
    
    if ($serverMode eq "training"){
	#Read training specific options; save in $userInput
	my $trainingFh = $q->upload('training_file');               $userInput->{"training_file"} = $trainingFh;
	my $jackknifeFraction = $q->param('jackknife_fraction');    $userInput->{"jackknife_fraction"} = $jackknifeFraction;
	my $trainingIterations = $q->param('training_iterations');  $userInput->{"training_iterations"} = $trainingIterations;
    }
    elsif ($serverMode eq "application") {

	#Read application specific options; save in $userInput
	my $svmModel = $q->param('svm_model');                                  $userInput->{"svm_model"} = $svmModel;
	my $svmCustomModel = $q->param('svm_custom_model');                     $userInput->{"svm_custom_model"} = $svmCustomModel;
	my $rulesFh = $q->upload('rules_file');                                 $userInput->{"rules_file"} = $rulesFh;
	my $applicationFh = $q->upload('application_file');                     $userInput->{"application_file"} = $applicationFh;
	my $applicationSpecification = $q->param('application_specification');  $userInput->{"application_specification"} = $applicationSpecification;
    }
    else {
	throw saliweb::frontend::InternalError("Did not get expected server mode (expect 'training' or 'application'; instead got $serverMode)");
    }

    #perform all validation and create files
    my $globalParameterFileName = "/netapp/sali/peptide/data/globalPeptideParameters.txt";   #hardcoded location -- TODO -- see if there is a better way to do this
    $self->process_user_input($userInput, $globalParameterFileName);
    
    #submit and user output
    $job->submit();
    
    $self->writeUserLog("Finished processing user input for job name " . $job->name . "; results will be found at " . $job->results_url);
    $self->writeInternalLog("Finished processing user input; proceeding to backend");
    
    return $q->p("Your job " . $job->name . " has been submitted.") .
           $q->p("Results will be found at <a href=\"" .
                 $job->results_url . "\">this link</a>.");
	
}

###########################################################################################################################################################
# process_user_input
# Takes web-page input provided by user, validates it, and writes files in preparation for backend (both training and application mode).
# This can be called from get_submit_page or by testing agents.
#
# PARAM  $userInput: Hash where keys are the same field names as the cgi web form, and values are those entered by the user
#                    In some cases these are FileHandles.  Also contains a field for the job's directory
# PARAM  $paramFileName: Name of the parameter file that is used throughout the job 
###########################################################################################################################################################
sub process_user_input {
    my ($self, $userInput, $paramFileName) = @_;

    #Read and validate global options
    my $email = $userInput->{'email'};
    my $name = $userInput->{'name'};
    my $errorHandling = $userInput->{'error_handling'};
    my $bestModelCriteria = $userInput->{'best_model'};
    my $serverMode = $userInput->{'server_mode'};

    my $directory = $userInput->{"directory"};

    $self->readParameterFile($paramFileName);

    $self->validateJobName($name);

    &check_required_email($email); 

    #Initialize logging
    $self->getUserLogFile($directory);
    $self->getInternalLogFile($directory);
    $self->writeUserLog("Starting run of peptide server in $serverMode mode. Options set for this run:");  

    #create parameter hash; insert global options
    $self->setParam("job_name", $name, 1);
    $self->setParam("email", $email, 1);
    $self->setParam("best_model_criteria", $bestModelCriteria, 1);
    $self->setParam("server_mode", $serverMode, 1);
    $self->setParam("error_handling", $errorHandling, 1);


    if ($serverMode eq "training"){

	my $trainingFh = $userInput->{'training_file'};
	my $jackknifeFraction = $userInput->{'jackknife_fraction'};
	my $trainingIterations = $userInput->{'training_iterations'};
	
	$self->setParam("test_set_percentage", $jackknifeFraction, 1);
	$self->setParam("iteration_count", $trainingIterations, 1);

	$self->validateJackknifeFraction($jackknifeFraction);
	$self->validateTrainingIterations($trainingIterations);

	my $stats = $self->processUserSpecifiedPeptides($trainingFh, $errorHandling, $directory, 0);

	my $peptideLength = $self->{MaxPeptideLength};
	$self->setParam("peptide_length", $peptideLength);
	
	$self->writeTrainingStats($stats, $directory);
    }
    elsif ($serverMode eq "application") {

	#Read and validate application specific options	

	#Handle user custom model if uploaded, or use previously generated models
	my $svmModel = $userInput->{'svm_model'};
	my $svmCustomModel = $userInput->{'svm_custom_model'};
	
	$self->validateModelSpecified($svmModel, $svmCustomModel);
	$self->writeUserLog("svm_model_name:\t$svmModel");	

	my $peptideLength = 0;

	if ($svmCustomModel){
	    #decompose user model package into its model and benchmark components
	    #model and benchmark file location params will be set later (after preprocess directory is known)
	    $peptideLength = $self->processUserCreatedModel($directory, $svmCustomModel);
	    $self->setParam("using_custom_model", "yes", 1);

	}
	else{
	    #set generated model parameter files
	    $self->setParam("using_custom_model", "no", 1);
	    
	    my $modelFileLocation = $self->getSvmModelFileLocation($svmModel);
	    my $benchmarkScoreFileLocation = $self->getBenchmarkScoreFileLocation($svmModel);
	    $self->setParam("svm_application_model", $modelFileLocation, 0);
	    $self->setParam("benchmark_score_file", $benchmarkScoreFileLocation, 0);
	    $peptideLength = 8;  #true for all previously generated models
	    
	}

	$self->setParam("peptide_length", $peptideLength, 1);

	my $rulesFh = $userInput->{'rules_file'};
	my $applicationFh = $userInput->{'application_file'};
	my $applicationSpecification = $userInput->{'application_specification'};

	#User-defined peptides
	if ($applicationSpecification eq "D"){
	    $self->writeUserLog("application_peptide_source:\tuser defined");
	    my $stats = $self->processUserSpecifiedPeptides($applicationFh, $errorHandling, $directory);
	    $self->writeUserLogBlankLine();
	    $self->writeApplicationStats($stats);
	}
	#Scan protein sequences
	elsif ($applicationSpecification eq "S"){

	    #Finish logging params
	    $self->writeUserLog("application_peptide_source:\tscan from rules file");
	    $self->writeUserLogBlankLine();

	    $self->writeInternalLog("Reading and validating rules file");
	    my $rulesFileLines = $self->readAndValidateRulesFile($rulesFh, $peptideLength);    #check rules file consistency as its read
	    #TODO - once length is a functional input parameter, make sure length matches up (this could also be read from model file)
	    
	    $self->writeRulesFileOutput($rulesFileLines, $directory);
	    
	    $self->writeInternalLog("Reading and validating application file");
	    #read and validate input file, get accessions
	    my $uniprotAccessionList = $self->readAndValidateApplicationFile($applicationFh, $directory);
	    
	    #use uniprot accessions to get all sequences from modbase; write to fasta file
	    $self->writeInternalLog("Getting protein sequences from modbase");
	    my $sequenceInfo = $self->getSequencesFromModbase($errorHandling, @$uniprotAccessionList);
	    $self->writeInternalLog("Writing protein sequences to fasta");
	    $self->writeApplicationInfo($directory, $sequenceInfo);
	    	    
	}
	else {
	    throw saliweb::frontend::InternalError("Did not get expected application specification (expect 'D' or 'S'; instead got $applicationSpecification)");
	}
	
	

	$self->setParam("application_specification", $applicationSpecification, 0);
    }
    
    else {
	throw saliweb::frontend::InternalError("Did not get expected server mode (expect 'training' or 'application'; instead got $serverMode)");
    }
    
    #make feature task file directory
    my $seqBatchTopDirectoryName = $self->getParam("seq_batch_top_directory");
    my $seqBatchCmd = "mkdir -p $directory/$seqBatchTopDirectoryName";
    system($seqBatchCmd);

    #write out parameter file
    $self->writeParameters($directory);
}

sub get_results_page {
    my ($self, $job) = @_;
    my $q = $self->cgi;
    
    my $directory = $job->directory;
    
    #read parameters (again) -- these have been updated through the course of the job run
    my $parameterFileName = "parameters.txt";  #hardcoded
    $self->readParameterFile($parameterFileName);
    my $serverMode = $self->getParam("server_mode");
    
    my $returnValue = $q->p("Job '<b>" . $job->name . "</b>' has completed.");
    
    
    if ($serverMode eq "training"){
	my $resultsFile = $self->getParam("training_final_result_file_name");
	my $modelFile = $self->getParam("user_model_package_name");
	my $errorFileName = "postprocessErrors";
	
	if ((-f $errorFileName) || (-f $resultsFile == 0)){
	    $returnValue .= $q->p("We're sorry; an error occurred while this server job was being processed. " . 
				  "An email has been sent to the administrator notifying them of the problem (which may also be found in the log file) ");
	    $returnValue .= $q->p("Common errors include that our cluster experienced a problem, in which case you may try submitting the job again later. " .
				  "We apologize for the inconvenience"); #looks fine when printed to screen
	}
	else {    #training results file
	    $returnValue .= $q->p("<a href=\"" .
				  $job->get_results_file_url($resultsFile) .
				  "\">Download training benchmark results file</a>.");
	}
	if (-f $modelFile) { 
	    $returnValue .= $q->p("<a href=\"" .
				  $job->get_results_file_url($modelFile) .
				  "\">Download SVM model file generated from your input.</a> This file can be uploaded in Application mode to search for new peptides.");
	}
	else {
	    $returnValue .= $q->p("No model file was produced (searched for $modelFile). Please inspect " .
				  "the log file to determine the problem.");
	}

	    
    }
    elsif ($serverMode eq "application") {
	
	my $errorFileName = "postprocessErrors";
	my $resultsFile = $self->getParam("application_final_result_file_name");
	if ((-f $errorFileName) || (-f $resultsFile == 0)){
	    $returnValue .= $q->p("We're sorry; an error occurred while this server job was being processed. " . 
				  "An email has been sent to the administrator notifying them of the problem (which may also be found in the log file) ");
	    $returnValue .= $q->p("Common errors include that our cluster experienced a problem, in which you may try submitting the job again later. " .
				  "We apologize for the inconvenience"); #looks fine when printed to screen
	}

	else {
	    #application results file

	    $returnValue .= $q->p("<a href=\"" .
				  $job->get_results_file_url($resultsFile) .
				  "\">Download application results file</a>.");
	}
    }
    else {
	throw saliweb::frontend::InternalError("Did not get expected server mode (expect 'training' or 'application'; instead got $serverMode)");
    }
    
    #log file
    my $logFileName = $self->getParam("user_log_file_name");
    if (-f $logFileName){
	$returnValue .= $q->p("<a href=\"" .
			 $job->get_results_file_url($logFileName) .
			 "\">Download log file</a>.");
    }

    my $mismatchFileName = $self->getParam("mismatch_file_name");
    if (-s $mismatchFileName){
	$returnValue .= $q->p("<a href=\"" .
			 $job->get_results_file_url($mismatchFileName) . 
			 "\">Download protein sequences where no user-supplied peptide matched the protein residue sequence in Modbase</a>."); 
    }
    $returnValue .= $job->get_results_available_time();
    return $returnValue;
}


sub get_navigation_links {
    my $self = shift;
    my $q = $self->cgi;
    return [
        $q->a({-href=>$self->index_url}, "PCSS Home"),
        $q->a({-href=>$self->queue_url}, "Current PCSS queue"),
        $q->a({-href=>$self->help_url}, "Help"),
        $q->a({-href=>$self->contact_url}, "Contact")
        ];
}

sub get_project_menu {
    my ($self) = @_;

    return <<MENU;
	<p>&nbsp;</p>
<h4><small>Full PCSS Documentation</small></h4>
<p><a href="html/doc/PCSS_Documentation.pdf">Download</a>
<h4><small>Lead Authors:</small></h4>
<p>Dave Barkan<br />
Dan Hostetter<br />
<br />
<h4><small>Web Developers:</small></h4>
<p>Dave Barkan<br />
Ben Webb<br />
<h4><small>Corresponding Authors:</small></h4>
<p>Andrej Sali<br />
Charles Craik<br />

<p><font color=FIREBRICK>Download Granzyme B and Caspase predicted cleavage sites generated from study in Barkan, Hostetter, <i>et al</i>, <i>Bioinformatics</i>, 2010</font><p>
<p><a href="html/doc/caspase_proteome_results.zip">Caspase</a> <a href="html/doc/grb_proteome_results.zip">Granzyme B</a>

MENU


}

sub get_footer {
    my ($self) = @_;
    return "&nbsp";
}



###########################################################################################################################################################
# processUserSpecifiedPeptides
# Top level method for parsing user-provided peptide file which includes all accessions, peptide start positions, and peptide sequences.
# Once read, retrieves sequences from modbase, does a lot of quality control, and writes out a file that the backend picks up in the next step.
#
# PARAM  $peptideFh: FileHandle for uploaded file (automatically created upon submission).
# PARAM  $errorHandling: Either "I" or "Q".  "I" ignores mismatches and writes them to the log.  "Q" quits before the job is sent to the backend.
# PARAM  $directory: webserver job directory where file will be written
# RETURN $stats: statistics about which peptides were found or not.
###########################################################################################################################################################
sub processUserSpecifiedPeptides{
    my ($self, $peptideFh, $errorHandling, $directory) = @_;

    my ($peptideFileInfo) = $self->readAndValidatePeptideFile($peptideFh, $directory);
    my $stats;

    $self->writeUserLogBlankLine();  #last param has been written (obviously could change)

    #use uniprot accessions to get all sequences from modbase and validate user-specified peptides; output final peptide file
    my @accessions = keys (%$peptideFileInfo);
    my $sequenceInfo = $self->getSequencesFromModbase($errorHandling, @accessions);
    $peptideFileInfo = $self->updatePeptideFile($peptideFileInfo, $sequenceInfo);
    ($peptideFileInfo, $stats) = $self->validatePeptideSequenceInfo($sequenceInfo, $peptideFileInfo, $errorHandling);  

    #the data in $peptideFileInfo will change by side-effect if a sequence mismatch was found and errorHandling eq 'I'
    $self->writePeptideInfo($sequenceInfo, $peptideFileInfo, $directory);  
    return $stats;
}


###########################################################################################################################################################
# After filtering out different uniprot accessions that map to the same Modbase ID, get all the user-specified information for the 
# different peptides for the filtered uniprot accessions and add it to the uniprot accession that will represent the duplicates going forward.
# Takes as input the $peptideFileInfo hash that contains the possibly redundant accessions and returns the same style hash but with the 
# duplicate accessions merged into a single accession.
# 
# PARAM  $peptideFileInfo: hash containing results of user's sequence set, of the form $peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{peptideSequence} = $peptideSequence
#                                                                                                                                                    ->{classification}  = $classification
# PARAM  $sequenceInfo: map of uniprot accessions to modbase sequence IDs of the form $sequenceInfo->{$modbaseSeqId}->{uniprotAccession} = $uniprotAccession
#                                                                                                                   ->{sequence}         = $proteinSequence
# RETURN $peptideFileInfo: a new hash of the same form of $peptideFileInfo (the original hash is not update by side effect).
###########################################################################################################################################################
sub updatePeptideFile{
    my ($self, $peptideFileInfo, $sequenceInfo) = @_;

    #transform list of modbase to duplicate uniprot to be keyed on uniprot; save rep uniprots
    my $modbaseToDuplicateUniprot = $self->{ModbaseToDuplicateUniprot};
    my $uniprotsToModbase;
    my $uniprotsToReps; #rep uniprots is the uniprot accession we'll use going forward for this modbase seq id (arbitrarily chosen)
    foreach my $modbaseSeqId (keys %$modbaseToDuplicateUniprot){
	my $repUniprot = $sequenceInfo->{$modbaseSeqId}->{uniprotAccession};
	my $uniprots = $modbaseToDuplicateUniprot->{$modbaseSeqId};
	foreach my $uniprotAccession (keys %$uniprots){
	    $uniprotsToModbase->{$uniprotAccession} = $modbaseSeqId;
	    $uniprotsToReps->{$uniprotAccession} = $repUniprot;
	}
    }
    
    #Create new peptide file info data structure with only the rep uniprots as the key. Move all info from
    #duplicate uniprots into this data structure
    my $finalPeptideFileInfo;
    foreach my $uniprotAccession (keys %$peptideFileInfo){
	my $repUniprot = $uniprotsToReps->{$uniprotAccession}; #get rep uniprot (if this is the rep uniprot, gets identical accession, which is fine)
	my $startPositions = $peptideFileInfo->{$uniprotAccession};
	foreach my $startPosition (keys %$startPositions){ #move all info for each start position to this rep uniprot info
	    my $startPositionInfo = $startPositions->{$startPosition};
	    $finalPeptideFileInfo->{$repUniprot}->{$startPosition} = $startPositionInfo;
	}
    }
    return $finalPeptideFileInfo;
}
	


###########################################################################################################################################################
# readAndValidatePeptideFile
# Reads user-submitted file that that specifies sequence IDs, peptide sequence, peptide position, and peptide classification.
# Validates formatting of all peptide attributes (see inline code for specific validation steps performed).
# Each line of the file represents one peptide and is of the form:
#
# UniprotAccession PeptideStartPosition PeptideSequence Classification
# 
# Classification is either 'positive' or 'negative' (training mode) or blank (application).  If it is blank (or anything else) in application mode, it will be 
# returned in $peptideFileInfo as 'application'. Case doesn't matter, and it will be returned as lowercase.  Entries are separated by whitespace.  
#
# PARAM  $peptideFh: FileHandle for uploaded file (automatically created upon submission).
# THROW  InputValidationError for a number of reasons related to formatting
# RETURN $peptideFileInfo  
#        Hash of the form $peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{peptideSequence} = $peptideSequence
#                                                                                       ->{classification}  = $classification
###########################################################################################################################################################
sub readAndValidatePeptideFile{
    my ($self, $peptideFh, $directory) = @_;

    if (!$peptideFh){
	throw saliweb::frontend::InputValidationError("No peptide file has been submitted.");
    }

    my $peptideFileInfo;

    my $savedInputFileName = $self->getParam("saved_input_file_name");
    my $savedInputFh = FileHandle->new(">" . "$directory/$savedInputFileName")  || 
	throw saliweb::frontend::InternalError("Could not open peptide file input $savedInputFileName: $!");

    while (<$peptideFh>){
	chomp;
	my $line = $_;
	print $savedInputFh $line . "\n";
	$line =~ s/[\r\n]//g; 

	next unless ($line =~ /(\w+)/); 
	my ($uniprotAccession, $peptideStartPosition, $peptideSequence, $classification) = split('\s+', $line);   
	#assuming no spaces in any of the entries which must be correct given file format.  File format could change in which case should split on '\t'
	
	unless ($uniprotAccession && $peptideStartPosition && $peptideSequence){  #check all features (except classification) are specified

	    throw saliweb::frontend::InputValidationError("Syntax error in peptide file: each line must be of the format uniprot_accession peptide_start_position peptide_sequence classification.  The first three entries must be present for each line. The following line in your peptide file did not contain one or more entries:\n$line");
	}

	unless ($peptideStartPosition =~ /^\d+$/){   #check position is a number

	    throw saliweb::frontend::InputValidationError("Syntax error in peptide file: The peptide start position must be a number (found the value '$peptideStartPosition' in the submitted file.");
	}
	unless ($peptideSequence =~ /^[a-zA-Z]+$/){   #check peptide sequence is all letters

	    throw saliweb::frontend::InputValidationError("Syntax error in peptide file: The peptide sequence must consist of valid one-letter amino acid codes (found the value '$peptideSequence' in the submitted file.");
	}
	
	if ($peptideSequence =~ /B/ || $peptideSequence =~ /J/ || $peptideSequence =~ /O/ || $peptideSequence =~ /U/ || $peptideSequence =~ /X/ || $peptideSequence =~ /Z/){  # check standard AAs

	    throw saliweb::frontend::InputValidationError("Content error in peptide file: Each peptide sequence must consist only of the 20 standard amino acids (the sequence '$peptideSequence' was found in your file).");
	}
	$classification = lc($classification);
	unless ($classification eq "positive" || $classification eq "negative"){   #check classification in cv
	    if ($self->getParam("server_mode") eq "training"){

		throw saliweb::frontend::InputValidationError("Syntax error in peptide file: in training mode, the classification for a peptide must be either 'positive' or 'negative' (found the value '$classification' in the input file.");
	    }
	}
	$peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{peptideSequence} = $peptideSequence;
	$classification = $self->getParam("keyword_application_classification") if ($self->getParam("server_mode") eq "application");
	$peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{classification} = $classification;
    }
    if (scalar(keys %$peptideFileInfo) == 0){  #check to make sure we have at least one entry in the peptide set (elsewhere, this minimum requirement may be increased and checked again)

	throw saliweb::frontend::InputValidationError("The submitted peptide file did not contain any entries");
    }
    return $peptideFileInfo;
}


##########################################################################################################################################################################################
# validatePeptideSequenceInfo
# Checks user-submitted peptide locations and sequences to make sure they match what's in ModBase.
# Both the specified position of the first residue in the sequence and the sequence itself must match for the check to pass.  If it doesn't,
# the method proceeds according to the user-specified error handling options.
#
# PARAM  $sequenceInfo: map of uniprot accessions to modbase sequence IDs of the form $sequenceInfo->{$modbaseSeqId}->{uniprotAccession} = $uniprotAccession
#                                                                                                                   ->{sequence}         = $proteinSequence
# PARAM  $peptideFileInfo: hash containing results of user's sequence set, of the form $peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{peptideSequence} = $peptideSequence
#                                                                                                                                                    ->{classification}  = $classification
# PARAM  $errorHandling: Either "I" or "Q".  "I" ignores mismatches and writes them to the log.  "Q" quits before the job is sent to the backend.
# THROW  InputValidationError if $errorHandling set to "Q" and sequence mismatch found.
#        InternalError if certain sanity checks fail.
# RETURN $peptideFileInfo:  This is the same hash that was passed in.  It may be changed by side effect to note mismatches using the keyword.
#        $stats: statistics about which peptides were found or not
##########################################################################################################################################################################################
sub validatePeptideSequenceInfo{
    my ($self, $sequenceInfo, $peptideFileInfo, $errorHandling) = @_;

    my $stats;
    my $mismatchAccessions;
    my $mismatchData;

    $self->writeInternalLog("Validating user input to make sure that every provided peptide start location and peptide sequence matches what's in ModBase");
    foreach my $modbaseSeqId (keys %$sequenceInfo){
	$stats->{input}->{accessions}++;

	#get accession info
	my $sequence = $sequenceInfo->{$modbaseSeqId}->{sequence};
	my $uniprotAccession = $sequenceInfo->{$modbaseSeqId}->{uniprotAccession};
	my $peptideStartPositions = $peptideFileInfo->{$uniprotAccession};

	foreach my $peptideStartPosition (keys %$peptideStartPositions){
	    
	    #get peptide info
	    my $peptideSequence = $peptideStartPositions->{$peptideStartPosition}->{peptideSequence};
	    my $classification = $peptideStartPositions->{$peptideStartPosition}->{classification};
	    $stats->{input}->{lc($classification)}++;

	    #get equivalent substring in modbase sequence
	    my $peptideLength = length($peptideSequence);
	    my $modbaseSubstring = substr($sequence, $peptideStartPosition - 1, $peptideLength);  #substring doesn't choke if length longer than end of $sequence
	    
	    if ($modbaseSubstring ne $peptideSequence) {  	    

		#check if start position > protein length
		my $proteinLength = length($sequence);
		if (($peptideStartPosition + $peptideLength) > $proteinLength){
		    $modbaseSubstring = "[overrun -- $proteinLength]";
		}
		
		#empty sequence -- should not happen except when the position was greater than the length of the protein, which is handled above
		if ($modbaseSubstring =~ /^\s*$/){ 
		    throw saliweb::frontend::InternalError("Got empty sequence when searching for user-specified peptide.\n  Accession: $uniprotAccession modbase seq id: $modbaseSeqId peptideStartPosition: $peptideStartPosition user sequence: $peptideSequence found $modbaseSubstring. The protein sequence:\n$sequence\n");
		}
		
		#General mismatch handling
		#Quit
		if ($errorHandling eq "Q"){  
		    my $formattedSeqString = $self->formatProteinSequence($sequence);
		    throw saliweb::frontend::InputValidationError("Error: the provided peptide sequence $peptideSequence was not found at position $peptideStartPosition for uniprot accession $uniprotAccession.  The following sequence was found instead: $modbaseSubstring. <br><br>. You may need to check that you have correctly specified the start position in the input file.  There could also be a discrepancy with how the sequence is stored in ModBase.  Since the error handling option was set to 'Quit', this job will now quit.  <br><br>If you are submitting a large number of proteins, consider setting error handling to 'Ignore' to continue processing the remaining proteins.  For more information as to why this accession was not found, refer to the help section by clicking on the above link.  We apologize for the inconvenience. <br><br> For reference, the residue sequence for $uniprotAccession in ModBase is the following: $formattedSeqString");
		}
		#Ignore
		elsif ($errorHandling eq "I"){ #don't add to list of peptides to be processed; log and continue
		    my $peptideSequenceMismatchKeyword = $self->getParam("keyword_peptide_sequence_mismatch");  #this keyword is added for both mismatches and overshots
		    $mismatchData->{$uniprotAccession}->{$peptideStartPosition}->{input} = $peptideSequence;
		    $mismatchData->{$uniprotAccession}->{$peptideStartPosition}->{found} = $modbaseSubstring;

		    $peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{peptideSequence} = $peptideSequenceMismatchKeyword;  
		    $stats->{mismatch}++;
		    $mismatchAccessions->{$uniprotAccession} = 1;
		}
		else {
		    throw saliweb::frontend::InternalError("Did not get expected error handling mode (expect 'I' or 'Q', instead got $errorHandling.)");
		}		
	    }
	    else{
		$stats->{output}->{lc($classification)}++;
	    }
	}
    }
    if (scalar(keys %$mismatchData) > 0){
	$self->writeUserLogBlankLine();
	my $logMsg = "The following mismatches were found between peptide sequences read from the input file and what is stored in modbase. ";
	$logMsg .= "If the phrase \"[overrun - \#\#]\" is output, it means that the specified start position, plus the length of the peptide, was greater than the ";
	$logMsg .= "length of the protein found in modbase, and thus no peptide was found at this position (here, ## is the length of the protein in ModBase, for reference)";
	$self->writeUserLog($logMsg);
	foreach my $accession (keys %$mismatchData){
	    my $startPositions = $mismatchData->{$accession};
	    foreach my $startPosition (keys %$startPositions){
		my $input = $startPositions->{$startPosition}->{input};
		my $found = $startPositions->{$startPosition}->{found};
		$self->writeUserLog("Accession: $accession\tStart Position: $startPosition\tInput: $input\tModbase: $found");
	    }
	}
    }
    $self->writeUserLogBlankLine();
    my $uniqueMismatchAccessionCount = scalar(keys %$mismatchAccessions);
    $stats->{uniqueMismatchAccessionCount} = $uniqueMismatchAccessionCount;
    return ($peptideFileInfo, $stats);
}


###########################################################################################################################################################################################
# writePeptideInfo
# Take in user-provided peptide set, which has been validated in other methods, and write to file in preparation for back-end processing
# Format of file is Fasta, with one header line and protein sequence per accession.
# Each header line is of the form: >ModbaseSeqId|UniprotAccession(|peptideStartPosition_peptideSequence_peptideClassification)+
# (one triplet of peptide info for each peptide, separated by '|')
#
# Peptide start positions are all converted to zero-based here.
# 
# PARAM  $sequenceInfo: map of uniprot accessions to modbase sequence IDs of the form $sequenceInfo->{$modbaseSeqId}->{uniprotAccession} = $uniprotAccession
#                                                                                                                   ->{sequence}         = $proteinSequence
# PARAM  $peptideFileInfo: hash containing results of user peptide set, of the form $peptideFileInfo->{$uniprotAccession}->{$peptideStartPosition}->{peptideSequence} = $peptideSequence
#                                                                                                                                                 ->{classification}  = $classification
# PARAM  $directory: directory for this job, created by the framework
# THROW  InternalError if file couldn't be opened (sanity check)
# RETURN NULL 
############################################################################################################################################################################################
sub writePeptideInfo{
    my ($self, $sequenceInfo, $peptideFileInfo, $directory) = @_;

    my $peptideSequenceMismatchKeyword = $self->getParam("keyword_peptide_sequence_mismatch");
    my $peptideFileInputName = $self->getParam("input_fasta_file_name");
    my $fullPeptideFileInputName = "$directory/$peptideFileInputName";
    my $mismatchFileName = $self->getParam("mismatch_file_name");
    my $peptideFileInputFh = FileHandle->new(">" . $fullPeptideFileInputName) || 
	throw saliweb::frontend::InternalError("Could not open peptide file input $fullPeptideFileInputName: $!");

    my $mismatchFastaFh = FileHandle->new(">" . "$directory/$mismatchFileName") || 
	throw saliweb::frontend::InternalError("could not open mismatch file $mismatchFileName: $!");

    my $sequenceCount = 0;
    my $peptideCount = 0;
    my $hasOnlyMismatchesCount = 0; #has only mismatches means that if the user provided incorrect locations for *all* peptides in the protein, we don't write the protein at all
    my $currentMaxPeptideLength = 1;

    foreach my $modbaseSeqId (keys %$sequenceInfo){
	my $uniprotAccession = $sequenceInfo->{$modbaseSeqId}->{uniprotAccession};
	my $peptideStartPositions = $peptideFileInfo->{$uniprotAccession};

	my @allPeptideSpecs;
	my $hasOnlyMismatches = 1;
	my $hasOneMismatch = 0;
	foreach my $peptideStartPosition (keys %$peptideStartPositions){
	    my $peptideSequence = $peptideStartPositions->{$peptideStartPosition}->{peptideSequence};
	    my $classification = $peptideStartPositions->{$peptideStartPosition}->{classification};
	    $hasOneMismatch = 1 if ($peptideSequence eq $peptideSequenceMismatchKeyword);
	    $hasOnlyMismatches = 0 unless ($peptideSequence eq $peptideSequenceMismatchKeyword);
	    $peptideStartPosition -= 1;  #change from 1-based to 0-based to streamline all input
	    my $peptideSpec =  $peptideStartPosition . "_" . $peptideSequence . "_" . $classification;
	    if (length($peptideSequence) > $currentMaxPeptideLength){
		$currentMaxPeptideLength = length($peptideSequence);
	    }
	    push (@allPeptideSpecs, $peptideSpec);
	}
	
	my $peptideSpecString = join ('|', @allPeptideSpecs);
	if ($hasOneMismatch == 1){
	    print $mismatchFastaFh ">" . $uniprotAccession . "\n";
	    my $sequence = $sequenceInfo->{$modbaseSeqId}->{sequence};
	    my $fastaLines = $self->getFormattedLines($sequence, 60, 1);
	    foreach my $line (@$fastaLines){
		print $mismatchFastaFh $line . "\n";
	    }
	}
	if ($hasOnlyMismatches == 1){
	    $hasOnlyMismatchesCount++;
	    $self->writeUserLog("None of the provided peptides for Uniprot Accession $uniprotAccession in the input file was found in the specified position in ModBase.  This protein will not be considered in any analysis");
	}
	else {
	    #write fasta header and sequence
	    print $peptideFileInputFh ">" . $modbaseSeqId . "|" . $uniprotAccession . "|";
	    print $peptideFileInputFh  $peptideSpecString . "\n";
	    my $sequence = $sequenceInfo->{$modbaseSeqId}->{sequence};
	    print $peptideFileInputFh $sequence . "\n";
	    $peptideCount += scalar(@allPeptideSpecs);
	    $sequenceCount++;
	}
    }
    $self->{MaxPeptideLength} = $currentMaxPeptideLength;
    $mismatchFastaFh->close();
    #Check to make sure one sequence was written; if not, output error
    if ($sequenceCount == 0){   

	my $msg = "Error: No input matched anything in ModBase. This could be either due to not finding Uniprot Accessions in Modbase, or because peptides provided did not match peptide sequence for the proteins in modbase. The following Uniprot accessions were not found in ModBase:<br><br>";
	my $noUniprot = $self->makeMissingUniprotString();
	$msg .= $noUniprot;
	$msg .= "<br><br>The amino acid sequences of accessions that were found in Modbase, but were not found in your input, are shown here. Make sure your numbering system starts with 1 (i.e., that a peptide starting at the 56th residue in the protein is listed in your input file as 56).<br><br>";

	my $mismatchFileName = $self->getParam("mismatch_file_name");
	my $mismatchFastaString = $self->makeMismatchFastaString("$directory/$mismatchFileName");
	$msg .= $mismatchFastaString;
	
	throw saliweb::frontend::InputValidationError($msg);
    }
    $self->writeInternalLog("Wrote all sequences to fasta format in file $fullPeptideFileInputName.  Processed $sequenceCount proteins containing $peptideCount peptides");
    $self->writeInternalLog("$hasOnlyMismatchesCount proteins had only mismatches bewteen ModBase peptides and user-supplied peptides; these were not written");
}

###############################################################################################################################################
# readAndValidateApplicationFile
# Reads user-submitted file that specifies the Uniprot Accessions which will be parsed for peptides that will be scored in application mode.
# Here, the user has not listed specific peptides for each accession. The file is intended to be a simple list of accessions, one per line, and nothing else.
#
# PARAM  $applicationFh: FileHandle for uploaded file (automatically created upon submission).
# THROW  InputValidationError for a few different reasons related to simple formatting mistakes.
# RETURN array reference where each entry is an accession.
###############################################################################################################################################
sub readAndValidateApplicationFile{
    my ($self, $applicationFh, $directory) = @_;

    my @uniprotAccessionList;

    #enforce file exists
    if (!$applicationFh){

	throw saliweb::frontend::InputValidationError("No application target file has been submitted.");
    }

    my $savedInputFileName = $directory . "/" .  $self->getParam("saved_input_file_name");

    my $savedInputFh = FileHandle->new(">" . "$savedInputFileName")  || 
	throw saliweb::frontend::InternalError("Could not open peptide file input $savedInputFileName: $!");

    while (<$applicationFh>){
	chomp;
	my $line = $_;
	print $savedInputFh $line . "\n";	
	next unless ($line =~ /(\w+)/); 
	$line =~ s/[\r\n]//g; 
	#enforce no whitespace in line
	if ($line =~ /(\w+)\s+(\w+)/){
	    throw saliweb::frontend::InputValidationError("Syntax error in application target file:  Each line is expected to be one uniprot accession (no spaces).  The following line contains more than one entry: \n$line");
	}

	push (@uniprotAccessionList, $line);
    }
    
    #enforce there was at least one valid entry
    if (scalar(@uniprotAccessionList) == 0){

	throw saliweb::frontend::InputValidationError("The submitted application target file did not contain any entries");
    }
    return \@uniprotAccessionList;
}


##############################################################################################################################################################################
# readAndValidateRulesFile
# Reads optional user-submitted 'rules' file that tells server how to determine which peptides to score from the sequences associated with the submitted Uniprot Accessions.
# The backend will scan the sequence for each accession and parse peptides that correspond to the rules specified in this file. If no file is specified, then all peptides
# in the sequence of length n will be scored (which is usually unnecessary, hence the file); n is the length of the peptides on which the scoring model was trained.
#
# Each position to restrict is designated with one line in the file. The line should begin with a number representing the position in the peptide,
# followed by a space separated list of residues that should not be present in that position. If there are no restrictions on a position in the peptide, 
# then there does not need to be a line specifying that position. Position counting is 1-based.
#
# An example rules file:
# 1 E D
# 4 A C E F G H I K L M N P Q R S T V W Y
# 8 W
# 
# This file will tell the service to only score peptides that don't have an acidic residue in the first position, 
# that only contain Asp in the fourth position, and that don't have Trp in the 8th position. 
#
# PARAM  $rulesFh: FileHandle for uploaded rules file (automatically created upon submission)
# PARAM  $peptideLength: Length of each peptide that will be scored after parsing.  All peptide lengths must be the same.
# 
# THROW  InputValidationError for a number of reasons related to formatting
# RETURN array reference where each entry is one of the lines in the rules file
##############################################################################################################################################################################
sub readAndValidateRulesFile{

    my ($self, $rulesFh, $peptideLength) = @_;

    my @rulesFileLines;

    my $positionsFound;
    my $hasContent = 0;
    while (<$rulesFh>){
	chomp;
	my $line = $_;
	next unless ($line =~ /\w+/); 
	$line =~ s/[\r\n]//g; 
	$hasContent = 1;
	my @cols = split('\s+', $line);
	my $position = $cols[0];
	if ($positionsFound->{$position}){

	    throw saliweb::frontend::InputValidationError("Syntax error in peptide specifier file:  the same position ($position) was found in two different places in the file.  Please make sure each position appears only once.");
	}
	$positionsFound->{$position} = 1;
	if ($position =~ /\D/){   #check position is a number

	    throw saliweb::frontend::InputValidationError("Syntax error in peptide specifier file:  Make sure each line in the file begins with a number representing a position in the peptide (no letters or spaces). The number should then be followed by a space.");
	}
	
	for (my $i = 1; $i < scalar(@cols); $i++){
	    my $nextResidue = $cols[$i];
	    if ($nextResidue =~ /[^a-zA-Z]/ || length($nextResidue) > 1){   #check we have a letter and there's only one

		throw saliweb::frontend::InputValidationError("Syntax error in peptide specifier file:  Each residue following the position must be designated by one letter, each separated by a space (The string '$nextResidue' was found in your file).");
	    }
	    elsif ($nextResidue eq "B" || $nextResidue eq "J" || $nextResidue eq "O" || $nextResidue eq "U" || $nextResidue eq "X" || $nextResidue eq "Z"){  #standard AAs

		throw saliweb::frontend::InputValidationError("Content error in peptide specifier file: Each residue in the file must be one of the 20 standard amino acids (the residue '$nextResidue' was found in your file).");
	    }
	}
	if (scalar(@cols) > 20){   #make sure not all AAs are on the line
	    my $number = scalar(@cols) - 1;

	    throw saliweb::frontend::InputValidationError("Content error in peptide specifier file: You cannot exclude all 20 residues for position $position (or your line for this position has duplicate residues).");
	}
	if ($position > $peptideLength){  #specified position doesn't exceed peptide length

	    throw saliweb::frontend::InputValidationError("Content error in peptide specifier file: The selected model was trained on peptides of length $peptideLength, and will only score peptides of the same length.  Position $position in the specifier file exceeds this length.  Please remove it from the file.");
	}

	push (@rulesFileLines, $line);

    }
    if ($hasContent == 0){
	$self->writeUserLog("No rules file was provided, and all peptides will be scored. To reduce the amount of output, consider specifying certain peptide motifs only (see documentation for more information).");
    }
    return \@rulesFileLines;
}

###########################################################################################################################################################
# writeApplicationInfo
# Take in user-provided application set of accessions, for which other methods have validated and retrieved sequences,
# and write to file in preparation for back-end processing. Here, user has not included specific peptides.
# Format of file is Fasta, with one header line and protein sequence per accession.
# Each header line is of the form: >ModbaseSeqId|UniprotAccession
#
# Also write user stats.
#
# PARAM  $directory: directory for this job, created by the framework
# PARAM  $sequenceInfo: map of uniprot accessions to modbase sequence IDs of the form $sequenceInfo->{$modbaseSeqId}->{uniprotAccession} = $uniprotAccession
#                                                                                                                   ->{sequence}         = $proteinSequence
# THROW  InternalError if method fails various sanity checks.
# RETURN NULL
###########################################################################################################################################################
sub writeApplicationInfo{

    my ($self, $directory, $sequenceInfo) = @_;

    my $inputFastaFileName = $self->getParam("input_fasta_file_name");
    my $fullInputFastaFileName = "$directory/$inputFastaFileName";
    my $fullInputFastaFh = FileHandle->new(">" . $fullInputFastaFileName) || 
	throw saliweb::frontend::InternalError("Could not open fasta input file $fullInputFastaFileName: $!");
    
    my $sequenceCount = 0;

    foreach my $modbaseSeqId (keys %$sequenceInfo){
	my $uniprotAccession = $sequenceInfo->{$modbaseSeqId}->{uniprotAccession};
	my $sequence = $sequenceInfo->{$modbaseSeqId}->{sequence};
	print $fullInputFastaFh ">$modbaseSeqId|$uniprotAccession\n$sequence\n";   
	$sequenceCount++;
    }

    my $missingAccessions = $self->getMissingUniprotAccessions();
    my $duplicateAccessions = $self->{DuplicateUniprotAccessions};
    my $missedSequenceCount = scalar(keys %$missingAccessions);
    my $totalSequenceCount = $missedSequenceCount + $sequenceCount;
    $self->writeUserLogBlankLine();
    $self->writeUserLog("Done processing user input");
    
    $self->writeUserLog("Number of accessions read from input file: $totalSequenceCount");
    $self->writeUserLog("Number of accessions found in modbase: $sequenceCount");
    $self->writeUserLog("Number of accessions missed (noted above in this log file): $missedSequenceCount");
    $self->writeUserLog("Number of accessions discarded due to being identical to another Uniprot accession (noted above in this log file): $duplicateAccessions");
    $self->writeUserLogBlankLine();
    $self->writeInternalLog("Wrote all application proteins to fasta format in file $fullInputFastaFileName.  Processed $sequenceCount proteins");
}

#####################################################################################
# writeRulesFileOutput
# Copy user provided rules file to job directory. If no rules file, creates placeholder with "###" in line 1.
# PARAM  $rulesFileLines: array reference where each entry is one line of rules file
# PARAM  $directory: directory for this job, created by the framework
# THROW  InternalError if various sanity checks fail
# RETURN NULL
#####################################################################################
sub writeRulesFileOutput{
    my ($self, $rulesFileLines, $directory) = @_;

    my $rulesFileName = $self->getParam("rules_file_name");
    my $fullRulesFileName = $directory . "/$rulesFileName";
    
    my $rulesOutputFh = FileHandle->new(">" . $fullRulesFileName) || 
	throw saliweb::frontend::InternalError("Could not open file to write rules output.  File name: $fullRulesFileName: $!");
    if (scalar(@$rulesFileLines == 0)){
	print $rulesOutputFh "### No rules file specified";
    }
    else {
	foreach my $line (@$rulesFileLines){
	    print $rulesOutputFh $line . "\n";
	}
    }
    $rulesOutputFh->close();
}

###########################################################################################################################################################################
# getSequencesFromModbase
# Given a list of Uniprot Accessions, query modbase_synonyms to get the modbase sequence id (long string representing its unique checksum) and amino acid sequences 
# for each accession.
#
# Only retrieves 'current' uniprot accessions (not deprecated in ModBase; see ModBase documentation for exact definition). Joins on uniprot_taxonomy, nr, and aasequences.
# If a sequence isn't found, proceeds according to Error Handling option set by user.
#
# PARAM  $errorHandling: Either "I" or "Q".  "I" ignores sequences not found in ModBase and writes them to the log.  "Q" quits before the job is sent to the backend.
# PARAM  @accessions: Array of Uniprot Accessions which are searched for in the nr table.
# THROW  InputValidationError if $errorHandling set to "Q" and sequence not found.
#        InternalError if certain sanity checks fail.
# RETURN $sequenceInfo: map of uniprot accessions to modbase sequence IDs of the form $sequenceInfo->{$modbaseSeqId}->{uniprotAccession} = $uniprotAccession
#                                                                                                                   ->{sequence}         = $proteinSequence

###########################################################################################################################################################################
sub getSequencesFromModbase{
    
    my ($self, $errorHandling, @accessions) = @_;
    
    my $inputCount = scalar(@accessions);
    $self->writeUserLog("Retrieving amino acid residue sequences from ModBase for $inputCount provided UniProt accessions");
        
    my $dbh = $self->dbh();
    
    my $query =  "select n.seq_id, a.sequence";
    $query   .= " from modbase_synonyms.nr n, modbase_synonyms.uniprot_taxonomy u, modbase_synonyms.aasequences a";
    $query   .= " where n.seq_id = u.seq_id and n.seq_id = a.seq_id and u.current = 1";
    $query   .= " and n.database_id = ?";
    
    #removed reference to modbase.sequences, which was used to sort by which modpipe run was used to create a model -- check webServerNotes for thoughts on this.                      

    my $sth = $dbh->prepare($query);

    my $sequenceInfo;

    my $searchedSequencesCount = 0;
    my $foundSequencesCount = 0;
    my $missedSequencesCount = 0;
    my $processedModbaseSeqIds;
    foreach my $uniprotAccession (@accessions){
	
	$sth->execute($uniprotAccession);

	$searchedSequencesCount++;
	$self->writeInternalLog("Processing protein number $searchedSequencesCount") if ($searchedSequencesCount % 1000 == 0);
	my ($modbaseSeqId, $sequence) = $sth->fetchrow_array();
	if ($modbaseSeqId){   #found sequence in modbase, add it to $sequenceInfo
	    $processedModbaseSeqIds->{$modbaseSeqId}->{$uniprotAccession} = 1;

	    $sequenceInfo->{$modbaseSeqId}->{uniprotAccession} = $uniprotAccession;
	    $sequenceInfo->{$modbaseSeqId}->{sequence} = $sequence;
	    $foundSequencesCount++;
	}
	else {
	    if ($errorHandling eq "I"){  #Do not include this uniprot accession in any analysis (just make a note in log file)

		$self->writeUserLog("Uniprot accession $uniprotAccession was not found in ModBase");
		$self->addMissingUniprotAccession($uniprotAccession);
		$missedSequencesCount++;
	    }
	    elsif ($errorHandling eq "Q"){ # Quit
		throw saliweb::frontend::InputValidationError("Error: the Uniprot accession $uniprotAccession was not found in ModBase. Since the error handling option was set to 'Quit', this job will now quit. If you are submitting a large number of proteins, consider setting error handling to 'Ignore' to continue processing the remaining proteins.  For more information as to why this accession was not found, refer to the help section by clicking on the above link.  We apologize for the inconvenience.");
	    }
	    else {
		throw saliweb::frontend::InternalError("Did not get expected error handling mode (expect 'I' or 'Q', instead got $errorHandling.)");
	    }
	}
    }
    if ($foundSequencesCount == 0){   #we will only get here if error handling was set to "I" and no sequences were found (rare case)

	throw saliweb::frontend::InputValidationError("Error: None of the Uniprot accessions in the uploaded file was found in ModBase.  Although the error handling option was 'Ignore', this job will now quit due to having no input to process.  For more information as to why the accessions were not found, refer to the help section by clicking on the above link.  We apologize for the inconvenience.");
    }
    
    if ($foundSequencesCount + $missedSequencesCount != $searchedSequencesCount){  #doubt this will happen but could help reign in issues with queries and joins
	my $errorMessage = "Sanity Error: searched for $searchedSequencesCount; found $foundSequencesCount and missed $missedSequencesCount, but the total of found + missed is not equal to searched";
	throw saliweb::frontend::InternalError($errorMessage);
    }
    my $duplicateCount = 0;
    #Output lists of uniprot accessions that all mapped to the same sequence
    foreach my $modbaseSeqId (keys %$processedModbaseSeqIds){
	my $uniprotAccessions = $processedModbaseSeqIds->{$modbaseSeqId};
	my $uniprotCount = scalar (keys %$uniprotAccessions);
	if ($uniprotCount > 1){
	    $duplicateCount += $uniprotCount  - 1;
	    my $uniprotString = join(', ', keys %$uniprotAccessions);
	    $self->writeUserLog("The following Uniprot Accessions all mapped to the same sequence: $uniprotString");
	}
    }
    $self->{DuplicateUniprotAccessions} = $duplicateCount;
    $self->{ModbaseToDuplicateUniprot} = $processedModbaseSeqIds;
    return $sequenceInfo;
}


##############################################################################################################################################
# writeApplicationStats
# Writes various statistics about which application peptides were found in the modbase sequences or not. 
# 
# PARAM  $stats: hash containing stats, generated in validatePeptideSequenceInfo()
# RETURN NULL
##############################################################################################################################################
sub writeApplicationStats{
    my ($self, $stats) = @_;
    #output stats
    my $appKeyword = $self->getParam("keyword_application_classification");
    my $inputAccessionsCount = $stats->{input}->{accessions} || "zero";
    my $inputCount = $stats->{input}->{lc($appKeyword)} || "zero";
    my $outputCount = $stats->{output}->{lc($appKeyword)} || "zero";
    my $mismatchCount = $stats->{mismatch} || "zero";
    my $uniqueMismatchAccessionCount = $stats->{uniqueMismatchAccessionCount} || "zero";
    my $missingAccessions = $self->getMissingUniprotAccessions();
    my $missedSequenceCount = scalar(keys %$missingAccessions);    
    my $totalSequenceCount = $missedSequenceCount + $inputAccessionsCount;
    my $duplicateUniprot = $self->{DuplicateUniprotAccessions};

    $self->writeUserLog("Done processing user input");
    $self->writeUserLog("Number of accessions read from input file: $totalSequenceCount");
    $self->writeUserLog("Accessions found in modbase: $inputAccessionsCount");
    $self->writeUserLog("Accessions not found in modbase (noted above in this log file): $missedSequenceCount");
    $self->writeUserLog("Number of accessions discarded due to being identical to another Uniprot accession (noted above in this log file): $duplicateUniprot");
    $self->writeUserLog("Number of user-specified peptides supplied in modbase proteins: $inputCount");
    $self->writeUserLog("User-specified peptides matching modbase protein sequences: $outputCount");
    $self->writeUserLog("Peptides not matching the modbase sequence at the user-supplied position: $mismatchCount");
    $self->writeUserLog("Number of unique proteins containing these mismatched peptides: $uniqueMismatchAccessionCount");
    $self->writeUserLog("Mismatches are noted above in the log file");

    $self->writeUserLogBlankLine();
}

##############################################################################################################################################
# writeTrainingStats
# Writes various statistics about which training peptides were found in the modbase sequences or not. Also calls an additional validation method.
# 
# PARAM  $stats: hash containing stats, generated in validatePeptideSequenceInfo()
# RETURN NULL
##############################################################################################################################################
sub writeTrainingStats{
    my ($self, $stats, $directory) = @_;

    #output stats
    my $inputAccessionsCount = $stats->{input}->{accessions} || "zero";
    my $inputPositiveCount = $stats->{input}->{positive} || "zero";
    my $inputNegativeCount = $stats->{input}->{negative} || "zero";
    my $outputPositiveCount = $stats->{output}->{positive} || "zero";
    my $outputNegativeCount = $stats->{output}->{negative} || "zero";
    my $mismatchCount = $stats->{mismatch} || "zero";
    my $uniqueMismatchAccessionCount = $stats->{uniqueMismatchAccessionCount} || "zero";

    my $inputTotal = $inputPositiveCount + $inputNegativeCount;
    my $outputTotal = $outputPositiveCount + $outputNegativeCount;

    my $missingAccessions = $self->getMissingUniprotAccessions();
    my $missedSequenceCount = scalar(keys %$missingAccessions);    
    my $totalSequenceCount = $missedSequenceCount + $inputAccessionsCount;
    my $duplicateAccessions = $self->{DuplicateUniprotAccessions};

    $self->writeUserLogBlankLine();
    $self->writeUserLog("Done processing user input");
    $self->writeUserLog("Number of accessions read from input file: $totalSequenceCount");
    $self->writeUserLog("Accessions found in modbase: $inputAccessionsCount");
    $self->writeUserLog("Accessions not found in modbase (noted above in this log file): $missedSequenceCount");
    $self->writeUserLog("Accessions discarded due to being identical to another Uniprot accession (noted above in this log file): $duplicateAccessions");

    $self->writeUserLog("Number of user-specified peptides supplied in modbase proteins: $inputTotal");
    $self->writeUserLog("Positives: $inputPositiveCount");
    $self->writeUserLog("Negatives: $inputNegativeCount");

    $self->writeUserLog("Number of user-specified peptides matching modbase protein sequences: $outputTotal");
    $self->writeUserLog("Positives: $outputPositiveCount");
    $self->writeUserLog("Negatives: $outputNegativeCount");
 
    $self->writeUserLog("Number of peptides that didn't match the modbase sequence at the user-supplied position in the sequence: $mismatchCount");
    $self->writeUserLog("Number of unique proteins containing these mismatched peptides: $uniqueMismatchAccessionCount");
    $self->writeUserLog("Mismatches are noted above in the log file");

    $self->writeUserLogBlankLine();
    
    #more validation; do this here because the counts that are passed are all validated peptides (could also move up to where writeTrainingStats() is called
    $self->validateTrainingAndTestRatios($outputPositiveCount, $outputNegativeCount, $directory);
}

 

##############################################################################################################################################
# getSvmModelFileLocation
# Dynamically gets SVM model file location based on which protease model the user wants to score with.
# There are only two options currently, which were created for the current study, but this will get more involved
# once we allow the user to upload their own model or save them. 10-22-10: added hiv!
# 
# PARAM  $svmModel: name of SVM model, taken from CV (either grb or caspase, generated internally according to user drop-down box selection.
# THROW  InternalError if various sanity checks fail.
# RETURN Full path of SVM model file location, read from original global parameter file.
##############################################################################################################################################
sub getSvmModelFileLocation{
    my ($self, $svmModel) = @_;
    
    #TODO -- read dynamically from DB or directory after there are more than two
    my $modelFile;
    if ($svmModel eq "grb"){
	$modelFile = $self->getParam("grb_model_file");
    }
    
    elsif ($svmModel eq "caspase"){
	$modelFile =  $self->getParam("caspase_model_file");
    }
    elsif ($svmModel eq "hiv"){
	$modelFile = $self->getParam("hiv_model_file");
    }

    else{
	unless ($svmModel eq "custom"){
	    throw saliweb::frontend::InternalError("Did not get expected SVM Model type (expect 'grb', 'caspase', 'hiv', or 'custom'; instead got $svmModel)");
	}
    }
    return $modelFile;
    
}

##############################################################################################################################################
# getBenchmarkScoreFileLocation
# Dynamically gets benchmark score file location (this file contains the FPR and TPR for each SVM score in the benchmark set and can
# be used to give a confidence metric of an SVM score in application mode. There are only two options currently, which were created for 
# the current study, but this will get more involved once we allow the user to upload their own model or save them. 
#
# PARAM  $svmModel: name of SVM model, taken from CV (either grb or caspase, generated internally according to user drop-down box selection. 
# THROW  InternalError if various sanity checks fail.                                                                                                                         
# RETURN Full path of benchmark file location, read from original global parameter file.      
##############################################################################################################################################
sub getBenchmarkScoreFileLocation{
    my ($self, $svmModel) = @_;
    
    #TODO -- read dynamically from DB or directory after there are more than two (new TODO -- we're doing that in preprocess on backend, but should move this there too)
    my $benchmarkScoreFile;
    if ($svmModel eq "grb"){
	$benchmarkScoreFile = $self->getParam("grb_benchmark_score_file");
    }
    
    elsif ($svmModel eq "caspase"){
	$benchmarkScoreFile =  $self->getParam("caspase_benchmark_score_file");
    }
    elsif ($svmModel eq "hiv"){
	$benchmarkScoreFile =  $self->getParam("hiv_benchmark_score_file");
    }
    else{
	unless ($svmModel eq "custom"){
	    throw saliweb::frontend::InternalError("Did not get expected SVM Model type (expect 'grb', 'caspase', 'hiv', or 'custom'; instead got $svmModel)");
	}
    }

    $self->writeInternalLog("Using benchmark score file $benchmarkScoreFile for svm model $svmModel");
    return $benchmarkScoreFile;
    
}

sub processUserCreatedModel{
    my ($self, $directory, $modelPackageFh) = @_;

    my $separator = $self->getParam("user_separator_line");

    my $customModelFile = $self->getParam("custom_model_file");
    my $customModelFh = FileHandle->new(">" . $directory . "/" . $customModelFile) ||
	throw saliweb::frontend::InternalError("Could not open custom model file for writing: $!");

    my $customBenchmarkFile = $self->getParam("custom_benchmark_file");
    my $customBenchmarkFh = FileHandle->new(">" . $directory . "/" . $customBenchmarkFile) ||
	throw saliweb::frontend::InternalError("Could not open custom benchmark file for writing: $!");
    
    my $writingModelFile = 1;

    my $invalidModelFileMsg = "Did not get expected file format for svm model generated in a previous iteration of the PCSS server in training mode.";
    $invalidModelFileMsg .= "If you previously downloaded this file, please ensure that you have not modified it before submitting it here.";
    $invalidModelFileMsg .= "If you are seeing this error message but have not modified the file, please contact the administrator for more help by clicking the link above";
    
    my $peptideLength = 0;

    my $modelLineCount = 0;
    my $benchmarkLineCount = 0;
    while (<$modelPackageFh>){
	chomp;
	my $line = $_;
	if ($line eq $separator){
	    $writingModelFile = 0;
	    my $peptideLengthLine = <$modelPackageFh>;
	    chomp $peptideLengthLine;
	    if ($peptideLengthLine =~ /peptideLength\s(\d+)/){
		$peptideLength = $1;
	    }
	    else{
		throw saliweb::frontend::InputValidationError($invalidModelFileMsg);
	    }
	    next;
	}
	if ($writingModelFile){
	    print $customModelFh $line . "\n";
	    $modelLineCount++ unless $line =~ /^\s*$/;
	}
	else {
	    print $customBenchmarkFh $line . "\n";
	    $benchmarkLineCount++ unless ($line =~ /^\s*$/ || $line =~ /ritical/);
	}
    }
    if ($writingModelFile == 1){
	throw saliweb::frontend::InputValidationError($invalidModelFileMsg);  #never found separator
    }
    if ($benchmarkLineCount < 3){
	throw saliweb::frontend::InputValidationError($invalidModelFileMsg);  #benchmark line too small or not included
    }
    if ($modelLineCount == 0){
	throw saliweb::frontend::InputValidationError($invalidModelFileMsg);  #model not included
    }
    return $peptideLength;
}

sub validateModelSpecified{
    my ($self, $svmModel, $svmCustomModel) = @_;

    if ($svmModel eq "none"){
	unless ($svmCustomModel){
	    throw saliweb::frontend::InputValidationError("Please either upload a model generated in training mode or select a pre-generated model using the drop-down box");
	}
    }
}



##############################################################################################################################################
# formatProteinSequence
# Takes a protein sequence represented by one string and inserts <br> every sixty residues.  This allows cleaner html output when the sequence 
# needs to be displayed to the user.
# PARAM  $proteinSequence: The sequence to be formatted.
# RETURN The resulting string.
##############################################################################################################################################
sub formatProteinSequence{
    my ($self, $proteinSequence) = @_;
    my $length = length($proteinSequence);
    my $currentSection = "";
    my $output = "";
    my $counter = 0;
    my @seqArray = split('', $proteinSequence);
    while ($counter < $length){
	if ($counter % 60 == 0){
	    $output .= $currentSection;
	    $currentSection = "<br>";
	}
	my $nextCharacter = $seqArray[$counter];
	$currentSection .= $nextCharacter;
	$counter++;
    }
    $output .=  $currentSection;
    return $output;
}

##################################################################################################################################################
# validateTrainingAndTestRatios
# Given counts of positive and negative peptides in training, ensures that there are the appropriate levels of each to perform the training.
# This is subject to the following rules:
#
# 1. There are more negatives than positives (note that if this is an issue for the user, they can just switch the classification labels)
# 2. There is at least one positive in the test set after the jackknife_fraction has been applied (i.e. test_set_percentage)
# 
# More rules may be added as needed.
#
# PARAM  $positiveCount, $negativeCount: counts of training set positive and negative peptides, intended to have been validated as being present 
#        in ModBase before this method is called.
#
# THROW  InputValidationError if the ratio checks fail.
# RETURN NULL
###################################################################################################################################################
sub validateTrainingAndTestRatios{
    my ($self, $positiveCount, $negativeCount, $directory) = @_;

    #enforce more negatives than positives

    if ($negativeCount < $positiveCount){
	my $message = "Please change the number of negative peptides in your input file to be greater than or equal to the number of positive peptides.\n";
	$message .= "The number of negatives provided was $negativeCount and the number of positives was $positiveCount.\n";
	$message .= "Note that the number of each found in ModBase might be fewer than how many were provided in the input file.\n";
	$message .= "Please examine these lists to see if that is the case <br><br>";
	$message .= "The following Uniprot accessions were not found in ModBase:<br><br>";
	my $noUniprot = $self->makeMissingUniprotString();
	$message .= $noUniprot;
	$message .= "<br><br>The amino acid sequences of accessions that were found in Modbase, but were not found in your input, are shown here. Make sure your numbering system starts with 1 (i.e., that a peptide starting at the 56th residue in the protein is listed in your input file as 56).<br><br>";

	my $mismatchFileName = $self->getParam("mismatch_file_name");
	my $mismatchFastaString = $self->makeMismatchFastaString("$directory/$mismatchFileName");
	$message .= $mismatchFastaString;

	throw saliweb::frontend::InputValidationError($message);
    }

    #enforce one positive in test set
    my $testSetPercentage = $self->getParam("test_set_percentage");
    my $testSetPositiveCount = floor(($positiveCount * 1.0) * ($testSetPercentage * 1.0));

    if ($testSetPositiveCount < 1){
	my $message = "Please change the number of positives in your input file to ensure that there is at least one peptide left for testing when the jackknife fraction is applied (rounded down).\n";
	$message .= "The number of positives provided was $positiveCount which results in $testSetPositiveCount allowed in the test set when the fraction $testSetPercentage is applied.\n";
	$message .= "Note that the number of each found in ModBase might be fewer than how many were provided in the input file\n";
	$message .= "Please examine these lists to see if that is the case <br><br>";
	$message .= "The following Uniprot accessions were not found in ModBase:<br><br>";
	my $noUniprot = $self->makeMissingUniprotString();
	$message .= $noUniprot;
	$message .= "<br><br>The amino acid sequences of accessions that were found in Modbase, but were not found in your input, are shown here. Make sure your numbering system starts with 1 (i.e., that a peptide starting at the 56th residue in the protein is listed in your input file as 56).<br><br>";


	my $mismatchFileName = $self->getParam("mismatch_file_name");
	my $mismatchFastaString = $self->makeMismatchFastaString("$directory/$mismatchFileName");
	$message .= $mismatchFastaString;
	throw saliweb::frontend::InputValidationError($message);
    }
}

###############################################################################################
# makeMismatchFastaString
# Given a fasta file name (intended to be one where only mismatches were included for all sequences contained), read all sequences
# and make a cleanly formatted string representing them that can be printed to the web page in various cases.
# 
# PARAM  $fullMismatchFileName: the name of the fasta file
# RETURN String to be printed to screen
###############################################################################################
sub makeMismatchFastaString{
    my ($self, $fullMismatchFileName) = @_;
    my $msg = "";
    my $mismatchFastaFh = FileHandle->new("<" . "$fullMismatchFileName") || 
	    throw saliweb::frontend::InternalError("could not open mismatch file $fullMismatchFileName: $!");
    my $fastaLine = "";

    my $headerToFasta;

    while (<$mismatchFastaFh>){
	chomp;
	my $line = $_;
	$line =~ s/[\r\n]//g; 
	if ($line =~ /^\>/){
	    $msg .= $line . "<br>";
	}
	else {
	    my $fastaLines = $self->getFormattedLines($line, 40, 1);	    
	    foreach my $line (@$fastaLines){
		$msg .= $line . "<br>";
	    }
	    $msg .= "<br>";
	}
    }
        
    return $msg;
}


###############################
# validateJobName
# Enforces user-specified job name not blank
#
# PARAM  $name: Name of job specified by user in web form
# THROW  InputValidationError if $name doesn't have one non-space character
# RETURN NULL
###############################
sub validateJobName{
    my ($self, $name) = @_;
    if ($name =~ /^\s*$/){
	throw saliweb::frontend::InputValidationError("Please provide a name for your job run");
    }
}


#####################################################################
# validateJackknifeFraction 
# Enforces user-specified jackknife fraction to be <= 0.5.
#
# PARAM  $jackknifeFraction: fraction specified by user in web form.
# THROW  InputValidationError if $jackknifeFraction > 0.5
# RETURN NULL
#####################################################################
sub validateJackknifeFraction{
    my ($self, $jackknifeFraction) = @_;

    if ($jackknifeFraction > .5){
	throw saliweb::frontend::InputValidationError("Please set the Jackknife Fraction value to 0.5 or less (current value is $jackknifeFraction).");
    }
    if ($jackknifeFraction == 0){
	throw saliweb::frontend::InputValidationError("Please set the Jackknife Fraction to a value greater than 0");
    }
}

#################################################################################
# validateTrainingIterations
# Enforces user-specified number of iterations in training mode to be <= 1000
#
# PARAM  $trainingIterations: Number of iterations specified by user in web form.
# THROW  InputValidationError if $trainingIterations > 1000
# RETURN NULL
#################################################################################
sub validateTrainingIterations{
    my ($self, $trainingIterations) = @_;

    if ($trainingIterations > 1000){
	throw saliweb::frontend::InputValidationError("Please set the Training Iterations value to 1000 or less (current value is $trainingIterations).");
    }

}

##################################################################################################################
# getUserLogFile
# Create filehandle for log which will presented to user after job completion.  FileHandle is stored internally.
# PARAM  $directory: directory for this job, created by the framework
# THROW  InternalError if various sanity checks fail
# RETURN NULL
##################################################################################################################
sub getUserLogFile{

    my ($self, $directory) = @_;

    my $logFileName = $self->getParam("user_log_file_name");
    my $fullLogFileName = $directory . "/$logFileName";
    my $logFh = FileHandle->new(">" .  "$fullLogFileName") || 
	throw saliweb::frontend::InternalError("Could not open log file $fullLogFileName: $!");
    $self->{UserLogFh} = $logFh;
}


##################################################################################################################
# getInternalLogFile
# Create filehandle for internal framework log which will presented to user after job completion.  FileHandle is stored internally.
# This is intended to be the same framework log file that the backend also writes to.
# PARAM  $directory: directory for this job, created by the framework
# THROW  InternalError if various sanity checks fail
# RETURN NULL
##################################################################################################################
sub getInternalLogFile{

    my ($self, $directory) = @_;

    my $logFileName = $self->getParam("framework_log_file_name");
    my $fullLogFileName = $directory . "/$logFileName";
    my $logFh = FileHandle->new(">" .  "/$fullLogFileName") || 
	throw saliweb::frontend::InternalError("Could not open log file $fullLogFileName: $!");
    $self->{InternalLogFh} = $logFh;
    $self->{InternalLogFileName} = $fullLogFileName;
}


#######################################################################
# readParameterFile
# Read global parameter file and store name/value pairs.
# Format of parameter file is tab separated list of name / value pairs.
# PARAM  $parameterFileName: full path of parameter filename.
# THROW  InternalError if various sanity checks fail.
# RETURN NULL
#######################################################################
sub readParameterFile{
    my ($self, $parameterFileName) = @_;

    my $parameterFh = FileHandle->new("<" . $parameterFileName) ||
	throw saliweb::frontend::InternalError("Could not open global parameter file $parameterFileName: $!");

    while (<$parameterFh>){
	chomp;
	my $line = $_;
	$line =~ s/[\r\n]//g; 
	next if ($line =~ /^\#/);
	next unless ($line =~ /\w/);
	my ($paramName, $paramValue) = split('\t', $line);
	$self->{Parameters}->{$paramName} = $paramValue;
    }

}

####################################################################################################################
# writeParameters
# Write all parameters to file specific to this job run.  This includes initial global parameters and any that were
# set by frontend execution.  This is intended to be called just before passing the job off to the backend.
# PARAM  $directory: directory for this job, created by the framework
# THROW  InternalError if various sanity checks fail.
# RETURN NULL
####################################################################################################################
sub writeParameters{

    my ($self, $directory) = @_;

    my $jobParameterFileName = $self->getParam("job_parameter_file_name");
    my $fullJobParameterFileName = $directory . "/" . $jobParameterFileName;
    
    my $parameterFh = FileHandle->new(">" . $fullJobParameterFileName) || 
	throw saliweb::frontend::InternalError("Could not open job parameter file for writing (file name:  $fullJobParameterFileName): $!");
    my $parameters = $self->{Parameters};
    
    foreach my $paramName (keys %$parameters){
	my $value = $parameters->{$paramName};
	print $parameterFh $paramName . "\t" . $value . "\n";
    }
    $parameterFh->close();
}

#####################################################################################################################################
# setParam
# Set parameter value.  Parameters are initially read from global parameters file. This frontend module may add to them along the way
# (for example, after reading user input.)
# PARAM  $paramName: name of parameter whose value is to be set.
# PARAM  $paramValue: value to set to $paramName
# PARAM  $writeLog: whether to write this name and value to the user's log (useful for logging values set by user at web site).
# THROW  InternalError if there is already a parameter set with this name
# RETURN NULL
#####################################################################################################################################
sub setParam{

    my ($self, $paramName, $paramValue, $writeLog) = @_;

    my $paramExists = $self->{Parameters}->{$paramName};
    if ($paramExists){
	throw saliweb::frontend::InternalError("Error: Tried to set parameter $paramName with $paramValue but found existing value '$paramExists' for this parameter (did you forget to call frontend->clear() between multiple calls to frontend->process_user_input()?)");
    }
    else {
	$self->{Parameters}->{$paramName} = $paramValue;
	if ($writeLog){
	    $self->writeUserLog("$paramName:\t$paramValue");
	}
    }
    
}

#####################################################################################################################################
# getParam
# Get parameter value.  Parameters are initially read from global parameters file. This frontend module may add to them along the way
# (for example, after reading user input.)
# PARAM  $paramName: name of parameter whose value is to be retrieved.
# THROW  InternalError if there is no parameter with that name.
# RETURN value for $paramName
#####################################################################################################################################
sub getParam{

    my ($self, $paramName) = @_;
    my $paramValue = $self->{Parameters}->{$paramName};

    if (!($paramValue)){
        my $errorString = "Error: Frontend tried to retrieve value for parameter $paramName but this is not a valid parameter.  Valid parameters:";

        foreach my $parameter (keys %{$self->{Parameters}}){
            $errorString .= "--" . $parameter . "\n";
        }
        throw saliweb::frontend::InternalError($errorString);
    }
    return $paramValue;
}

#############################################################################
# writeUserLog
# Write timestamped line to log that user will receive after the job is done.
# PARAM  $message: line to write to log; newline appended.
# RETURN NULL
#############################################################################
sub writeUserLog{
    my ($self, $message) = @_;
    my $logFh = $self->{UserLogFh};
    my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst)=localtime(time);
    
    my $dateLine = sprintf ("%4d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);

    my $lines = $self->getFormattedLines($message, 90, 0);

    my $firstLine = $lines->[0];
    print $logFh "$dateLine:\t $firstLine\n";
    for(my $i = 1; $i < scalar(@$lines); $i++){
	my $line = $lines->[$i];
	print $logFh  "\t\t\t$line\n";
    }

    $self->writeInternalLog($message);
}
#############################################################################
# writeUserLogBlankLine
# Write one blank line, in the user log, with no timestamp
# RETURN NULL
#############################################################################
sub writeUserLogBlankLine{
    my ($self) = @_;
    my $logFh = $self->{UserLogFh};
    print $logFh "\n";
}



#############################################################################
# getFormattedLines
# Cleanly format a long message to be wrapped to multiple lines
# PARAM  $message: string to be formatted
# PARAM  $length:  length of each line to be output
# PARAM  $breakUpWords: If not set, only start a new line at a white space character
# RETURN Array Reference where each entry in the array is a formatted line
#############################################################################
sub getFormattedLines{
    my ($self, $message, $length, $breakUpWords) = @_;
    my $cutPoint = $length;
    my $previousCutPoint = 0;
    my @lines;
    while (1){
	unless ($breakUpWords){  #if $breakUpWords is set, don't start a new line in the middle of a word
	    my $currentCharAt = substr($message, $cutPoint, 1);
	    while ($currentCharAt =~ /\S/){
		$cutPoint++;
		$currentCharAt = substr($message, $cutPoint, 1);
	    }
	}
	my $end = $cutPoint - $previousCutPoint;
	my $substr = substr($message, $previousCutPoint, $cutPoint - $previousCutPoint);
	$previousCutPoint = $cutPoint;
	$cutPoint += $length;
	push(@lines, $substr);
	last if ($previousCutPoint > length($message));
    }
    return \@lines;
}

############################################################################################
# addMissingUniprotAccession
# Add provided accession to internal hash of those that weren't found in ModBase.
############################################################################################
sub addMissingUniprotAccession{
    my ($self, $accession) = @_;
    $self->{MissingUniprot}->{$accession} = 1;
}

############################################################################################
# addMissingUniprotAccession
# Return hash where keys are accessions that weren't found in ModBase
############################################################################################
sub getMissingUniprotAccessions{
    my ($self) = @_;
    return $self->{MissingUniprot};
}


############################################################################################
# makeMissingUniprotString
# For all uniprot accessions that weren't found, return them in a string, separated by <br>
#
# RETURN missing uniprot string
############################################################################################
sub makeMissingUniprotString{
    my ($self) = @_;
    my $accessions = $self->{MissingUniprot};
    my $string = "";
    foreach my $accession (keys %$accessions){
	$string .= $accession . "<br>";
    }
    return $string;
}




############################################################################################
# writeInternalLog
# Write timestamped line to internal framework log; useful for debugging and timing analysis.
# PARAM  $message: line to write to log; newline appended.
# RETURN NULL
############################################################################################
sub writeInternalLog{

    my ($self, $message) = @_;
    my $logFh = $self->{InternalLogFh};
    my ($sec,$min,$hour,$mday,$mon,$year,$wday, $yday,$isdst)=localtime(time);
    
    my $dateLine = sprintf ("%4d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
    
    print $logFh "$dateLine:\t$message\n";
}


sub clear{

    my ($self) = @_;
    if ($self->{InternalLogFh}){
	$self->{InternalLogFh}->close();
    }
    if ($self->{UserLogFh}){
	$self->{UserLogFh}->close();
    }
    $self->{MissingUniprot} = {};
    $self->{Parameters} = {};
}
#sub allow_file_download {
#    my ($self, $file) = @_;
#    return $file eq 'output.pdb' or $file eq 'log';
#}









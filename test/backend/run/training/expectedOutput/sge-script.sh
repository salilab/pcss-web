#!/bin/tcsh
#$ -S /bin/tcsh
#$ -cwd
#$  -o output.txt -e error.txt -l netappsali=1G,database=1G,scratch=1G -l arch=linux-x64 -r y -j y  -l mem_free=1G -l h_rt=72:00:00 -p 0 -t 1-10
setenv _SALI_JOB_DIR `pwd`
echo "STARTED" > ${_SALI_JOB_DIR}/job-state


set HOME_BIN_DIR="/netapp/sali/peptide/bin/"
set HOME_LIB_DIR="/netapp/sali/peptide/lib/"

set HOME_RUN_DIR="/netapp/sali/peptide/live/preprocess/trainingLoo_668280" 

set tasks=( svm_iteration_1 svm_iteration_2 svm_iteration_3 svm_iteration_4 svm_iteration_5 svm_iteration_6 svm_iteration_7 svm_iteration_8 svm_iteration_9 svm_iteration_10 )
set input=$tasks[$SGE_TASK_ID]

set HOME_RESULTS_DIR="$HOME_RUN_DIR/svm/$input"
mkdir -p $HOME_RESULTS_DIR

set NODE_HOME_DIR="/scratch/peptide//$input"
mkdir -p $NODE_HOME_DIR

set MODEL_OUTPUT_FILE_NAME="modelPipelineOut.txt"
set MODEL_RESULTS_FILE_NAME="modelPipelineResults.txt"
set MODEL_LOG_FILE_NAME="modelPipelineLog"

set PARAMETER_FILE_NAME="parameters.txt"
cp $HOME_RUN_DIR/$PARAMETER_FILE_NAME $NODE_HOME_DIR
cp $HOME_RUN_DIR/inputSequences.fasta $NODE_HOME_DIR

echo -e "\nrun_name\t$input" >>  $NODE_HOME_DIR/$PARAMETER_FILE_NAME     

cd $NODE_HOME_DIR
date
hostname
pwd

setenv PERLLIB $HOME_LIB_DIR

perl $HOME_BIN_DIR/runModelPipeline.pl --parameterFileName $PARAMETER_FILE_NAME --pipelineClass BenchmarkerPipeline > & $MODEL_OUTPUT_FILE_NAME

cp  $MODEL_OUTPUT_FILE_NAME  $MODEL_LOG_FILE_NAME $MODEL_RESULTS_FILE_NAME $HOME_RESULTS_DIR

if ($input == svm_iteration_1) then
set CREATION_OUTPUT_FILE_NAME="creationPipelineOut"


echo "svm iteration 1"
echo CreationPipeline
perl $HOME_BIN_DIR/runModelPipeline.pl --parameterFileName $PARAMETER_FILE_NAME --pipelineClass CreationPipeline > & $CREATION_OUTPUT_FILE_NAME  
cp rawUserModelFile $HOME_RUN_DIR
cp $CREATION_OUTPUT_FILE_NAME $HOME_RUN_DIR

set LOO_PARAMETER_FILE_NAME="leaveOneOutParams.txt"
cp $HOME_RUN_DIR/$LOO_PARAMETER_FILE_NAME $NODE_HOME_DIR
echo -e "\nrun_name\t$input" >>  $NODE_HOME_DIR/$LOO_PARAMETER_FILE_NAME     
set LOO_MODEL_LOG_FILE_NAME="looModelPipelineLog"
set LOO_MODEL_RESULTS_FILE_NAME="looModelPipelineResults.txt"
set LOO_MODEL_OUTPUT_FILE_NAME="looModelOutputFile.txt"
perl $HOME_BIN_DIR/runModelPipeline.pl --parameterFileName $LOO_PARAMETER_FILE_NAME --pipelineClass BenchmarkerPipeline > & $LOO_MODEL_OUTPUT_FILE_NAME
cp $LOO_MODEL_LOG_FILE_NAME $LOO_MODEL_RESULTS_FILE_NAME $LOO_MODEL_OUTPUT_FILE_NAME $HOME_RUN_DIR

endif



rm -r $NODE_HOME_DIR/


echo "DONE" > ${_SALI_JOB_DIR}/job-state

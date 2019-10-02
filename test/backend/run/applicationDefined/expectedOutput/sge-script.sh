#!/bin/tcsh
#$ -S /bin/tcsh
#$ -cwd
#$  -o output.txt -e error.txt -l scratch=1G -l arch=lx-amd64 -r y -j y  -l mem_free=1G -l h_rt=144:00:00 -p 0 -t 1-1
setenv _SALI_JOB_DIR `pwd`
echo "STARTED" > ${_SALI_JOB_DIR}/job-state


# Set paths to PCSS pipeline scripts
module load Sali
module load pcss

set tasks=( seq_batch_1 )
set input=$tasks[$SGE_TASK_ID]

set HOME_RUN_DIR="/tmp/tmpLrq1rs" 
set HOME_SEQ_BATCH_DIR="$HOME_RUN_DIR/sequenceBatches/$input/"

set NODE_HOME_DIR="/scratch/peptide//$input"
mkdir -p $NODE_HOME_DIR

set PEPTIDE_OUTPUT_FILE_NAME="peptidePipelineOut.txt"
set PARAMETER_FILE_NAME="parameters.txt"

cp $HOME_RUN_DIR/$PARAMETER_FILE_NAME $NODE_HOME_DIR 
cp $HOME_SEQ_BATCH_DIR/inputSequences.fasta $NODE_HOME_DIR

echo -e "\nrun_name\t$input" >>  $NODE_HOME_DIR/$PARAMETER_FILE_NAME     

cd $NODE_HOME_DIR

date
hostname
pwd



cp $HOME_RUN_DIR/peptideRulesFile $NODE_HOME_DIR
runPeptidePipeline.pl --parameterFileName $PARAMETER_FILE_NAME > & $PEPTIDE_OUTPUT_FILE_NAME

set MODEL_OUTPUT_FILE_NAME="modelPipelineOut.txt"
set MODEL_LOG_FILE_NAME="modelPipelineLog"
set MODEL_RESULTS_FILE_NAME="modelPipelineResults.txt"

set PEPTIDE_LOG_FILE_NAME="peptidePipelineLog"
set PEPTIDE_RESULTS_FILE_NAME="peptidePipelineResults.txt"

set SVM_SCORE_FILE_NAME="svmScoreFile"

runModelPipeline.pl --parameterFileName $PARAMETER_FILE_NAME --pipelineClass ApplicationPipeline > & $MODEL_OUTPUT_FILE_NAME

cp  $PEPTIDE_OUTPUT_FILE_NAME $PEPTIDE_LOG_FILE_NAME $PEPTIDE_RESULTS_FILE_NAME $MODEL_OUTPUT_FILE_NAME $MODEL_LOG_FILE_NAME $MODEL_RESULTS_FILE_NAME $SVM_SCORE_FILE_NAME $HOME_SEQ_BATCH_DIR
rm -r $NODE_HOME_DIR/

echo "DONE" > ${_SALI_JOB_DIR}/job-state

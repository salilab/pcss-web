#!/bin/tcsh                            
#                                     
#$ -S /bin/tcsh                       
#$ -cwd                              
#$ -o ./logs                           
#$ -e ./logs                           
#$ -r y                            
#$ -j y                                                         
#$ -l arch=lx24-amd64
#$ -l mem_free=1G
#$ -l netappsali=1G,database=1G,scratch=1G 
#$ -l h_rt=24:00:00                   
#$ -p 0                               
#$ -t 1-1


echo "cluster starting up"

set tasks = ( 72d6308d72a998d9432794ae32578067MEAVPMTR )

set input=$tasks[$SGE_TASK_ID]


set HOME_DIR="/netapp/sali/dbarkan/protease/webserver/WebServer/"

set THREE_LETTER=`echo $input | head -c 3`

set HOME_RUN_DIR="$HOME_DIR/runs/testClusterPipeline/"   # dynamically generated?
set HOME_BIN_DIR="$HOME_DIR/bin/"
set HOME_SEQUENCE_DIR="$HOME_RUN_DIR/$THREE_LETTER/$input/"   #already created

set HOME_LIB_DIR="$HOME_DIR/lib/"

#have fasta sequence, parameters, in the sequence dir itself (could have global parameters but if I have modbase seq id parameterized it will be specific to this sequence)
#have global rules file in pipeline directory

set NODE_HOME_DIR="/scratch/dbarkan/peptide/$input"
set NODE_HOME_BIN_DIR="$NODE_HOME_DIR/bin"
set NODE_HOME_RUN_DIR="$NODE_HOME_DIR/runs"

mkdir -p $NODE_HOME_BIN_DIR
mkdir -p $NODE_HOME_RUN_DIR


cd $NODE_HOME_BIN_DIR

date
hostname
pwd

setenv PERLLIB $HOME_LIB_DIR

set OUTPUT_FILE_NAME="${input}_out.txt"

cp $HOME_SEQUENCE_DIR/peptideParams.txt $NODE_HOME_BIN_DIR
cp $HOME_SEQUENCE_DIR/sequenceFasta.txt $NODE_HOME_BIN_DIR
cp $HOME_RUN_DIR/peptideRules.txt $NODE_HOME_BIN_DIR


perl $HOME_BIN_DIR/runPeptidePipeline.pl --parameterFileName peptideParams.txt > & $OUTPUT_FILE_NAME

cp -r $NODE_HOME_BIN_DIR $HOME_SEQUENCE_DIR


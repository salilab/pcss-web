import unittest
import peptide
import saliweb.test
import sys
import os
import re
import subprocess
import logging
import time

TESTDIR = os.path.abspath(os.path.dirname(__file__))

class JobTests(saliweb.test.TestCase):

    def get_test_directory(self, subdir):
        return os.path.join(TESTDIR, subdir)


    """
    test_preprocess()
    Test that preprocess successfully creates all three modes (application scan, application user defined, training)

    General testing flow:
    1. Each mode has its own directory with input and expected output
    2. Create job object
    3. Copy job input (which is what the frontend has delivered) into the job's run directory
    4. Call job's preprocess() method
    5. Check that all output files were correctly written (splitting input into different files for cluster submission, etc.)
    """
    def test_preprocess(self):

        print "Testing Preprocess Application Scan"
        applicationScanDirectory = self.get_test_directory(
                                      "preprocess/applicationScan/")
        self.runPreprocess(applicationScanDirectory, 3, 102)

        print "Testing Preprocess Application Defined"

        applicationDefinedDirectory = self.get_test_directory(
                                         "preprocess/applicationDefined/")
        self.runPreprocess(applicationDefinedDirectory, 1, 18)

    def runPreprocess(self, preprocessDir, seqBatchCount, totalSeqCount):

        j = self.createPreprocessingJobDirectory()

        #copy input
        inputDirectory = preprocessDir + "/input/"
        files = ["parameters.txt", "inputSequences.fasta"]
        self.copyFiles(inputDirectory, j.directory, files)

        #run preprocess
        j.preprocess()

        #copy output
        expectedOutputDir = preprocessDir + "/expectedOutput"
        files = ["cluster_state", "framework.log", "inputSequences.fasta",  "parameters.txt", "sequenceBatches"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput", files)

        #check results match expected
        self.processSeqBatchAndParams(j, preprocessDir, expectedOutputDir)

        #correct number of sequences and seq batch directories written
        logMessage = "Made %s sequence batch directories for %s sequences" % (seqBatchCount, totalSeqCount)
        self.checkLogMessageWritten(j, logMessage) #stats


    def processSeqBatchAndParams(self, j, jobDirectory, expectedOutputDir):

        seqBatchExpectedOutputDir = expectedOutputDir + "/sequenceBatches"

        dotRegex = re.compile('^\.')
        tildaRegex = re.compile('\~')

        allSeqBatchSeqIds = {}
        inputFastaSeqIds = {}
        self.getSequenceIdsFromFasta(j.directory + "/inputSequences.fasta", inputFastaSeqIds)

        #Go through all sequence batch directories
        prefixDirs = os.listdir(seqBatchExpectedOutputDir)
        for prefixDir in prefixDirs:

            dotFile = dotRegex.search(prefixDir)
            tildaFile = tildaRegex.search(prefixDir)
            if (dotFile or tildaFile):
                continue

            #check fasta file exists
            expectedFastaFile = seqBatchExpectedOutputDir + "/" + prefixDir + "/inputSequences.fasta"
            observedFastaFile = j.directory + "/sequenceBatches/" + prefixDir +  "/inputSequences.fasta"
            fastaSkip = []
            self.compareFiles(observedFastaFile, expectedFastaFile, 0, fastaSkip)
            self.getSequenceIdsFromFasta(observedFastaFile, allSeqBatchSeqIds)

        for inputSeqId in inputFastaSeqIds.keys():
            self.assertTrue(allSeqBatchSeqIds.has_key(inputSeqId), "Sequence " + inputSeqId + " in input fasta but did not get written to any seqBatch directory")

        #check cluster state param file exists
        otherFileSkip = []
        expectedClusterStateFile = expectedOutputDir + "/cluster_state"
        observedClusterStateFile = j.directory + "/cluster_state"
        self.compareFiles(expectedClusterStateFile, observedClusterStateFile, 0, otherFileSkip)

        #check global parameter file matches
        parameterSkip = ["head\_node"]
        expectedParameterFile = expectedOutputDir + "/parameters.txt"
        observedParameterFile = j.directory + "/parameters.txt"
        self.compareFiles(expectedParameterFile, observedParameterFile, 1, parameterSkip)


    """
    General testing flow:
    1. Each mode has its own directory with input and expected output
    2. Create job object
    3. Copy job input (which is what preprocess has delivered) into the job's run directory
    4. Call job's run() method
    5. Check that all output files were correctly written and others were not changed (mostly just check cluster script is accurate)
    """
    def test_run(self):

        print "Testing Run Application Scan"

        applicationScanDirectory = self.get_test_directory(
                                                "run/applicationScan/")
        self.runRunTest(applicationScanDirectory, 3)

        print "Testing Run Application Defined"

        applicationDefinedDirectory = self.get_test_directory(
                                                 "run/applicationDefined/")
        self.runRunTest(applicationDefinedDirectory, 1)

        print "Testing Run Training"
        trainingDirectory= self.get_test_directory("run/training/")
        self.runTrainingRunSvmTest(trainingDirectory, 10)  #test training run in SVM mode (second call to run() over the course of processing a server job)



    def runTrainingRunSvmTest(self, trainingDir, taskCount):
        j = self.createRunningJobDirectory()

        #copy input
        inputDirectory = trainingDir + "/input/"
        files = ["parameters.txt", "inputSequences.fasta", "sequenceBatches", "cluster_state"]
        self.copyFiles(inputDirectory, j.directory, files)

        #read params
        j.readParameters(j.directory + "/parameters.txt")  #need to call this here because run() is not being called in context

        #run()
        r = j.run()

        #write sge script -- this isn't done by run() itself, so do it here
        script = os.path.join(j.directory, 'sge-script.sh')
        fh = open(script, 'w')
        r._write_sge_script(fh)
        fh.close()

        #copy files
        expectedOutputDir = trainingDir + "/expectedOutput/"
        outputFiles = ["sge-script.sh", "framework.log", "leaveOneOutParams.txt"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

        #compare sge script to expected
        sgeTestSkip = ["set\sHOME\_RUN\_DIR"]
        expectedSgeScriptFile = expectedOutputDir + "/sge-script.sh"
        observedSgeScriptFile = j.directory + "/sge-script.sh"
        self.compareFiles(expectedSgeScriptFile, observedSgeScriptFile, 0, sgeTestSkip)

        #Compare dynamically generated parameter file for LeaveOneOutBenchmarker pipeline to expected
        parameterSkip = ["head\_node"]
        expectedLooParamsFile = expectedOutputDir + "/leaveOneOutParams.txt"
        observedLooParamsFile = j.directory + "/leaveOneOutParams.txt"
        self.compareFiles(expectedLooParamsFile, observedLooParamsFile, 1, parameterSkip)

        logMsg = "%s tasks will be run" % taskCount
        self.checkLogMessageWritten(j, logMsg)  #stats



    def runRunTest(self, runDir, taskCount):

        j = self.createRunningJobDirectory()

        #copy input
        inputDirectory = runDir + "/input/"
        files = ["parameters.txt", "inputSequences.fasta", "sequenceBatches", "cluster_state"]
        self.copyFiles(inputDirectory, j.directory, files)

        #read params
        j.readParameters(j.directory + "/parameters.txt")  #need to call this here because run() is not being called in context

        #run()
        r = j.run()

        #write sge script -- this isn't done by run() itself, so do it here
        script = os.path.join(j.directory, 'sge-script.sh')
        fh = open(script, 'w')
        r._write_sge_script(fh)
        fh.close()

        #copy files
        expectedOutputDir = runDir + "/expectedOutput/"
        outputFiles = ["sge-script.sh", "framework.log"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

        #compare sge script to expected
        sgeTestSkip = ["set\sHOME\_RUN\_DIR"]

        expectedSgeScriptFile = expectedOutputDir + "/sge-script.sh"
        observedSgeScriptFile = j.directory + "/sge-script.sh"
        self.compareFiles(expectedSgeScriptFile, observedSgeScriptFile, 0, sgeTestSkip)

        #make sure no other files have changed
        self.processSeqBatchAndParams(j, runDir, expectedOutputDir)

        logMsg = "%s tasks will be run" % taskCount
        self.checkLogMessageWritten(j, logMsg)  #stats


    def test_postprocess(self):


        applicationScanDir = self.get_test_directory(
                                         "postprocess/applicationScan")
        applicationDefinedDir = self.get_test_directory(
                                         "postprocess/applicationDefined")

        trainingDir = self.get_test_directory("postprocess/training")
        trainingFeaturesDir = self.get_test_directory(
                                           "postprocess/trainingFeatures")
        applicationErrorPostprocessDir = self.get_test_directory(
                                           "postprocess/applicationErrors")
        trainingErrorPostprocessDir = self.get_test_directory(
                                           "postprocess/trainingErrors")

        j = self.createRunningJobDirectory()

        self.applicationPostprocessTest(j, trainingFeaturesDir, 424)

        print "Testing training postprocess"
        self.trainingPostprocessTest(j, trainingDir)

        print "Testing error training postprocess"
        self.errorTrainingPostprocessTest(j, trainingErrorPostprocessDir)


        print "Testing Normal Postprocess"
        self.applicationPostprocessTest(j, applicationScanDir, 2014)

        self.applicationPostprocessTest(j, applicationDefinedDir, 22)

        print "Testing Error Postprocess"
        self.errorApplicationPostprocess(applicationErrorPostprocessDir)



    def applicationPostprocessTest(self, j, postprocessDir, peptideCount):

        inputDir = postprocessDir + "/input"
        self.copyPostprocessApplicationInput(inputDir, j)
        j.postprocess()

        expectedOutputDir = postprocessDir + "/expectedOutput"
        outputFiles = ["applicationFinalResults.txt", "framework.log", "user.log"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput", outputFiles)

        expectedResultsFile = expectedOutputDir + "/applicationFinalResults.txt"
        observedResultsFile = j.directory + "/applicationFinalResults.txt"
        print "comparing " + expectedResultsFile + " and " + observedResultsFile
        postprocessSkip = []
        self.compareFiles(expectedResultsFile, observedResultsFile, 1, postprocessSkip)

        logMessage = "peptides processed without errors: %s" % peptideCount #stats
        self.checkLogMessageWritten(j, logMessage)


    def trainingPostprocessTest(self, j, postprocessDir):

        inputDir = postprocessDir + "/input"
        self.copyPostprocessTrainingInput(inputDir, j)
        j.postprocess()


        expectedOutputDir = postprocessDir + "/expectedOutput"
        outputFiles = ["svmTrainingFinalResults.txt", "framework.log", "user.log", "userCreatedSvmModel.txt"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

        self.checkNormalPostprocessCompletion(j, expectedOutputDir)
        self.checkLogMessageWritten(j, "Processed 5 positives and 326 negatives") #stats

    def errorTrainingPostprocessTest(self, j, postprocessDir):

        inputDir = postprocessDir + "/input"
        expectedOutputDir = postprocessDir + "/expectedOutput"

        self.runPostprocessTrainingOutputError(inputDir, expectedOutputDir)
        self.runPostprocessTrainingGlobalError(inputDir, expectedOutputDir)
        self.runPostprocessMissingSvmDirError(inputDir, expectedOutputDir)
        self.runPostprocessTrainingMissingResultFileError(inputDir, expectedOutputDir)

        self.runPostprocessTrainingResultsNotIncremented(inputDir, expectedOutputDir)
        self.runPostprocessTrainingResultsInvalidNegativeRef(inputDir, expectedOutputDir)
        self.runPostprocessTrainingResultsInvalidPositiveRef(inputDir, expectedOutputDir)

        self.runPostprocessMissingLooFile(inputDir, expectedOutputDir)
        self.runPostprocessLooNoContent(inputDir, expectedOutputDir)

        self.runPostprocessMissingUserModel(inputDir, expectedOutputDir)
        self.runPostprocessWrongPeptideCount(inputDir, expectedOutputDir)


    def runPostprocessWrongPeptideCount(self, inputDir, expectedOutputDir):
        print "Testing training error thrown when leave one out result file has no content"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"
        wrongCountFile = "looModelPipelineResultsWrongCount.txt"
        self.copyFiles(inputDir, j.directory, [wrongCountFile])
        self.updateParameters(parameterFile, "loo_model_pipeline_result_file_name", wrongCountFile)
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "training_content_error")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)



    def runPostprocessMissingLooFile(self, inputDir, expectedOutputDir):
        print "Testing training error thrown when leave one out result file not written"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "loo_model_pipeline_result_file_name", "fake")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def runPostprocessLooNoContent(self, inputDir, expectedOutputDir):
        print "Testing training error thrown when leave one out result file has no content"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"
        noContentFile = "looModelPipelineResultsNoContent.txt"
        self.copyFiles(inputDir, j.directory, [noContentFile])
        self.updateParameters(parameterFile, "loo_model_pipeline_result_file_name", noContentFile)
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)


    def runPostprocessMissingUserModel(self, inputDir, expectedOutputDir):
        print "Testing training error thrown when user-created model file not found"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "user_created_svm_model_name", "fake")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)


    def runPostprocessTrainingResultsNotIncremented(self, inputDir, expectedOutputDir):

        print "testing training error thrown when counts in result file are not greater with each successive line"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsNotIncremented.txt")
        self.updateParameters(parameterFile, "iteration_count", "1")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm", "parameters.txt"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)
        self.checkErrorFileWritten(j, "training_content_error")
        self.checkErrorMessageWritten(j)

    def runPostprocessTrainingResultsInvalidNegativeRef(self, inputDir, expectedOutputDir):

        print "testing training error thrown when different number of reference negative counts in result file"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsInvalidNegative.txt")
        self.updateParameters(parameterFile, "iteration_count", "2")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm", "parameters.txt"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)
        self.checkErrorFileWritten(j, "training_content_error")
        self.checkErrorMessageWritten(j)

    def runPostprocessTrainingResultsInvalidPositiveRef(self, inputDir, expectedOutputDir):

        print "testing training error thrown when different number of reference positive counts in result file"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsInvalidPositive.txt")
        self.updateParameters(parameterFile, "iteration_count", "2")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm", "parameters.txt"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)
        self.checkErrorFileWritten(j, "training_content_error")
        self.checkErrorMessageWritten(j)



    def runPostprocessEmptyResultFileError(self, inputDir, expectedOutputDir):

        print "Testing training error thrown when a result file was empty for a sequence batch"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsEmptyFile")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)
        self.checkLogMessageWritten(j, "Sending webserver feature error email")

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def runPostprocessTrainingMissingResultFileError(self, inputDir, expectedOutputDir):

        print "Testing training error thrown when a result file was not written for a sequence batch"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "fake")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def runPostprocessTrainingGlobalError(self, inputDir, expectedOutputDir):

        print "Testing training error thrown when cluster had an internal error, but still returned a result file"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsGlobalError")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "parameters.txt", "svm"]

        self.checkErrorFileWritten(j, "file_missing")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def runPostprocessMissingSvmDirError(self, inputDir, expectedOutputDir):
        print "Testing error thrown when svm directory didn't return from cluster"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "top_level_svm_directory", "fake")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "svm"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)


    def runPostprocessTrainingOutputError(self, inputDir, expectedOutputDir):
        print "Testing training error thrown when cluster had an error writing to a result file, but still returned it"

        j = self.createRunningJobDirectory()
        self.copyPostprocessTrainingInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsOutputError")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log", "parameters.txt", "svm"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

        self.checkErrorFileWritten(j, "output_error")
        self.checkErrorMessageWritten(j)



    def errorApplicationPostprocess(self, postprocessDir):

        inputDir = postprocessDir + "/input"
        expectedOutputDir = postprocessDir + "/expectedOutput"

        #Checks to make sure that cluster global errors all throw exceptions and write error files which are later read by front-end
        #1. Run job
        #2. Job reads modified modelPipelineResultFile which has error keyword
        #3. Job writes error output file and writes to logs
        #4. Test makes sure error output file exists with correct error keyword and generic log message was written
        self.runPostprocessApplicationOutputError(inputDir, expectedOutputDir)
        self.runPostprocessApplicationGlobalError(inputDir,  expectedOutputDir)

        #Checks to make sure that everything returned correctly from cluster. Even if cluster job failed, there should be error message in a file,
        #so these tests examine possible reasons the cluster or framework itself bombed
        #1. Run Job
        #2. Job reads modified file / directory names which are non-existent or empty
        #3. Job writes "cluster_missing_file" error keyword and writes to logs
        #4. Test makes sure error output file exists with correct error keyword and generic log message was written
        self.runPostprocessApplicationMissingSeqBatchError(inputDir,  expectedOutputDir)
        self.runPostprocessApplicationMissingResultFileError(inputDir, expectedOutputDir)
        self.runPostprocessApplicationEmptyResultFileError(inputDir, expectedOutputDir)

        #Checks to make sure everything handled correctly if job finished and processed sequences, but there was a content error.
        #This required reading in a real results file that had a feature error or didn't contain an expected sequence
        #1. Run Job
        #2. Job reads modified results file
        #3. Test makes sure appropriate error log messages were written (in production, the server also sends an email in the same code block as log message)

#        self.runPostprocessApplicationFeatureError(inputDir, expectedOutputDir)
#        self.runPostprocessApplicationMissingSequenceError(inputDir, expectedOutputDir)


    def runPostprocessApplicationMissingSeqBatchError(self,  inputDir, expectedOutputDir):

        print "Testing error thrown when sequence batch directory didn't return from cluster"

        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "seq_batch_directory_prefix", "fake")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def runPostprocessApplicationMissingSequenceError(self, inputDir, expectedOutputDir):

        print "Testing log message written when a sequence wasn't processed"
        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsMissingSeq")
        j.postprocess()

        outputFiles = [ "framework.log", "user.log"]
        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)
        self.checkLogMessageWritten(j, "Didn't find result")
        self.checkLogMessageWritten(j, "Sending missing sequence email")


    def runPostprocessApplicationFeatureError(self,  inputDir, expectedOutputDir):

        print "Testing log message written for a feature error"

        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsDisopredError")
        self.updateParameters(parameterFile, "seq_batch_count", "1")

        j.postprocess()
        outputFiles = ["framework.log", "user.log"]

        self.checkLogMessageWritten(j, "Sending webserver feature error email")

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)


    def runPostprocessApplicationEmptyResultFileError(self, inputDir, expectedOutputDir):

        print "Testing error thrown when a result file was empty for a sequence batch"

        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsEmptyFile")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def runPostprocessApplicationMissingResultFileError(self, inputDir, expectedOutputDir):

        print "Testing error thrown when a result file was not written for a sequence batch"

        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "fake")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log"]

        self.checkErrorFileWritten(j, "cluster_missing_file")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)


    def runPostprocessApplicationGlobalError(self, inputDir, expectedOutputDir):

        print "Testing error thrown when cluster had an internal error, but still returned a result file"

        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsGlobalError")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log"]

        self.checkErrorFileWritten(j, "file_missing")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)


    def runPostprocessApplicationOutputError(self, inputDir, expectedOutputDir):

        print "Testing error thrown when cluster had an error writing to a result file, but still returned it"

        j = self.createRunningJobDirectory()
        self.copyPostprocessApplicationInput(inputDir, j)

        parameterFile = j.directory + "/parameters.txt"

        self.updateParameters(parameterFile, "model_pipeline_result_file_name", "modelPipelineResultsOutputError")
        j.postprocess()

        outputFiles = ["postprocessErrors", "framework.log", "user.log"]

        self.checkErrorFileWritten(j, "output_error")
        self.checkErrorMessageWritten(j)

        self.copyFiles(j.directory, expectedOutputDir + "/observedOutput/", outputFiles)

    def checkErrorMessageWritten(self, j):

        self.checkLogMessageWritten(j, "Writing error output file")

    def checkLogMessageWritten(self, j, msg):

        msgRegex = re.compile(msg)
        foundLogMessage = 0

        logFileName = j.directory + "/framework.log"
        logFh = open(logFileName, "r")
        fileLines = logFh.readlines()
        for line in fileLines:
            if (msgRegex.search(line)):
                foundLogMessage = 1
        self.assertTrue(foundLogMessage == 1, " Log message " + msg + " not written to framework log")


    def checkErrorFileWritten(self, j, errorKeyword):
        errorFileName = j.directory + "/postprocessErrors"
        errorFh = open(errorFileName, "r")
        errorLine = errorFh.readline()
        errorLine = errorLine.rstrip("\n\r")
        self.assertEqual(errorLine, errorKeyword, "Error file with keyword " + errorKeyword + " not written")




    def copyPostprocessTrainingInput(self, inputDir, j):
        #copy input
        files = ["cluster_state",  "inputSequences.fasta",  "parameters.txt", "svm",  "rawUserModelFile", "looModelPipelineResults.txt"]
        self.copyFiles(inputDir, j.directory, files)

    def copyPostprocessApplicationInput(self, inputDir, j):

        #copy input
        files = ["cluster_state",   "inputSequences.fasta",  "parameters.txt",  "sequenceBatches"]
        self.copyFiles(inputDir, j.directory, files)

    def copyFiles(self, sourceDirectory, destinationDirectory, files):
        for file in files:
            fullFile = sourceDirectory + "/" + file

            process = subprocess.Popen(['cp', '-r', fullFile, destinationDirectory], shell=False, stderr=subprocess.PIPE)
            output = process.communicate()
            msg = output[1]
            if (msg != ""):
                print "Error in copying file " + fullFile + ": " + msg

    def checkNormalPostprocessCompletion(self, j, expectedOutputDir):
        expectedResultFile = os.path.join(expectedOutputDir, "svmTrainingFinalResults.txt")
        observedResultFile = os.path.join(j.directory, "svmTrainingFinalResults.txt")

        expectedFh = open(expectedResultFile, "r")
        observedFh = open(observedResultFile, "r")

        expectedLines = self.loadFile(expectedFh.readlines(), [])
        observedLines = self.loadFile(observedFh.readlines(), [])

        observedLineCounter = 0

        #compare each file line by line
        previousFpr = 0
        for expectedLine in expectedLines:
            observedLine = observedLines[observedLineCounter]
            observedLineCounter = observedLineCounter + 1


            expectedLine = expectedLine.rstrip("\n\r")
            observedLine = observedLine.rstrip("\n\r")

            expectedCols = expectedLine.split('\t')
            observedCols = observedLine.split('\t')
            if (len(observedCols) == 4):

                secondCol = observedCols[1]
                if (secondCol == "TPR"):
                    continue
                secondCol.rstrip("\n\r\s")
                self.assertTrue(len(observedCols) == 4)
                self.assertTrue(expectedCols[1] == observedCols[1])
                self.assertTrue(previousFpr <= observedCols[0], "FPR increased over all results")
                previousFpr = observedCols[0]

            else:
                print "did not get expected number of columns in %s" % observedResultFile
                exit



        expectedFh.close()
        observedFh.close()



    def compareFiles(self, firstFile, secondFile, sortFiles, skipList):

        #sort files if necessary (useful for when lines in files have random order, eg parameter files)
        if sortFiles == 1:
            sortedFirstFile = firstFile + "_sorted"
            sortedSecondFile = secondFile + "_sorted"
            sortedFirstFh = open(sortedFirstFile, "w")
            sortedSecondFh = open(sortedSecondFile, "w")
            process = subprocess.Popen(['sort', firstFile], shell=False, stdout=sortedFirstFh)
            process = subprocess.Popen(['sort', secondFile], shell=False, stdout=sortedSecondFh)
            firstFile = sortedFirstFile
            secondFile = sortedSecondFile
            sortedFirstFh.close()
            sortedSecondFh.close()
            time.sleep(1) #if I don't have this, I the subprocess sort command doesn't finish in time to load the file

        firstFh = open(firstFile, "r")
        secondFh = open(secondFile, "r")

        #prepare regex for lines we want to skip (eg lines that might change from run to run)
        skipReList = []
        for skip in skipList:
            skipRe = re.compile(skip)
            skipReList.append(skipRe)

        secondLineCounter = 0

        #load files to be comapred into lists (this strips out blank lines and lines in skipReList)
        allFirstLines = self.loadFile(firstFh.readlines(), skipReList)
        allSecondLines = self.loadFile(secondFh.readlines(), skipReList)

        #check number of lines in each file is the same
        firstLineCount = len(allFirstLines)
        secondLineCount = len(allSecondLines)
        self.assertTrue(firstLineCount == secondLineCount, "Files " + firstFile + " and " + secondFile + " don't have the same number of lines; first: " + str(firstLineCount) + " second: " + str(secondLineCount))

        #compare each file line by line
        for firstLine in allFirstLines:
            secondLine = allSecondLines[secondLineCounter]
            secondLineCounter = secondLineCounter + 1

            self.assertEqual(firstLine, secondLine, "A line in " + firstFile + " and " + secondFile + " mismatched. First line " + firstLine + " second line: " + secondLine)
        firstFh.close()
        secondFh.close()

    def createRunningJobDirectory(self):

        #create job
        j = self.make_test_job(peptide.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)

        #make log
        hdlr = j.get_log_handler()
        j.logger = logging.getLogger("peptide")
        j.logger.addHandler(hdlr)

        return j

    def createPreprocessingJobDirectory(self):
        #create job
        j = self.make_test_job(peptide.Job, 'PREPROCESSING')
        d = saliweb.test.RunInDir(j.directory)

        #make log
        hdlr = j.get_log_handler()
        j.logger = logging.getLogger("peptide")
        j.logger.addHandler(hdlr)

        return j

    def updateParameters(self, parameterFile, newParamName, newParamValue):
        parameterFh = open(parameterFile, "r")
        paramLines = parameterFh.readlines()
        parameterFh.close()
        foundParamName = 0

        parameterFh = open(parameterFile, "w")
        blankRe = re.compile('^\s*$')
        for line in paramLines:
            blankLine = blankRe.search(line)
            if blankLine:
                continue

            line = line.rstrip("\n\r")

            [paramName, paramValue] = line.split('\t')

            if (paramName == newParamName):

                paramValue = newParamValue
                foundParamName = 1
            parameterFh.write(paramName + "\t" + paramValue + "\n")
        if (foundParamName == 0):
            print "did not find parameter name" + newParamName + "to update"
            sys.exit()
        parameterFh.close()

    def getSequenceIdsFromFasta(self, fastaFile, seqDict):
        fastaFh = open(fastaFile)
        headerRe = re.compile('\>(\w+)\|(\w+)')
        blankRe = re.compile('^\s*$')

        for line in fastaFh:

            #next if blank line
            blankLine = blankRe.search(line)
            if blankLine:
                continue
            line.rstrip("\n\r\s")
            header = headerRe.search(line)
            if header:
                #add to dictionary
                modbaseSeqId = str(header.group(1))
                seqDict[modbaseSeqId] = 1


    def loadFile(self, fileLines, skipReList):

        blankRe = re.compile("^\s*$")
        allLines = []
        for line in fileLines:

            #continue past blank lines
            if blankRe.search(line):
                continue

            #see if we match any of the patterns that indicate a line should be skipped
            skipLine = 0
            for skipRe in skipReList:

                foundSkip = skipRe.search(line)
                if foundSkip:
                    skipLine = 1
            if skipLine == 1:
                continue

            allLines.append(line)
        return allLines



if __name__ == '__main__':
    unittest.main()

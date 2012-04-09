import saliweb.backend
import os
import subprocess
import logging
import re
import copy
import math 

class InvalidParamError(Exception):
    """Exception raised for parameter name that was not found in the list of Job's valid parameter names when retrieved, or one that already existed when set"""
    pass

class SubprocessError(Exception):
    """Exception raised for perl subprocess that returned with non-zero error code"""
    pass

class SanityError(Exception):
    def __init__(self, msg):
        self.keyword = "sanity_error"
        self.msg = msg
    """Exception raised if a job fails the sanity check, e.g. if a parameter
      was set to an unexpected value."""
    pass

class TrainingContentError(Exception):
    def __init__(self, msg):
        self.keyword = "training_content_error"
        self.msg = msg
    """Exception raised if a job training result didn't have expected format or content """
    pass

class FeatureMissingError(Exception):
    """Exception raised if a peptide job returned that didn't have all features correctly accounted for."""
    pass

class ClusterJobError(Exception):

    """Exception raised if a cluster node did not return expected output"""
    pass

class ClusterJobOutputError(ClusterJobError):
    def __init__(self, msg):
        self.keyword = "output_error"
        self.msg = msg
    pass

class ClusterJobGlobalError(ClusterJobError):
    def __init__(self, keyword, msg):
        self.keyword = keyword
        self.msg = msg
    pass

class ClusterJobEmptyFileError(ClusterJobError):
    def __init__(self,  msg):
        self.keyword = "cluster_missing_file"
        self.msg = msg
    pass

class Job(saliweb.backend.Job):

    runnercls = saliweb.backend.SGERunner

    def preprocess(self):
        """ Prepare cluster input by partitioning all sequences into separate batches, each of which is processed on its own node"""
        self.logger.setLevel(logging.INFO)

        self.logger.info("Beginning preprocess() for job %s " %self.name)

        #update parameters to include job.directory
        self.readParameters(os.path.join(self.directory, "parameters.txt")) #hardcoded
        parameterFileName = self.getParam("job_parameter_file_name")

        self.setServerMode()

        #tells the perl modules that run on the cluster where they get their data -- will change according to job name
        #frontend could write this but still don't appear to have _##### tag until after frontend submits job
        self.setParam("head_node_preprocess_directory", self.directory)

        #handle custom model parameters
        self.processCustomModel()

        #calculate number of sequence batches to create                                                                        
        [sequenceDict, sequenceIdList, modbaseToAccession] = self.getSequenceDict()
        headerList = sequenceDict.keys()
        seqBatchCount = self.getSeqBatchCount(headerList)
        self.setParam("seq_batch_count", seqBatchCount)

        #overwrite existing parameter file to add new params
        self.writeParameterFile(os.path.join(self.directory, parameterFileName), self.parameters)

        #prepare to create sequence batch directories
        seqBatchList = self.makeSeqBatchList(seqBatchCount)
        seqBatchTopDirectory = self.getParam("seq_batch_top_directory")
        fastaFileName = self.getParam("input_fasta_file_name")
        sequenceCount = len(headerList)
        seqsInBatchCount = int(self.getParam("seqs_in_batch_count"))

        #make one directory per batch. Each gets its own fasta file.
        i = 0

        for seqBatch in seqBatchList:
            
            #make directory
            seqBatchDirectory = os.path.join(self.directory, seqBatchTopDirectory, seqBatch)
            process = subprocess.Popen(['mkdir', '-p', seqBatchDirectory], shell=False, stderr=subprocess.PIPE)
            self.runSubprocess(process)

            #write sequences fasta file
            seqBatchFastaFileName =  os.path.join(seqBatchDirectory, fastaFileName)
            slice = headerList[i:i+seqsInBatchCount]
            fh = open(seqBatchFastaFileName, "w")
            for header in slice:
                fh.write(">%s" %header)
                sequence = sequenceDict[header]
                fh.write(sequence)
            i = i + seqsInBatchCount

        self.logger.info("Done preprocess(). Made %s sequence batch directories for %s sequences " % (seqBatchCount, sequenceCount))
      
        #prepare for first cluster submit (only one cluster job in application mode; first of two in training mode)
        self.setParamState(self.directory, "cluster_state", "FEATURES")
    

    def run(self):
        """Create cluster shell script according to which state the job is in, and submit to cluster"""
        clusterState = self.getParamState(self.directory, "cluster_state")

        self.setServerMode()
        self.logger.info("Beginning run() in server mode %s and cluster state %s" % (self.serverMode, clusterState))
        taskList = []
        script = ""
        
        #get task list that will go into cluster script (will either be list of modbase seq ids or iteration numbers)
        if (clusterState == "FEATURES"):
            seqBatchCount = self.getParam("seq_batch_count")
            taskList = self.makeSeqBatchList(seqBatchCount)
        elif (clusterState == "SVM"):
            taskList = self.getIterationList()
        else:
            raise SanityError("Did not get expected cluster state parameter value of either 'FEATURES' or 'SVM' (value obtained: %s)" %clusterState)
        
        #prepare cluster submit script
        taskCount = len(taskList)
        if (self.serverMode == "training"):
            if (clusterState == "FEATURES"):
                script = self.makeTrainingSgeScript(taskList)
            elif (clusterState == "SVM"):
                self.makeLooParameterFile()
                script = self.makeModelSgeScript(taskList)
            else:
                raise SanityError("Did not get expected cluster state parameter value of either 'FEATURES' or 'SVM' (value obtained: %s)" %clusterState)
        else: #application mode
            
            script = self.makeApplicationSgeScript(taskList)

        #submit script
        r = self.runnercls(script, interpreter='/bin/tcsh')
        r.set_sge_options(" -o output.txt -e error.txt -l netappsali=1G,database=1G,scratch=1G -l arch=lx24-amd64 "
                                                    "-r y -j y  -l mem_free=1G -l h_rt=72:00:00 -p 0 -t 1-%s" % taskCount)
        self.logger.info("Submitting job to cluster; %s tasks will be run" % taskCount)
        return r


    def postprocess(self):
        """Read and validate results of cluster run. In training mode, resubmit if only first run is done; otherwise, create final output file and return"""
        #prepare logging
        self.logger.setLevel(logging.INFO)

        #self.parameters are destroyed over the course of run; reread them 
        self.readParameters(os.path.join(self.directory, "parameters.txt"))

        self.setServerMode()
        
        clusterState = self.getParamState(self.directory, "cluster_state")
        self.logger.info("Beginning postprocess() in server mode %s and cluster state %s" % (self.serverMode, clusterState))
        self.loadUserLog()
        self.userLogger.setLevel(logging.INFO)

        if (clusterState == "FEATURES"):   #first cluster run completed; features have been assigned to peptides

            seqBatchCount = self.getParam("seq_batch_count")
            self.featureErrorEmailSent = 0
            self.missingSequenceEmailSent = 0
            seqBatchList = self.makeSeqBatchList(seqBatchCount)

            try:
                #validate job ran correctly; process results and write to file
                self.checkPeptideJobCompleted(seqBatchList)
                self.processPeptideJob(seqBatchList)
                #self.validateFinalFeatureFiles()
            except ClusterJobError,  e:
                self.handleClusterError(e)
                return

            self.closeUserLog()                
            if (self.serverMode == "training"):
                #prepare to use peptide features to train a new model
                self.setParamState(self.directory, "cluster_state", "SVM")
                self.logger.info("Finished processing peptide features; rescheduling server run to train model")
                testMode = self.getParam("test_mode")
                if (testMode == "no"):
                    self.reschedule_run()
        elif (clusterState == "SVM"):
            try:
                #validate job ran correctly; process results and write to file
                self.checkTrainingJobCompleted()
                self.processSvmResults()
                self.makeUserCreatedModelPackage()
                #self.validateFinalSvmFiles()
            except (ClusterJobError, TrainingContentError), e:
                
                self.handleClusterError(e)
                return
            self.logger.info("Completed training model.  Returning to front-end")
            self.closeUserLog()
        else:
            #close user log?
            raise SanityError("Did not get expected cluster state parameter value of either 'FEATURES' or 'SVM' (value obtained: %s)" %clusterState)

    def makeUserCreatedModelPackage(self):
        separator = self.getParam("user_separator_line")

        #open model package file that's downloaded by user
        finalModelPackageName = self.getParam("user_model_package_name")
        fullModelPackageName = os.path.join(self.directory, finalModelPackageName)
        packageFh = open(fullModelPackageName, 'w')

        #write user model to package file
        userCreatedModelName =  self.getParam("user_created_svm_model_name")
        fullCreatedModelFile = os.path.join(self.directory, userCreatedModelName)
        userModelFh = open(fullCreatedModelFile, 'r')
        for line in userModelFh:
            packageFh.write(line)

        #write line that separates the two
        packageFh.write("%s\n" % separator)

        #write length of peptide sequence
        peptideLength = self.getParam("peptide_length")
        packageFh.write("peptideLength %s\n" % peptideLength)

        #write leave-one-out benchmark results file
        looBenchmarkResults = self.getParam("loo_model_pipeline_result_file_name")
        fullLooResultsFile = os.path.join(self.directory, looBenchmarkResults)
        looResultFh = open(fullLooResultsFile, 'r')
        for line in looResultFh:
            packageFh.write(line)

    def processPeptideJob(self, seqBatchList):
        """
        Read results of cluster job that assigned features to all peptides; validate content and write all results to single output file

        PARAM  seqBatchList: list of relative directory names containing data for all sequence batches
        """
        self.logger.info("Processing peptide job")
        #open output file           
        finalOutputFile = self.getParam("application_final_result_file_name")
        finalOutputFh = open(os.path.join(self.directory, finalOutputFile), "w")

        #print final columns to output file, in order
        [columnInfo, columnDisplayOrder] = self.readColumnInfo()
        columnOrderList = sorted(columnDisplayOrder.keys())
        columnHeaderString = self.makeColumnHeaderString(columnInfo, columnOrderList, columnDisplayOrder)
        finalOutputFh.write(columnHeaderString + "\n")
            
        #process each sequence batch result file; write to final output file
        [sequenceDict, sequenceIdList, modbaseToAccession] = self.getSequenceDict()
        sequencesToResults = {}
        
        for seqBatch in seqBatchList:
            self.processSeqBatchResultFile(seqBatch, finalOutputFh, sequencesToResults, columnInfo, columnDisplayOrder)
        finalOutputFh.close()

        #retrieve and print stats
        resultsMsg = self.logPeptideResultsMsg(sequenceIdList, sequencesToResults, modbaseToAccession)


    def processSeqBatchResultFile(self, seqBatch, finalOutputFh, sequencesToResults, columnInfo, columnDisplayOrder):
        lineCount = 0
        resultDict = {}
        
        #open results file
        seqBatchTopDirectory = self.getParam("seq_batch_top_directory")
        seqBatchDirectory = os.path.join(self.directory, seqBatchTopDirectory, seqBatch)
        resultsFileToCheck = ""

        if (self.serverMode == "training"):
            resultsFileToCheck = self.getParam("peptide_pipeline_result_file_name")
        else: #application
            resultsFileToCheck = self.getParam("model_pipeline_result_file_name")

        resultFh = open(os.path.join(seqBatchDirectory, resultsFileToCheck), "r")
        
        for line in resultFh:

            #process column header
            if lineCount == 0: 
                fileColumnMap = self.makeFileColumnMap(line)
                lineCount = 1
                continue
                    
            #process result line
            resultValues = line.split('\t')

            modbaseSeqId = self.getResultValue("Sequence ID", resultValues, fileColumnMap)

            #initialize sequencesToResults with this sequence if not done already
            if (sequencesToResults.has_key(modbaseSeqId) == 0):
                sequencesToResults[modbaseSeqId] = {}
                sequencesToResults[modbaseSeqId]["count"] = 0
                sequencesToResults[modbaseSeqId]["result"] = 0

            #check if feature error occurred for this peptide. 
            self.checkFeatureError(resultValues, fileColumnMap, sequencesToResults)  

            #map to each value from its column name
            valueCounter = 0
            for resultValue in resultValues:
                columnDisplayName = fileColumnMap[valueCounter]
                resultDict[columnDisplayName] = resultValue
                valueCounter = valueCounter + 1

            resultValueOutputList = []    

            #use column info to get next value
            columnOrderList = sorted(columnDisplayOrder.keys())
            for columnNumber in columnOrderList:
                nextResultValue = self.getSeqBatchResultValue(columnDisplayOrder, columnNumber, columnInfo, resultDict)
                resultValueOutputList.append(nextResultValue)
                
            #add all results for this peptide
            finalResultValueString = "\t".join(resultValueOutputList)
            finalOutputFh.write(finalResultValueString + "\n")
        


    def logPeptideResultsMsg(self, sequenceIdList, sequencesToResults, modbaseToAccession):
        #prepare error and stats reporting
        featureErrorCount = 0; normalSequenceCount = 0;  missingSequenceCount = 0; noPeptidesParsedCount = 0;
        keywordNoClusterError = self.getParam("keyword_no_cluster_errors")
        keywordNoPeptidesParsed = self.getParam("keyword_no_peptides_parsed")

        goodPeptideCount =  0
        
        for sequenceId in sequenceIdList:

            if (sequencesToResults.has_key(sequenceId) == 0):
                seqMsg = "Peptide webserver job %s, Didn't find result for sequence %s" %(self.name, sequenceId)
                accession = modbaseToAccession[sequenceId]
                userMsg = "Accession %s was not processed at all due to an error" % accesssion
                self.userLogger.info(userMsg)
                missingSequenceCount += 1
                    
                self.logger.info(seqMsg)
                    
                if (self.missingSequenceEmailSent == 0):
                    self.logger.info("Sending missing protein sequence email with msg %s" % seqMsg)
                    testMode = self.getParam("test_mode")
                    if (testMode == "no"):
                        self._db.config.send_admin_email("Peptide webserver missing protein sequence in job %s" %self.name, seqMsg)
                    self.missingSequenceEmailSent = 1
            else:
                seqResult = sequencesToResults[sequenceId]["result"]
                seqCount =  sequencesToResults[sequenceId]["count"]
                goodPeptideCount += seqCount
                if (seqResult == keywordNoClusterError):
                    normalSequenceCount += 1
                elif (seqResult == keywordNoPeptidesParsed):
                    noPeptidesParsedCount += 1
                else:
                    featureErrorCount += 1

        featureErrorString = ""
        missingSequenceString = ""
        noPeptidesParsedString = ""
        self.userLogger.info("Completed calculating peptide features")
        self.userLogger.info("Number of peptides processed without errors: %s" % goodPeptideCount)
        if (self.getIsApplicationScanMode()):
            self.userLogger.info("These peptides were parsed from protein sequences using the supplied peptide specifier file pattern")
        self.logger.info("Number of peptides processed without errors: %s" % goodPeptideCount)
        self.userLogger.info("Number of proteins containing these peptides: %s" % normalSequenceCount)

        if (self.getIsApplicationScanMode()):
            self.userLogger.info("Number of proteins not containing any peptides matching the supplied peptide specifier file pattern: %s" % noPeptidesParsedCount)
        
        self.userLogger.info("Number of proteins containing an error in one or more feature calculations: %s" %featureErrorCount)
        if (featureErrorCount > 0):
            self.userLogger.info("Proteins containing these errors are noted in the log file above. The specific error replaces normal output in the feature column in the results file")
            self.userLogger.info("Additionally, an email has been sent to the PCSS server administrator informing them of the problem")            
            
        self.userLogger.info("Number of proteins not processed at all due to errors: %s" %missingSequenceCount)
        if (missingSequenceCount > 0):
            self.userLogger.info("Proteins containing these errors are noted in the log file above.")
            self.userLogger.info("Additionally, an email has been sent to the PCSS server administrator informing them of the problem")


    def getIsApplicationScanMode(self):
        
        if (self.serverMode == "application"):
            specification = self.getParam("application_specification")
            if (specification == "S"):
                return 1
        return 0


    def processCustomModel(self):
        if (self.serverMode == "training"):
            self.logger.info("process custom model, training")
            return
        if (self.getParam("using_custom_model") == "no"):
            self.logger.info("process custom model, not using custom model")
            return
        elif (self.getParam("using_custom_model") == "yes"):
            self.logger.info("process custom model, setting custom model")
            customModelFile = self.getParam("custom_model_file")
            customBenchmarkFile = self.getParam("custom_benchmark_file")
            preprocessDir = self.getParam("head_node_preprocess_directory")

            fullCustomModelFile = os.path.join(preprocessDir, customModelFile)
            fullCustomBenchmarkFile = os.path.join(preprocessDir, customBenchmarkFile)

            self.setParam("benchmark_score_file", fullCustomBenchmarkFile)
            self.setParam("svm_application_model", fullCustomModelFile)
            
        else:
            raise SanityError("Did not get expected using custom model parameter of either 'no' or 'yes' (value obtained: %s)" %self.getParam("using_custom_model"))


    def processSvmResults(self):
        
        [fpsAtEachTp, scoresAtEachTp, referencePositiveCount, referenceNegativeCount, criticalFpRates, criticalTpRates, criticalEvalues] = self.readSvmResultsFiles()

        finalResultFileName = self.getParam("training_final_result_file_name")
        fullResultFileName = os.path.join(self.directory, finalResultFileName) 
        
        resultFileFh = open(fullResultFileName, 'w')
        resultFileFh.write("FPR\tTPR\tScore\tFPR_STDDEV\n")
        resultFileFh.write("0.0\t0.0\tN/A\tN/A\n")

        iterationCount = self.getParam("iteration_count") 
        totalFps = referenceNegativeCount * int(iterationCount)

        allTps = sorted(fpsAtEachTp.keys())
        for tp in allTps:
            fpCountsAtThisTp = fpsAtEachTp[tp]
            scoresAtThisTp = scoresAtEachTp[tp]
            totalFpsAtThisTp = 0

            allFps = []
            for fpCount in fpCountsAtThisTp.keys():
                fpCountValue = fpCountsAtThisTp[fpCount]
                fpCount = fpCount * fpCountValue
                totalFpsAtThisTp = int(fpCount) + totalFpsAtThisTp
                
                fpRate = (fpCount * 1.0) / (referenceNegativeCount * 1.0)
                allFps.append(fpRate)

            fpRateAtThisTp = (totalFpsAtThisTp * 1.0) / (totalFps * 1.0)
            tpRate = (tp * 1.0) / (referencePositiveCount * 1.0)

            fpRateSum = 0
            for fpRate in allFps:
                fpRateSum = fpRateSum + fpRate
            fpRateAverage = (fpRateSum * 1.0) / (len(allFps) * 1.0)
            averageDifferenceSum = 0
            for fpRate in allFps:
                difference = fpRate - fpRateAverage
                squaredDifference = difference * difference
                averageDifferenceSum = averageDifferenceSum + squaredDifference
            averageDifferenceSum = averageDifferenceSum / len(allFps)
            stdDev = math.sqrt(averageDifferenceSum)
            scoreTotal = 0.0
            for score in scoresAtThisTp.keys():
                scoreTotal = scoreTotal + score
            scoreAverage = scoreTotal / (int(iterationCount) * 1.0)
            resultFileFh.write("%s\t%s\t%s\t%s\n" % (fpRateAtThisTp, tpRate, scoreAverage, stdDev))

        resultFileFh.write("1.0\t1.0\tN/A\tN/A\n\n\n")
        self.userLogger.info("Model training completed across %s iterations" % iterationCount)
                              
    def readSvmResultsFiles(self):

        referencePositiveCount = 0
        referenceNegativeCount = 0
        iterationNegativeCount = 0
        fpsAtEachTp = {}
        scoresAtEachTp = {}
        criticalEvalues = []
        criticalFpRates = []
        criticalTpRates = []

        svmResultDir = self.getParam("top_level_svm_directory")
        iterationCount = int(self.getParam("iteration_count"))
        svmResultFileName = self.getParam("model_pipeline_result_file_name")

        for i in range(1, iterationCount + 1):
            fullSvmResultFile = os.path.join(self.directory, svmResultDir, "svm_iteration_" + str(i), svmResultFileName)
            previousTp = 0
            previousFp = 0
            
            svmResultFh = open(fullSvmResultFile, "r")

            tpCounts = []
            fpCounts = []
            lineCounter = 0
            for line in svmResultFh:
                if (lineCounter == 0):
                    lineCounter +=1
                    continue
                columns = line.split('\t')
                columnCount = len(columns)
                if (columnCount == 3):
                    tpCount = int(columns[0])
                    fpCount = int(columns[1])
                    
                    if (lineCounter > 1):
                        self.checkCountsIncremented(fpCount, tpCount, previousFp, previousTp, fullSvmResultFile)

                    lineCounter += 1
                    previousFp = fpCount
                    previousTp = tpCount
                    score = float(columns[2])
                    
                    if fpsAtEachTp.has_key(tpCount):
                        fpsAtThisTp = fpsAtEachTp[tpCount]
                        scoresAtThisTp = scoresAtEachTp[tpCount]
                    else:
                        fpsAtThisTp = {}
                        scoresAtThisTp = {}
                    if (fpsAtThisTp.has_key(fpCount)):
                        fpsAtThisTp[fpCount] += 1
                    else:
                        fpsAtThisTp[fpCount] = 1
                    if (scoresAtThisTp.has_key(score)):
                        scoresAtThisTp[score] += 1
                    else:
                        scoresAtThisTp[score] = 1
                        
                    fpsAtEachTp[tpCount] = fpsAtThisTp
                    scoresAtEachTp[tpCount] = scoresAtThisTp

                    tpCounts.append(tpCount)
                    fpCounts.append(fpCount)
                elif (columnCount == 4):
                    criticalFpRate = float(columns[0])
                    criticalTpRate = float(columns[1])
                    criticalEvalue = float(columns[2])
                    criticalFpRates.append(criticalFpRate)
                    criticalTpRates.append(criticalTpRate)
                    criticalEvalues.append(criticalEvalue)
                    
                    iterationNegativeCount = int(columns[3])  #slightly hacky way of getting total number of negatives, for consistency checks
                else:
                    raise TrainingContentError("Did not get expected number of columns when reading svm training result file %s (expect 2 or 3 columns, got %s" %(fullSvmResultFile, columnCount))
            countSize = len(tpCounts)
            positiveCount = tpCounts[countSize - 1]
            referencePositiveCount = self.checkReferenceTestSetCount(referencePositiveCount, positiveCount, "positive", fullSvmResultFile)
            referenceNegativeCount = self.checkReferenceTestSetCount(referenceNegativeCount, iterationNegativeCount, "negative", fullSvmResultFile)

        self.logger.info("Read svm results. Processed %s positives and %s negatives (reference count, same across all files)" % (referencePositiveCount, referenceNegativeCount))
        return [fpsAtEachTp, scoresAtEachTp, referencePositiveCount, referenceNegativeCount, criticalFpRates, criticalTpRates, criticalEvalues]
       

    def handleClusterError(self, e):
        keyword = e.keyword
        msg = e.msg
        self.logger.info("Writing error output file. Keyword: %s Message:\n%s" % (keyword, msg))
        self.writeErrorOutputFile(self.directory, keyword)
        testMode = self.getParam("test_mode")
        if (testMode == "no"):
            self._db.config.send_admin_email("Global peptide server error for job %s error in job %s with keyword %s" %(self.name, self.name, keyword), msg)
        self.closeUserLog()

        
    def makeColumnHeaderString(self, columnInfo, columnOrderList, columnDisplayOrder):
        columnHeaderOutputList = []
        for columnNumber in columnOrderList:
            #use column number to get column short name, and use that to get display name
            columnShortName = columnDisplayOrder[columnNumber]
            shortColumnInfo = columnInfo[columnShortName]
            columnDisplayName = shortColumnInfo["displayName"]
            
            columnHeaderOutputList.append(columnDisplayName)

        finalColumnHeaderString = "\t".join(columnHeaderOutputList)
        return finalColumnHeaderString

    def makeFileColumnMap(self, columnLine):
        fileColumnMap = {}
        columnDisplayNames = columnLine.split('\t')
        columnCounter = 0 #think it's ok to key on 0
        #read in columns. Can't assume they are the same order and name as what we read earlier; so map order to name
        for columnDisplayName in columnDisplayNames:

            fileColumnMap[columnCounter] = columnDisplayName
            fileColumnMap[columnDisplayName] = columnCounter
            columnCounter = columnCounter + 1
        return fileColumnMap

    def getSeqBatchResultValue(self, columnDisplayOrder, columnNumber, columnInfo, resultDict):
                       
        columnShortName = columnDisplayOrder[columnNumber]
        shortColumnInfo = columnInfo[columnShortName]
        columnDisplayName = shortColumnInfo["displayName"]
        nextResultValue = resultDict[columnDisplayName]
        if (columnShortName == "peptideStartPosition" or columnShortName == "peptideEndPosition"):
            if (nextResultValue != ""):   #account for no_peptides_parsed lines which don't have peptide ranges
                position = int(nextResultValue)
                position += 1 #convert to base-1
                nextResultValue = str(position)
        return nextResultValue


    def writeErrorOutputFile(self, directory, keyword):
        errorFileName = "postprocessErrors"
        errorFile = os.path.join(directory, errorFileName)     #todo - parameterize
        errorFh = open(errorFile, "w")
        errorFh.write(keyword)
        errorFh.close()

    def closeUserLog(self):
        self.logger.info("closing user log")
        self.userHdlr.close()

    def loadUserLog(self):
        logFileName = self.getParam("user_log_file_name")
        fullLogFileName = os.path.join(self.directory, logFileName)

        hdlr = logging.FileHandler(fullLogFileName)
        formatter = logging.Formatter('%(asctime)s: %(message)s')
        formatter.datefmt = '%Y-%m-%d %H:%M:%S'
        hdlr.setFormatter(formatter)

        self.userLogger = logging.getLogger("userLog")
        self.userLogger.addHandler(hdlr)
        self.userHdlr = hdlr


    def getSeqBatchCount(self, headerList):
        """
        Return number of sequence batches that will hold all sequences in the headerList

        Keyword arguments:
        headerList -- list of fasta headers read from sequence input file; one header per sequence

        Return:
        seqBatchCount -- number of sequence batches
        """
        seqsInBatchCount = int(self.getParam("seqs_in_batch_count"))
        sequenceCount = len(headerList)
        seqBatchCount = sequenceCount / seqsInBatchCount
        
        remainder = sequenceCount % seqsInBatchCount

        if remainder != 0:
            seqBatchCount = seqBatchCount + 1
        return seqBatchCount

    def makeSeqBatchList(self, seqBatchCount):
        """
        Get list of directories that will store sequence batches

        Keyword arguments:
        seqBatchcount -- number of sequence batches in the list

        Return:
        directoryList -- list of seq batch directories
        """
        directoryList = []
        seqBatchDirectoryPrefix = self.getParam("seq_batch_directory_prefix")
        for i in range(1, int(seqBatchCount) + 1):
            directory = "%s_%s" %(seqBatchDirectoryPrefix, i)
            directoryList.append(directory)

        return directoryList


    def checkReferenceTestSetCount(self, referenceCount, countToCheck, tag, file):

        if (referenceCount == 0):
            referenceCount = countToCheck
        else:
            if (countToCheck != referenceCount):
                raise TrainingContentError("Did not have consistent number of %s peptides across different svm iterations. File %s had %s compared to the reference count of %s" % (tag, file, countToCheck, referenceCount))
        return referenceCount

    def checkCountsIncremented(self, fpCount, tpCount, previousFp, previousTp, fileName):
        if (previousFp > fpCount):
            raise TrainingContentError("fp count (%s) is less than that in previous line (%s) in file %s" % (fpCount, previousFp, fileName))
        if (tpCount > 0):
            if (previousTp >= tpCount):
                raise TrainingContentError("Did not increment tp count (%s) from previous line (%s) in file %s" % (tpCount, previousTp, fileName))


    def checkFeatureError(self, resultValues, fileColumnMap, sequencesToResults):
        """
        checkFeatureError
        Reads job results for one peptide and checks for errors. If a feature error occurred, sends email to admin and logs it. If no peptides
        were parsed for the sequence, notes this in sequencesToResults. If no errors occurred, increments the number of peptides for which this
        is the case in sequencesToResults

        PARAM  resultValues: tab-separated line representing the results for this peptide (read directly from cluster results file)
        PARAM  fileColumnMap: dictionary containing information about the order of values in the results file (structure described in self.makeFileColumnMap)
        PARAM  sequencesToResults: dictionary tracking results for each protein sequence. Keys are sequenece IDs and values are dictionary, with one key
               set to 'count' and the other to 'result', with the values of those set here
        """

        errorValue = self.getResultValue("Errors", resultValues, fileColumnMap)
        modbaseSeqId = self.getResultValue("Sequence ID", resultValues, fileColumnMap)

        keywordNoClusterError = self.getParam("keyword_no_cluster_errors")
        keywordNoPeptidesParsed = self.getParam("keyword_no_peptides_parsed")

        #check error column. Three possibilities: no errors, feature error, or no peptides were parsed for sequence
        if (errorValue != keywordNoClusterError and errorValue != keywordNoPeptidesParsed):

            #feature error -- send email notifying admin, and log
            uniprotAccession = self.getResultValue("Uniprot Accession", resultValues, fileColumnMap)
            peptideId = self.getResultValue("Peptide Start", resultValues, fileColumnMap)
            msg = "Server Job %s found feature error %s for uniprot %s modbase %s peptide %s"  %(self.name, errorValue, uniprotAccession, modbaseSeqId, peptideId)
            userMsg = "Not all features processed correctly for uniprot accession %s for peptide starting at position %s" %(uniprotAccession, peptideId)
            self.userLogger.info(userMsg)
            self.logger.info(msg)
            if (self.featureErrorEmailSent == 0):  #only send email once, admin will know job had at least one error
                self.logger.info("Sending webserver feature error email")
                testMode = self.getParam("test_mode")
                if (testMode == "no"):
                    self._db.config.send_admin_email("Peptide webserver feature error in job %s " %self.name, msg)
                self.featureErrorEmailSent = 1
                    
        #Write error value to sequencesToResults    
        currentValue = sequencesToResults[modbaseSeqId]["result"]
        if (currentValue == keywordNoClusterError or currentValue == 0):      #only overwrite if we didn't find an error for this sequence already
            
            sequencesToResults[modbaseSeqId]["result"] = errorValue

        #If no error, increment successful peptide count for this sequence
        if (errorValue == keywordNoClusterError):
            sequencesToResults[modbaseSeqId]["count"] += 1

        
    def getResultValue(self, columnName, resultValues, fileColumnMap):
        columnNumber = fileColumnMap[columnName]
        value = resultValues[columnNumber]
        value = value.rstrip("\n\r")
        return value


    def getParamState(self, directory, param):
        fileName = os.path.join(directory, param)
        parameterFh = open(fileName, "r")
        line = parameterFh.readline()
        line = line.rstrip("\n\r")
        parameterFh.close()
        return line

    def setParamState(self, directory, param, state):
        fileName = os.path.join(directory, param)
        parameterFh = open(fileName, "w")
        parameterFh.write(state)
        parameterFh.close()
        

    def setServerMode(self):
        mode = self.getParam("server_mode")
        if (mode != "training" and mode != "application"):
            msg = "Attempting to set serverMode; id not get expected server mode parameter value of either 'training' or 'application' (value obtained: %s)" % mode
            raise SanityError(msg)
        self.serverMode = mode

    def getServerMode(self):
        if (self.serverMode != "training" and self.serverMode != "application"):
            msg = "Attempting to set serverMode; id not get expected server mode parameter value of either 'training' or 'application' (value obtained: %s)" % self.serverMode
            raise SanityError(msg)
        return self.serverMode
            
    def writeParameterFile(self, parameterFileName, parameters):
        """
        writeParameterFile
        Writes the given parameter dictionary to disk
    
        PARAM  parameterFileName: full name of the parameter file to write to (format paramName\tparamValue)
        PARAM  parameters: dictionary where keys are the parameter names and the values are the corresponding parameter values
        """
        parameterFh = open(parameterFileName, 'w')
        for paramName in parameters.keys():
            paramValue = parameters[paramName]
            parameterFh.write("%s\t%s\n" % (paramName, paramValue))

    
    def readParameters(self, parameterFileName):                              
        """
        readParameters
        Reads the parameter file in peparation for loading self.parameters
        
        PARAM  parameterFileName: full name of the parameter file to write to (format paramName\tparamValue)
        PARAM  parameters: dictionary where keys are the parameter names and the values are the corresponding parameter values
        """
        #TODO -- see how to handle IOError exceptions for this and all other files
        parameters = {}
        parameterFh = open(parameterFileName)
        blankRe = re.compile('^\s*$')
        for line in parameterFh:
            
            blankLine = blankRe.search(line)
            if blankLine:
                continue

            line = line.rstrip("\n\r")
            [paramName, paramValue] = line.split('\t')
            parameters[paramName] = paramValue
            
        parameterFh.close()
        self.parameters = parameters

    def getIterationList(self):
        """
        getIterationList
        Creates an array that will be used in the training cluster script to define the task list.  Each entry is 'svm_iteration_#',
        # from 1 to iteration count defined by user input
        """

        iterationList = []
        iterationCount = self.getParam("iteration_count")
        for i in range(1, int(iterationCount) + 1):
            iterationList.append("svm_iteration_" + str(i))
        return iterationList


    def getSequenceDict(self):
        """
        getSequenceDict
        Reads input fasta file and creates dictionary containing header and sequence information

        RETURN sequenceDict: Dictionary where keys are the headers in the fasta file (with leading '>' stripped and
                             the values are strings containing the full residue sequence
        RETURN sequenceList: List of modbase sequence IDs stripped from the headers
        RETURN modbaseToAccession: Dictionary where keys are modbase sequence IDs and values are Accessions for the sequence
        """
        
        fastaFileName = self.getParam("input_fasta_file_name")
        fullFastaFileName =  os.path.join(self.directory, fastaFileName)
 
        #header regex
        headerRe = re.compile('\>(\w+)\|(\w+)')

        #blank line regex
        blankRe = re.compile('^\s*$')
    
        fastaFh = open(fullFastaFileName)
        sequenceDict = {}
        modbaseToAccession = {}
        seqIdList = []
        currentSeqLines = []

        modbaseSeqId = ""
        currentHeaderLine = ""
        for line in fastaFh:

            #next if blank line
            blankLine = blankRe.search(line)
            if blankLine:
                continue
            line.rstrip("\n\r\s")
            header = headerRe.search(line)
            if header:
                #add to dictionary
                if currentHeaderLine != "":  #we are past the first header
                    
                    #add to id list
                    modbaseSeqId = str(header.group(1))
                    accession = str(header.group(2))
                    modbaseToAccession[modbaseSeqId] = accession
                    seqIdList.append(modbaseSeqId)
                    
                    #add to id dictionary
                    finalSequence = "".join(currentSeqLines)
                    sequenceDict[currentHeaderLine] = finalSequence
                    
                    #reset variables
                    currentHeaderLine = line.lstrip('>')
                    currentSeqLines = []
                else:
                    currentHeaderLine = line.lstrip('>')
                    modbaseSeqId = str(header.group(1))
                    accession = str(header.group(2))
                    modbaseToAccession[modbaseSeqId] = accession
                    seqIdList.append(modbaseSeqId)
            else:
                #continue to build sequence
                currentSeqLines.append(line)
        #add the final sequence
        finalSequence = "".join(currentSeqLines)
        sequenceDict[currentHeaderLine] = finalSequence
        fastaFh.close()
        return [sequenceDict, seqIdList, modbaseToAccession]


    def readColumnInfo(self):
        columnInfoFile = self.getParam("column_info_file")
        columnInfoFh = open(columnInfoFile)
        columnInfo = {}

        myMode = ""
        
        if (self.serverMode == "training"):
            myMode = "trainingDisplay"
        else: #application
            myMode = "applicationDisplay"


        modeRe = re.compile(myMode)

        counter = 1
        columnDisplayOrder = {}
        for line in columnInfoFh:
            line = line.rstrip("\n\r")
            [displayName, shortName, mode, method, description] = line.split('\t')
            if (modeRe.search(mode)):

                singleColumnInfo = {}
                singleColumnInfo["displayName"] = displayName
                singleColumnInfo["mode"] = mode
                singleColumnInfo["method"] = method
                singleColumnInfo["displayOrder"] = counter
                columnDisplayOrder[counter] = shortName
                counter = counter + 1
                
                columnInfo[shortName] = singleColumnInfo

        columnInfoFh.close()
        return [columnInfo, columnDisplayOrder]


    def checkPeptideJobCompleted(self, seqBatchList):
        """
        checkPeptideJobCompleted
        Coordinates making sure jobs run on the cluster that assessed peptide features or application-mode svm scores finished correctly

        PARAM  seqBatchList: List of directories containing divided sequence batches
        RAISE  anything that checkAllClusterFiles finds
        """

        #Determine which result file we are validating
        resultFileToCheck = ""
        if (self.serverMode == "training"):
            resultFileToCheck = self.getParam("peptide_pipeline_result_file_name")  #check intermediate peptide assessment pipeline worked
        else: #application
            resultFileToCheck = self.getParam("model_pipeline_result_file_name")    #assume intermediate assessment worked; just go to model file


        
        [sequenceDict, sequenceList, modbaseToAccession] = self.getSequenceDict()
        seqBatchTopDir = self.getParam("seq_batch_top_directory")

        for seqBatchName in seqBatchList:

            #check all files are accounted for in directory
            fullSeqBatchDir = os.path.join(self.directory, seqBatchTopDir, seqBatchName)
            self.checkAllClusterFiles(fullSeqBatchDir, resultFileToCheck)




    def checkAllClusterFiles(self, resultDirectory, resultFile):
        """
        checkAllClusterFiles
        Checks a result file returned by the cluster to make sure no errors occurred.

        PARAM  resultDirectory: Directory containing the result file
        PARAM  resultFile: name of the result file to check

        RAISE  ClusterJobEmptyFileError if the directory or file is missing or empty
        RAISE  ClusterJobOutputError if the result file indicates the job had trouble writing output
        RAISE  ClusterJobGlobalError if the result file indicates the job encountered a serious, non-recoverable error
        """
        #Check directory exists
        if (os.path.exists(resultDirectory) == 0):
            raise ClusterJobEmptyFileError("Did not find expected peptide pipeline results directory after finishing cluster job (searched for %s)" %resultDirectory)

        #check result file is there
        fullResultFile = os.path.join(resultDirectory, resultFile)
        if (os.path.exists(fullResultFile) == 0):
            raise ClusterJobEmptyFileError("Did not find expected peptide pipeline results file after finishing cluster job (searched for %s)" %fullResultFile)

        #Read results files for errors that may have occurred while running the job
        resultFh = open(fullResultFile, "r")
        lineCount = 0
        lineContentRe = re.compile('\S')

        #todo -- parameterize
        lineOutputError = re.compile('output_error')
        lineGlobalError = re.compile('file_missing|internal_error|invalid_model|invalid_residue|output_error|infinite_sampling_loop|invalid_benchmark_ratio')
        
        foundContent = 0
        for line in resultFh:

            line = line.rstrip("\n\r\s")

            #make sure file is non-empty
            lineNonEmpty = lineContentRe.search(line)
            if lineNonEmpty:
                foundContent = 1

            #check for error job may have had in writing output
            outputError = lineOutputError.search(line)
            if outputError:
                raise ClusterJobOutputError("Cluster output file %s resulted in output error" %fullResultFile)

            #check for error job might have had that required it to bail out (i.e. file missing)
            globalError = lineGlobalError.search(line)
            if globalError:
                raise ClusterJobGlobalError(line, "Cluster output file %s resulted in global error" %fullResultFile)

        if (foundContent == 0):
            raise ClusterJobEmptyFileError("Cluster output file %s did not have any content" %fullResultFile)
    
        resultFh.close()
                                    

    def checkTrainingJobCompleted(self):
        #check to make sure all benchmarking jobs completed successfully (produced non-empty output)
        iterationList = self.getIterationList()
        topLevelSvmDir = self.getParam("top_level_svm_directory")
        resultFile = self.getParam("model_pipeline_result_file_name")
        for iteration in iterationList:
            fullSvmDir = os.path.join(self.directory, topLevelSvmDir, iteration)

            self.checkAllClusterFiles(fullSvmDir, resultFile)

        #leave one out benchmarker results file exists
        looBenchmarkResults = self.getParam("loo_model_pipeline_result_file_name")
        fullLooResultsFile = os.path.join(self.directory, looBenchmarkResults)
        if (os.path.exists(fullLooResultsFile) == 0):

            raise ClusterJobEmptyFileError("Did not LeaveOneOutBenchmarker results file finishing cluster job (searched for %s)" % fullLooResultsFile)

        #benchmark results file is not empty
        looResultFh = open(fullLooResultsFile, 'r')
        totalPeptides = -1
        foundContent = 0
        for line in looResultFh:

            resultValues = line.split('\t')
            resultCount = len(resultValues)
            if (len(resultValues) == 6):
                totalPeptides = int(resultValues[4]) + int(resultValues[5])  #get peptide count for validating SVM model below
                foundContent = 1
        if (foundContent == 0):
            raise ClusterJobEmptyFileError("LeaveOneOut benchmark results file %s did not have any content" %fullLooResultsFile)

                
        #user created svm model
        userCreatedModelName =  self.getParam("user_created_svm_model_name")
        fullCreatedModelFile = os.path.join(self.directory, userCreatedModelName)
        if (os.path.exists(fullCreatedModelFile) == 0):
            raise ClusterJobEmptyFileError("Did not get user created model after finishing cluster job (searched for %s)" %fullCreatedModelFile)

        #make sure number of peptides reported by SVM software is the same number as in our benchmark set
        trainingPeptidesFound = -2
        trainingRe = re.compile('^(\d+).*number of training documents')
        userModelFh = open(fullCreatedModelFile, 'r')
        for line in userModelFh:
            foundTrainingPeptide = trainingRe.search(line)
            if (foundTrainingPeptide):

                trainingPeptidesFound = int(foundTrainingPeptide.group(1))

        if (trainingPeptidesFound != totalPeptides):
            raise TrainingContentError("User created model is trained on %s peptides but LeaveOneOut benchmark results indicate %s peptides were used in the dataset" % (trainingPeptidesFound,
                                                                                                                                                                         totalPeptides))
        
       
    def getParam(self, paramName):
        """
        getParam
        Gets the value for the given parameter name
        
        PARAM  paramName: name of the parameter to search for
        RAISE  InvalidParamError if the parameter is not in self.parameters
        RETURN value for paramName
        """
        try:
            paramValue = self.parameters[paramName]
            return paramValue
        except KeyError:
            errorString = "Backend tried to retrieve value for parameter %s but this is not a valid parameter.  Valid Parameters:\n--" % paramName
            errorString += "\n--".join(self.parameters.keys())
            raise InvalidParamError(errorString)

    def setParam(self, paramName, paramValue):
        """
        setParam
        Sets the value in self.parameters for the given param name
        
        PARAM  paramName: name of the parameter to set
        PARAM  paramValue: value to set paramName to in self.parameters
        RAISE  InvalidParamError if this parameter is already set
        """
        try:
            self.parameters[paramName] = paramValue
        except KeyError:
            existingParamValue = self.parameters[paramName]
            errorString = "Error: tried to set parameter %s but this parameter already had an existing value: %s" % (paramName, existingParamValue)
            raise InvalidParamError(errorString)


    def runSubprocess(self, process):
        """
        runSubprocess
        Executes system call

        PARAM  process:  process object returned by subprocess.Popen method
        RAISE  SubprocessError if there is a non-zero exit code
        """
        processOutput = process.communicate()
        returnCode = process.returncode
        if (returnCode != 0):
            outputString = "Backend ran subprocess which returned with non-zero error code %s and output:\n\n %s" %(returnCode, processOutput)
            raise SubprocessError(outputString)




    def makeBaseSgeScript(self, taskList):
        jobDirectory = self.directory
        netappBinDirectory = self.getParam("netapp_bin_directory")
        netappLibDirectory = self.getParam("perl_lib_directory")
        topLevelSeqBatchDir = self.getParam("seq_batch_top_directory")
        parameterFileName = self.getParam("job_parameter_file_name")
        inputFileName = self.getParam("input_fasta_file_name")
        outputFileName = self.getParam("peptide_pipeline_output_file")
        nodeHomeDirectory = self.getParam("cluster_pipeline_directory")

        taskListString = " ".join(taskList)

        script = """

set HOME_BIN_DIR="%(netappBinDirectory)s"
set HOME_LIB_DIR="%(netappLibDirectory)s"

set tasks=( %(taskListString)s )
set input=$tasks[$SGE_TASK_ID]

set HOME_RUN_DIR="%(jobDirectory)s" 
set HOME_SEQ_BATCH_DIR="$HOME_RUN_DIR/%(topLevelSeqBatchDir)s/$input/"

set NODE_HOME_DIR="%(nodeHomeDirectory)s/$input"
mkdir -p $NODE_HOME_DIR

set PEPTIDE_OUTPUT_FILE_NAME="%(outputFileName)s"
set PARAMETER_FILE_NAME="%(parameterFileName)s"

cp $HOME_RUN_DIR/$PARAMETER_FILE_NAME $NODE_HOME_DIR 
cp $HOME_SEQ_BATCH_DIR/%(inputFileName)s $NODE_HOME_DIR

echo -e "\\nrun_name\\t$input" >>  $NODE_HOME_DIR/$PARAMETER_FILE_NAME     

cd $NODE_HOME_DIR

date
hostname
pwd

setenv PERLLIB $HOME_LIB_DIR

""" %locals()
        return script
    
    def makeTrainingSgeScript(self, taskList):
        peptidePipelineScriptName = self.getParam("peptide_pipeline_script_name")
        baseScript = self.makeBaseSgeScript(taskList)

        peptideLogFileName = self.getParam("peptide_pipeline_log_name")
        peptideResultsFileName = self.getParam("peptide_pipeline_result_file_name")

 
        baseScript += """
perl $HOME_BIN_DIR/%(peptidePipelineScriptName)s --parameterFileName $PARAMETER_FILE_NAME > & $PEPTIDE_OUTPUT_FILE_NAME

set PEPTIDE_LOG_FILE_NAME="%(peptideLogFileName)s"
set PEPTIDE_RESULTS_FILE_NAME="%(peptideResultsFileName)s"

cp  $PEPTIDE_OUTPUT_FILE_NAME $PEPTIDE_LOG_FILE_NAME $PEPTIDE_RESULTS_FILE_NAME  $HOME_SEQ_BATCH_DIR
rm -r $NODE_HOME_DIR/

""" %locals()
        return baseScript

    def makeApplicationSgeScript(self, taskList):      
        #script input
        peptidePipelineScriptName = self.getParam("peptide_pipeline_script_name")
        modelPipelineScriptName = self.getParam("model_pipeline_script_name")
        applicationClassName = self.getParam("application_class_name")
        rulesFileName = self.getParam("rules_file_name")
        
        #things to copy back
        modelResultsFileName = self.getParam("model_pipeline_result_file_name")
        modelLogFileName = self.getParam("model_pipeline_log_name")
        modelOutputFileName = self.getParam("model_pipeline_output_file")

        peptideLogFileName = self.getParam("peptide_pipeline_log_name")
        peptideResultsFileName = self.getParam("peptide_pipeline_result_file_name")

        svmScoreFileName = self.getParam("svm_score_file_name")
        
        baseScript = self.makeBaseSgeScript(taskList)
        baseScript += """

cp $HOME_RUN_DIR/%(rulesFileName)s $NODE_HOME_DIR
perl $HOME_BIN_DIR/%(peptidePipelineScriptName)s --parameterFileName $PARAMETER_FILE_NAME > & $PEPTIDE_OUTPUT_FILE_NAME

set MODEL_OUTPUT_FILE_NAME="%(modelOutputFileName)s"
set MODEL_LOG_FILE_NAME="%(modelLogFileName)s"
set MODEL_RESULTS_FILE_NAME="%(modelResultsFileName)s"

set PEPTIDE_LOG_FILE_NAME="%(peptideLogFileName)s"
set PEPTIDE_RESULTS_FILE_NAME="%(peptideResultsFileName)s"

set SVM_SCORE_FILE_NAME="%(svmScoreFileName)s"

perl $HOME_BIN_DIR/%(modelPipelineScriptName)s --parameterFileName $PARAMETER_FILE_NAME --pipelineClass %(applicationClassName)s > & $MODEL_OUTPUT_FILE_NAME

cp  $PEPTIDE_OUTPUT_FILE_NAME $PEPTIDE_LOG_FILE_NAME $PEPTIDE_RESULTS_FILE_NAME $MODEL_OUTPUT_FILE_NAME $MODEL_LOG_FILE_NAME $MODEL_RESULTS_FILE_NAME $SVM_SCORE_FILE_NAME $HOME_SEQ_BATCH_DIR
rm -r $NODE_HOME_DIR/
""" %locals()
        return baseScript

    def makeLooParameterFile(self):
        
        looParameterFileName = self.getParam("loo_parameter_file_name")
        looFh = open(os.path.join(self.directory, looParameterFileName), "w")
        
        for paramName in self.parameters.keys():
            paramValue = self.parameters[paramName]
            if (paramName == "benchmark_class"):
                paramValue = "LeaveOneOut"
            if (paramName == "model_pipeline_log_name"): 
                paramValue = self.getParam("loo_model_pipeline_log_name")
            if (paramName == "model_pipeline_result_file_name"):
                paramValue  = self.getParam("loo_model_pipeline_result_file_name")
            looFh.write("%s\t%s\n" % (paramName, paramValue))


    def makeModelSgeScript(self, taskList):
        jobDirectory = self.directory
        netappBinDirectory = self.getParam("netapp_bin_directory")
        netappLibDirectory = self.getParam("perl_lib_directory")
        topLevelSvmDir = self.getParam("top_level_svm_directory")
        parameterFileName = self.getParam("job_parameter_file_name")
        inputFileName = self.getParam("input_fasta_file_name")
        nodeHomeDirectory = self.getParam("cluster_pipeline_directory")
        modelOutputFileName = self.getParam("model_pipeline_output_file")
        taskListString = " ".join(taskList)
        modelPipelineScriptName = self.getParam("model_pipeline_script_name")
        benchmarkerClassName = self.getParam("benchmarker_class_name")


        modelResultsFileName = self.getParam("model_pipeline_result_file_name")
        modelLogFileName = self.getParam("model_pipeline_log_name")

        creationClassName = self.getParam("creation_class_name")
        creationOutputFileName = self.getParam("creation_pipeline_output_file")
        creationUserModelName =  self.getParam("user_created_svm_model_name");

        looModelLogFileName = self.getParam("loo_model_pipeline_log_name")
        looModelResultsFileName = self.getParam("loo_model_pipeline_result_file_name")
        looModelOutputFileName = "looModelOutputFile.txt"
        looParameterFileName = self.getParam("loo_parameter_file_name")
        script = """

set HOME_BIN_DIR="%(netappBinDirectory)s"
set HOME_LIB_DIR="%(netappLibDirectory)s"

set HOME_RUN_DIR="%(jobDirectory)s" 

set tasks=( %(taskListString)s )
set input=$tasks[$SGE_TASK_ID]

set HOME_RESULTS_DIR="$HOME_RUN_DIR/%(topLevelSvmDir)s/$input"
mkdir -p $HOME_RESULTS_DIR

set NODE_HOME_DIR="%(nodeHomeDirectory)s/$input"
mkdir -p $NODE_HOME_DIR

set MODEL_OUTPUT_FILE_NAME="%(modelOutputFileName)s"
set MODEL_RESULTS_FILE_NAME="%(modelResultsFileName)s"
set MODEL_LOG_FILE_NAME="%(modelLogFileName)s"

set PARAMETER_FILE_NAME="%(parameterFileName)s"
cp $HOME_RUN_DIR/$PARAMETER_FILE_NAME $NODE_HOME_DIR
cp $HOME_RUN_DIR/%(inputFileName)s $NODE_HOME_DIR

echo -e "\\nrun_name\\t$input" >>  $NODE_HOME_DIR/$PARAMETER_FILE_NAME     

cd $NODE_HOME_DIR
date
hostname
pwd

setenv PERLLIB $HOME_LIB_DIR

perl $HOME_BIN_DIR/%(modelPipelineScriptName)s --parameterFileName $PARAMETER_FILE_NAME --pipelineClass %(benchmarkerClassName)s > & $MODEL_OUTPUT_FILE_NAME

cp  $MODEL_OUTPUT_FILE_NAME  $MODEL_LOG_FILE_NAME $MODEL_RESULTS_FILE_NAME $HOME_RESULTS_DIR

if ($input == svm_iteration_1) then
set CREATION_OUTPUT_FILE_NAME="%(creationOutputFileName)s"


echo "svm iteration 1"
echo %(creationClassName)s
perl $HOME_BIN_DIR/%(modelPipelineScriptName)s --parameterFileName $PARAMETER_FILE_NAME --pipelineClass %(creationClassName)s > & $CREATION_OUTPUT_FILE_NAME  
cp %(creationUserModelName)s $HOME_RUN_DIR
cp $CREATION_OUTPUT_FILE_NAME $HOME_RUN_DIR

set LOO_PARAMETER_FILE_NAME="%(looParameterFileName)s"
cp $HOME_RUN_DIR/$LOO_PARAMETER_FILE_NAME $NODE_HOME_DIR
echo -e "\\nrun_name\\t$input" >>  $NODE_HOME_DIR/$LOO_PARAMETER_FILE_NAME     
set LOO_MODEL_LOG_FILE_NAME="%(looModelLogFileName)s"
set LOO_MODEL_RESULTS_FILE_NAME="%(looModelResultsFileName)s"
set LOO_MODEL_OUTPUT_FILE_NAME="%(looModelOutputFileName)s"
perl $HOME_BIN_DIR/%(modelPipelineScriptName)s --parameterFileName $LOO_PARAMETER_FILE_NAME --pipelineClass %(benchmarkerClassName)s > & $LOO_MODEL_OUTPUT_FILE_NAME
cp $LOO_MODEL_LOG_FILE_NAME $LOO_MODEL_RESULTS_FILE_NAME $LOO_MODEL_OUTPUT_FILE_NAME $HOME_RUN_DIR

endif



rm -r $NODE_HOME_DIR/

""" %locals()
        return script



def get_web_service(config_file):
    db = saliweb.backend.Database(Job)
    config = saliweb.backend.Config(config_file)
    return saliweb.backend.WebService(config, db)


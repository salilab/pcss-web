import saliweb.build

vars = Variables('config.py')
env = saliweb.build.Environment(vars, ['conf/live.conf', 'conf/test.conf'], service_module='peptide')
Help(vars.GenerateHelpText(env))

env.InstallAdminTools()
env.InstallCGIScripts()


Export('env')
SConscript('python/peptide/SConscript')
SConscript('lib/SConscript')
SConscript('txt/SConscript')
SConscript('html/SConscript')

#SConscript('test/frontend/SConscript')
#SConscript('test/svmApplication/SConscript')
#SConscript('test/pipeline/SConscript')
#SConscript('test/svmTraining/SConscript')
SConscript('test/backend/SConscript')


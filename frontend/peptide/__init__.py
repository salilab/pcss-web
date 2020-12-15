from flask import render_template, request, send_from_directory
import saliweb.frontend
from saliweb.frontend import get_completed_job, Parameter, FileParameter
from .param import ParameterFile
from .results import ResultFile
from . import submit
import os

parameters = []
app = saliweb.frontend.make_application(__name__, parameters)


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/help')
def help():
    return render_template('help.html')


@app.route('/contact')
def contact():
    return render_template('contact.html')


@app.route('/job', methods=['GET', 'POST'])
def job():
    if request.method == 'GET':
        return saliweb.frontend.render_queue_page()
    else:
        return submit.handle_new_job()


@app.route('/results.cgi/<name>')  # compatibility with old perl-CGI scripts
@app.route('/job/<name>')
def results(name):
    job = get_completed_job(name, request.args.get('passwd'))
    params = ParameterFile.read(job.get_path('parameters.txt'))
    log_file = ResultFile(job, params['user_log_file_name'])
    mismatch_file = ResultFile(job, params['mismatch_file_name'])
    server_mode = params['server_mode']
    if server_mode == 'training':
        results_file = ResultFile(job,
                                  params['training_final_result_file_name'])
        model_file = ResultFile(job, params['user_model_package_name'])
        return saliweb.frontend.render_results_template(
                    "results_training.html", job=job,
                    results_file=results_file, model_file=model_file,
                    log_file=log_file, mismatch_file=mismatch_file)
    elif server_mode == 'application':
        results_file = ResultFile(job,
                                  params['application_final_result_file_name'])
        return saliweb.frontend.render_results_template(
                    "results_application.html", job=job,
                    results_file=results_file,
                    log_file=log_file, mismatch_file=mismatch_file)


@app.route('/job/<name>/<path:fp>')
def results_file(name, fp):
    job = get_completed_job(name, request.args.get('passwd'))
    return send_from_directory(job.directory, fp)

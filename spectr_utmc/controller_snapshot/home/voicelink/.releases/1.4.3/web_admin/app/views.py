# -*- coding: utf-8 -*-

import shutil
import re
import os
import time
import struct
import subprocess
import random
import string
import io
import zipfile
from Crypto.Cipher import DES
from io import BytesIO
from xmlrpclib import Binary
from datetime import datetime
from flask import render_template, flash, redirect, \
    session, url_for, request, g, abort, make_response, \
    Markup, jsonify, Response, send_file, after_this_request,\
    stream_with_context
try:
    from flask_login import login_user, logout_user, \
        current_user, login_required, user_logged_out
    from flask_babel import gettext
except ImportError:
    from flask.ext.login import login_user, logout_user, \
        current_user, login_required, user_logged_out
    from flask.ext.babel import gettext

from werkzeug.utils import secure_filename
from app import app, babel, limiter, db, lm
from forms import LoginForm, DetectorsForm, NetworkForm, SecurityForm, DatetimeForm
from models import User, Camera, ROLE_GUEST, ROLE_OPERATOR, ROLE_ADMIN
from engine import rtcapi
from engine import address
from engine import my_threading as threading
from config import LANGUAGES, LANGUAGE_DIR, UPLOAD_FOLDER,\
    ALLOWED_EXTENSIONS, MAX_SESSIONS_COUNT, UPDATE_FOLDER,\
    FIRMWARE_FILE, UUID, MAGIC, ALLOWED_FIRMWARE_EXTENSIONS
from utils import get_file_content, read_hash_from_file,\
    make_hash, FullVersion, encrypt_file, check_version
from semantic_version import Version


MAIN_PATH = '/home/voicelink/rtc/resident'
PASSWORD = 'z95mImh0'
SERVICE_PATH = '/home/voicelink/.service'
TIMERS_FOR_CAMERAS = {}
MAX_AMOUNT_FRAMES_ONE_CAMERA = 4
MAX_AMOUNT_CAMERAS = 32
LIST_NUM_DETECTORS_FOR_CAMERAS = dict(map(None, range(1,MAX_AMOUNT_CAMERAS+1), [[200+ii+(MAX_AMOUNT_FRAMES_ONE_CAMERA*i) for ii in range(1,MAX_AMOUNT_FRAMES_ONE_CAMERA+1)] for i in range(MAX_AMOUNT_CAMERAS)]))
##{1: [201, 202, 203, 204], 2: [205, 206, 207, 208], 3: [209, 210, 211, 212], ... , 31: [321, 322, 323, 324], 32: [325, 326, 327, 328]}

MAX_AMOUNT_FRAMES_ONE_CAMERA_TRAFICAM = 16
MAX_AMOUNT_CAMERAS_TRAFICAM = 32
LIST_NUM_DETECTORS_FOR_CAMERAS_TRAFICAM = dict(map(None, range(1,MAX_AMOUNT_CAMERAS_TRAFICAM+1), [[400+ii+(MAX_AMOUNT_FRAMES_ONE_CAMERA_TRAFICAM*i) for ii in range(1,MAX_AMOUNT_FRAMES_ONE_CAMERA_TRAFICAM+1)] for i in range(MAX_AMOUNT_CAMERAS_TRAFICAM)]))
##{1: [401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416], 2: [417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432], ... , 31: [881, 882, 883, 884, 885, 886, 887, 888, 889, 890, 891, 892, 893, 894, 895, 896], 32: [897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912]}

MAX_AMOUNT_FRAMES_ONE_CAMERA_TRAFFIXTREAM2 = 10
MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2 = 32
LIST_NUM_DETECTORS_FOR_CAMERAS_TRAFFIXTREAM2 = dict(map(None, range(1,MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2+1), [[960+ii+(MAX_AMOUNT_FRAMES_ONE_CAMERA_TRAFFIXTREAM2*i) for ii in range(1,MAX_AMOUNT_FRAMES_ONE_CAMERA_TRAFFIXTREAM2+1)] for i in range(MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2)]))
##{1: [961, 962, 963, 964, 965, 966, 967, 968, 969, 970], 2: [971, 972, 973, 974, 975, 976, 977, 978, 979, 980], ... , 31: [1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270], 32: [1271, 1272, 1273, 1274, 1275, 1276, 1277, 1278, 1279, 1280]}

whence_min, whence_max = 0, 0
ip_addr = None
lifetime_timer = None
user_list = set()
updating = None

@babel.localeselector
def get_locale():
    ##return request.accept_languages.best_match(LANGUAGES.keys())
    lng = 'ru'
    if os.path.exists(LANGUAGE_DIR):
        with open(LANGUAGE_DIR, 'r') as f:
            lng = f.read()
    else:
        with open(LANGUAGE_DIR, 'w') as f:
            f.write(lng)
    
    return lng

#----------------------------------------------------------------------
@lm.user_loader
def load_user(id):
    return User.query.get(int(id))

#----------------------------------------------------------------------
@app.before_request
def before_request():
    #if request.url.startswith('http://'):
    #    url = request.url.replace('http://', 'https://', 1).replace('080', '443', 1)
    #    code = 301
    #    return redirect(url, code=code)
    g.user = current_user
    #session.permanent = True
    g.locale = get_locale()
    g.languages = LANGUAGES.keys()


def id_generator(length):
    return ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(length))

#----------------------------------------------------------------------
@app.route('/login', methods = ['GET', 'POST'])
def login():
    global ip_addr
    global user_list
    
    if g.user is not None and g.user.is_authenticated:
        return redirect(url_for('index'))
    
    form = LoginForm()
    if ip_addr is None and len(user_list) < MAX_SESSIONS_COUNT:
        if form.validate_on_submit():
            session['remember_me'] = form.remember_me.data
            #flash(u'login={0}; passwd={1}; remember_me={2};'.format(str(form.login.data), str(form.password.data), str(form.remember_me.data)))
            user = User.query.filter_by(login = str(form.login.data).strip()).first()
            if user:
                if user.passwd == form.password.data.strip():
                    login_user(user, remember=form.remember_me.data)
                    session.permanent = True
                    ##ip_addr = request.remote_addr#спецдыр перехотел сделать ограничение на вход
                    response = make_response(redirect(url_for('index', _external=True)))
                    session_id = id_generator(8)
                    user_list.add(session_id)
                    response.set_cookie('session_id', session_id)
                    return response
                else:
                    form.login.errors.append(gettext('Invalid login or password!'))
            else:
                form.login.errors.append(gettext('Invalid login or password!'))
    else:
        flash(gettext('Maximum number of sessions achieved.'), category='danger')
    
    return render_template('login.html', 
        title = gettext('Authorization'),
        form = form)

#----------------------------------------------------------------------
@app.route("/logout")
@login_required
def logout():
    global user_list
    session_id = request.cookies.get('session_id', '')
    user_list.discard(session_id)

    logout_user()
    return redirect(url_for('login'))


@user_logged_out.connect_via(app)
def on_user_logged_out(sender, user, **extra):
    global ip_addr
    ip_addr = None
    #flash("user_logged_out", category='info')
    return redirect(url_for('login'))

#----------------------------------------------------------------------
@lm.unauthorized_handler
def unauthorized():
    global user_list
    session_id = request.cookies.get('session_id', '')
    user_list.discard(session_id)
    return redirect(url_for('login'))

#----------------------------------------------------------------------
@app.route('/', methods = ['GET', 'POST'])
@app.route('/index', methods = ['GET', 'POST'])
@limiter.limit('200/second')
@login_required
def index():
    #if request.method == 'POST':
    #    st, prog = rtcapi.readFromDev(rtcapi.CONFIG_ID_PROGRAMM_RESTART)
    #    if st != rtcapi.RPC_OK:
    #        flash(u'Ошибка перезапуска программы! {0};'.format(st))

    if request.method == 'POST':
        value = request.form.get('mode', 'restart')
        if request.form.get('restart'):
            st, prog = rtcapi.readFromDev(rtcapi.CONFIG_ID_PROGRAMM_RESTART)
            if st != rtcapi.RPC_OK:
                ##flash(gettext('Error restarting the program! %(state)s;', state = str(st)), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, gettext('Error restarting the program!').encode('utf8')).decode('utf8')), category='danger')
        elif value in ['local', 'adaptive']:
            st, mode = rtcapi.writeToDev(rtcapi.CONFIG_ID_PROGRAMM_MODE, str(value))
            if st != rtcapi.RPC_OK:
                ##flash(gettext('Error setting mode! %(state)s;', state = str(st)), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, gettext('Error setting mode!').encode('utf8')).decode('utf8')), category='danger')
    
    allinfo = {}
    #fulltime = {"date": datetime.strftime(time, "%d.%m.%Y"), "time": datetime.strftime(time, "%H:%M:%S")}
    st, allinfo = rtcapi.readFromDev(rtcapi.CONFIG_ID_GET_CURRENT_ALL_INFO)
    if st != rtcapi.RPC_OK:
        flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, allinfo).decode('utf8')), category='danger')
        allinfo = {}
    
    time = {}
    count_phases = allinfo.get('count_phases', 0)
    remaining_time = -1
    adaptive = True
    detectors = []
    for det in allinfo.get('adaptive_control', []):
        d = det.get('num_detector')
        if d:
            detectors.append(d)
    # Ищем в условиях перехода фаз все детекторы
    reg = re.compile('\(\s*D([0-9]{1,3})\s*\)')
    for transitions in allinfo.get('phase_transitions', {}).values():
        for transition in transitions:
            call_condition = transition.get('call_condition', '')
            extension_condition = transition.get('extension_condition', '')
            termination_condition = transition.get('termination_condition', '')
            condition = call_condition + extension_condition + termination_condition
            if condition:
                detectors.extend([int(i) for i in reg.findall(condition) if i.isdigit()])
    
    detectors = list(set(detectors))
    if detectors == ['']:
        detectors = []
    
    if len(allinfo.get('inputs', [])) == 0 or not detectors:
        adaptive = False
    
    time_tmp = allinfo.get('datetime', {})
    if time_tmp.get('time') and time_tmp.get('date'):
        time['hour'] = time_tmp.get('time').split(':')[0]
        time['minute'] = time_tmp.get('time').split(':')[1]
        time['second'] = time_tmp.get('time').split(':')[2]
    
    current_phase = allinfo.get('current_phase')
    if current_phase:
        plan = allinfo.get('plan', {}).values()[0]
        cross_time = plan.get('crossTime', {})
        count_phases = len(cross_time) if len(cross_time) else allinfo.get('count_phases', 0)
        tmp = sum([i[0] if type(i) == list else i for i in cross_time.get(str(current_phase), [])]) - allinfo.get('elapsed_phase_time', 0)
        remaining_time = tmp if tmp >=0 else -1
    
    if not 'plan' in allinfo:
        allinfo['plan'] = {}
    
    pages = {'index': 'active'}
    return render_template("index.html",
        title = gettext('Home'),
        time = time,
        datetime = allinfo.get('datetime', {}),
        data = allinfo,
        desc = allinfo.get('desc', {}),
        count_phases = count_phases,
        remaining_time = remaining_time,
        adaptive = adaptive,
        pages = pages)

#----------------------------------------------------------------------
@app.route('/detectors', methods = ['GET', 'POST'])
@app.route('/detectors/<string:type_tab>', methods = ['GET', 'POST'])
@app.route('/detectors/<string:type_tab>/<string:type_eth_detectors>', methods = ['GET', 'POST'])
@limiter.limit('200/second')
@login_required
def detectors(type_tab = 'status', type_eth_detectors = 'smartvision'):
    """type_tab: status; traffic_counting; security; eth_detectors;"""
    pages = {'detectors': 'active'}
    tab = {type_tab: 'active', type_eth_detectors: 'active'}
    data = {}
    
    if request.method == 'GET':
        if type_tab == 'status':
            st, detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_DETECTORS)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, detectors).decode('utf8')), category='danger')
            elif detectors:
                data['adaptive_control'] = detectors.get('adaptive_control', [])
        elif type_tab == 'traffic_counting':
            st, detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_DETECTORS)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, detectors).decode('utf8')), category='danger')
            elif detectors:
                data['traffic_counting'] = detectors.get('traffic_counting', {'1h': [{'': {}}], '24h': [{'': {}}]})
                for cnt, cnt_dets in data['traffic_counting'].items():
                    if not cnt_dets:
                        data['traffic_counting'][cnt] = [{'': {}}]

                data['phase_counting'] = detectors.get('phase_counting', {'1h': [{'': {}}], '24h': [{'': {}}]})
                for cnt, cnt_dets in data['phase_counting'].items():
                    if not cnt_dets:
                        data['phase_counting'][cnt] = [{'': {}}]

        elif type_tab == 'security':
            st, detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_DETECTORS)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, detectors).decode('utf8')), category='danger')
            elif detectors:
                data['onoff'] = detectors.get('onoff', False)
                data['adaptive_control'] = detectors.get('adaptive_control', [])
        elif type_tab == 'eth_detectors':
            if type_eth_detectors == 'smartvision':
                data['ip'] = ['' for i in range(MAX_AMOUNT_CAMERAS)]
                data['alias'] = ['' for i in range(MAX_AMOUNT_CAMERAS)]
                data['number'] = list(range(1,MAX_AMOUNT_CAMERAS+1))
            elif type_eth_detectors == 'traficam':
                data['ip_traficam'] = ['' for i in range(MAX_AMOUNT_CAMERAS_TRAFICAM)]
                data['alias_traficam'] = ['' for i in range(MAX_AMOUNT_CAMERAS_TRAFICAM)]
                data['number_traficam'] = list(range(1,MAX_AMOUNT_CAMERAS_TRAFICAM+1))
            elif type_eth_detectors == 'traffixtream2':
                data['ip_traffixtream2'] = ['' for i in range(MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2)]
                data['alias_traffixtream2'] = ['' for i in range(MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2)]
                data['login_traffixtream2'] = ['' for i in range(MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2)]
                data['password_traffixtream2'] = ['' for i in range(MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2)]
                data['number_traffixtream2'] = list(range(1,MAX_AMOUNT_CAMERAS_TRAFFIXTREAM2+1))
            
            st, eth_detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_ETH_DETECTORS)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, eth_detectors).decode('utf8')), category='danger')
            elif eth_detectors:
                if type_eth_detectors == 'smartvision':
                    data['ip'] = eth_detectors.get('ip', [])
                    data['alias'] = eth_detectors.get('alias', [])
                    data['number'] = eth_detectors.get('number', [])
                elif type_eth_detectors == 'traficam':
                    data['ip_traficam'] = eth_detectors.get('ip_traficam', [])
                    data['alias_traficam'] = eth_detectors.get('alias_traficam', [])
                    data['number_traficam'] = eth_detectors.get('number_traficam', [])
                elif type_eth_detectors == 'traffixtream2':
                    data['ip_traffixtream2'] = eth_detectors.get('ip_traffixtream2', [])
                    data['alias_traffixtream2'] = eth_detectors.get('alias_traffixtream2', [])
                    data['login_traffixtream2'] = eth_detectors.get('login_traffixtream2', [])
                    data['password_traffixtream2'] = eth_detectors.get('password_traffixtream2', [])
                    data['number_traffixtream2'] = eth_detectors.get('number_traffixtream2', [])
    
    if request.method == 'POST':
        if type_tab == 'status':
            detectors = request.form.getlist("detectors[]", type=int)
            status = request.form.getlist("status[]", type=int)
            state = request.form.getlist("state[]", type=int)
            ##data['status'] = []
            data['adaptive_control'] = []
            for det, stat, st in map(None, detectors, status, state):
                data['adaptive_control'].append({"num_detector": det, 'detector_state': st})
                ##data['status'].append(stat)
            
            st, detectors = rtcapi.writeToDev(rtcapi.CONFIG_ID_DETECTORS, data)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, detectors).decode('utf8')), category='danger')
            else:
                flash(gettext('Data saved.'), category='info')
        elif type_tab == 'traffic_counting':
            st, detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_DETECTORS)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, detectors).decode('utf8')), category='danger')
            elif detectors:
                csv = ''

                # merge traffic counts with phases
                traffic_counts = detectors.get('traffic_counting', {})
                for counts in traffic_counts:
                    c = traffic_counts[counts]
                    for d in c:
                        for t in d:
                            d[t] = {'D{}'.format(i): d[t][i] for i in d[t]}
                phase_counts = detectors.get('phase_counting', {})
                for counts in phase_counts:
                    c = phase_counts[counts]
                    for d in c:
                        for t in d:
                            d[t] = {'S{}'.format(i): d[t][i] for i in d[t]}

                result = {'1h': [], '24h': []}
                for cnt in traffic_counts:
                    result[cnt] = traffic_counts[cnt]

                for cnt in phase_counts:
                    for tstmp_dict in phase_counts[cnt]:
                        for tstmp in tstmp_dict:
                            f = False
                            for res_tstmp in result[cnt]:
                                if tstmp in res_tstmp:
                                    res_tstmp[tstmp].update(tstmp_dict[tstmp])
                                    f = True
                        if f:
                            continue
                        if tstmp_dict not in result[cnt]:
                            result[cnt].append(tstmp_dict)

                for cnt, timestamps in result.items():
                    csv += '/*counter{0}*/\n'.format(cnt)
                    for tmstamp in timestamps:
                        for timestamp, cnt_dets in tmstamp.items():
                            csv += '{},{}\n'.format(timestamp, ','.join(map(lambda y: '{},{}'.format(*y), sorted(cnt_dets.items(), key = lambda x : x[0]))))
                
                response = make_response(csv)
                response.headers["Content-type"] ="multipart/form-data"
                response.headers["Content-Disposition"] = "attachment; filename=traffic_counting_{0}.csv".format(datetime.strftime(datetime.now(), "%d.%m.%Y_%H:%M:%S"))
                return response
        elif type_tab == 'security':
            onoff = request.form.get('onoff', type=bool)
            detectors = request.form.getlist("detectors[]", type=int)
            detector_time_on = request.form.getlist('detector_time_on[]', type=int)
            detector_time_off = request.form.getlist('detector_time_off[]', type=int)
            data['onoff'] = bool(onoff)
            data['adaptive_control'] = []
            for det, time_on, time_off in map(None, detectors, detector_time_on, detector_time_off):
                data['adaptive_control'].append({"num_detector": det, 'detector_time_on': time_on, 'detector_time_off': time_off})
            
            st, detectors = rtcapi.writeToDev(rtcapi.CONFIG_ID_DETECTORS, data)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, detectors).decode('utf8')), category='danger')
            else:
                flash(gettext('Data saved.'), category='info')
        elif type_tab == 'eth_detectors':
            error = False
            ips = []
            aliases = []
            logins = []
            passwords = []
            numbers = []
            if type_eth_detectors == 'smartvision':
                ips = request.form.getlist("ip[]", type=str)
                aliases = request.form.getlist("alias[]", type=str)
                numbers = request.form.getlist("number[]", type=int)
            elif type_eth_detectors == 'traficam':
                ips = request.form.getlist("ip_traficam[]", type=str)
                aliases = request.form.getlist("alias_traficam[]", type=str)
                numbers = request.form.getlist("number_traficam[]", type=int)
            elif type_eth_detectors == 'traffixtream2':
                ips = request.form.getlist("ip_traffixtream2[]", type=str)
                aliases = request.form.getlist("alias_traffixtream2[]", type=str)
                logins = request.form.getlist("login_traffixtream2[]", type=str)
                passwords = request.form.getlist("password_traffixtream2[]", type=str)
                numbers = request.form.getlist("number_traffixtream2[]", type=int)
            
            tmp_ips = ['.'.join([j.lstrip('0') if j.lstrip('0') else '0' for j in i.partition(':')[0].split('.')]) for i in ips if i != '']
            tmp_aliases = [i.lstrip('0') for i in aliases if i != '']
            if len(tmp_ips) != len(list(set(tmp_ips))) or len(tmp_aliases) != len(list(set(tmp_aliases))):
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('IP addresses and end-to-end numbering of cameras should be unique.').encode('utf8')).decode('utf8')), category='danger')
                error = True
            
            subnets = []
            network_hub = {}
            st, network = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, network).decode('utf8')), category='danger')
                error = True
            elif network:
                network_hub = network
            mask_hub = network_hub.get('mask')
            ip_hub = network_hub.get('ip')
            subnets.append(address.makeSubnet(ip_hub, mask_hub))
            
            for ip in tmp_ips:
                subnets.append(address.makeSubnet(ip, mask_hub))
            if len(list(set(subnets))) > 1:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('The IP addresses of the cameras must be on the same subnet as the hub.').encode('utf8')).decode('utf8')), category='danger')
                error = True
            
            if type_eth_detectors == 'smartvision':
                data['ip'] = []
                data['alias'] = []
                data['number'] = []
            elif type_eth_detectors == 'traficam':
                data['ip_traficam'] = []
                data['alias_traficam'] = []
                data['number_traficam'] = []
            elif type_eth_detectors == 'traffixtream2':
                data['ip_traffixtream2'] = []
                data['alias_traffixtream2'] = []
                data['login_traffixtream2'] = []
                data['password_traffixtream2'] = []
                data['number_traffixtream2'] = []
            
            n = 1
            for ip, alias, number, login, passwd in map(None, ips, aliases, numbers, logins, passwords):
                if type_eth_detectors == 'smartvision':
                    data['ip'].append(ip if ip else '')
                    data['alias'].append(int(alias) if alias else '')
                    data['number'].append(n)
                elif type_eth_detectors == 'traficam':
                    data['ip_traficam'].append(ip if ip else '')
                    data['alias_traficam'].append(int(alias) if alias else '')
                    data['number_traficam'].append(n)
                elif type_eth_detectors == 'traffixtream2':
                    data['ip_traffixtream2'].append(ip if ip else '')
                    data['alias_traffixtream2'].append(int(alias) if alias else '')
                    data['login_traffixtream2'].append(login if login else '')
                    data['password_traffixtream2'].append(passwd if passwd else '')
                    data['number_traffixtream2'].append(n)
                n += 1
            
            if not error:
                eth_detectors = {}
                if type_eth_detectors == 'smartvision':
                    eth_detectors['ip'] = data.get('ip', [])
                    eth_detectors['alias'] = data.get('alias', [])
                    eth_detectors['number'] = data.get('number', [])
                elif type_eth_detectors == 'traficam':
                    eth_detectors['ip_traficam'] = data.get('ip_traficam', [])
                    eth_detectors['alias_traficam'] = data.get('alias_traficam', [])
                    eth_detectors['number_traficam'] = data.get('number_traficam', [])
                elif type_eth_detectors == 'traffixtream2':
                    eth_detectors['ip_traffixtream2'] = data.get('ip_traffixtream2', [])
                    eth_detectors['alias_traffixtream2'] = data.get('alias_traffixtream2', [])
                    eth_detectors['login_traffixtream2'] = data.get('login_traffixtream2', [])
                    eth_detectors['password_traffixtream2'] = data.get('password_traffixtream2', [])
                    eth_detectors['number_traffixtream2'] = data.get('number_traffixtream2', [])
                
                st, eth_detectors = rtcapi.writeToDev(rtcapi.CONFIG_ID_ETH_DETECTORS, eth_detectors)
                if st != rtcapi.RPC_OK:
                    flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, eth_detectors).decode('utf8')), category='danger')
                else:
                    flash(gettext('Data saved.'), category='info')
    
    return render_template("detectors.html",
        title = gettext('Detectors'),
        type_tab = type_tab,
        type_eth_detectors = type_eth_detectors,
        enumerate=enumerate,
        sorted=sorted,
        lm=lambda x : int(x[0]),
        int=int,
        tab = tab,
        data = data,
        pages = pages)


#----------------------------------------------------------------------
@app.route('/controller_management', methods = ['GET', 'POST'])
@login_required
def controller_management():
    pages = {'controller_management': 'active'}
    data = {
        'proto':'UG405',
        'scn':'',
        'tail':'',
        'protoversion': 'v2c',
        'authpass': '',
        'privpass': '',
        'auth_encryp_type': '',
        'priv_encryp_type': '',
        'notify_type': 'trap'
    }
    if request.method == 'GET':
        st, snmp_proto = rtcapi.readFromDev(rtcapi.CONFIG_ID_SNMP_PROTO)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, snmp_proto).decode('utf8')), category='danger')
        else:
            if snmp_proto:
                for key in snmp_proto:
                    data[key] = snmp_proto[key]
        
        st, buff = rtcapi.readFromDev(rtcapi.CONFIG_ID_SNMP_ADDRESS)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, buff).decode('utf8')), category='danger')
        else:
            if buff:
                for key in buff:
                    kk = key.replace('ip', 'ip_receiver').replace('port', 'port_receiver')
                    data[kk] = buff[key] if buff[key] not in ['0.0.0.0', 'none', 'null', None, 0] else ''
    
    if request.method == 'POST':
        error = False
        proto = request.form.get("proto", type=str)
        scn = request.form.get("scn", type=str).strip().upper()
        protoversion = request.form.get("protoversion", '', type=str)
        user = request.form.get("user", '', type=str).strip()
        authpass = request.form.get("authpass", '', type=str).strip()
        auth_encryp_type = request.form.get("auth_encryp_type", '', type=str).upper()
        privpass = request.form.get("privpass", '', type=str).strip()
        priv_encryp_type = request.form.get("priv_encryp_type", '', type=str).upper()
        notify_type = request.form.get("notify_type", type=str)
        ip_receiver = request.form.get("ip_receiver", '', type=str)
        port_receiver = request.form.get("port_receiver", '', type=int)
        tail = ''
        
        if proto == "UG405" and re.search(r"^C{1}O{1}\d{1,4}$", scn) == None:
            ##flash(gettext('For the UG405 protocol, the SCN value is required!'), category='danger')
            ##flash(gettext('Format SCN = COX, where "CO" - required characters in Latin letters, and X - the number from 1 to 9999;'), category='danger')
            flash(gettext('Error! %(state)s', state = '{0}; {1} {2};'.format('', gettext('For the UG405 protocol, the SCN value is required!').encode('utf8'), gettext('Format SCN = COX, where "CO" - required characters in Latin letters, and X - the number from 1 to 9999;').encode('utf8')).decode('utf8')), category='danger')
            
            error = True
        elif proto == "UG405" and scn:
            tail = "1{0}".format(scn)
        
        if protoversion == 'v3' and \
           (not user or not authpass or not auth_encryp_type or not privpass or not priv_encryp_type):
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('Please fill in all fields.').encode('utf8')).decode('utf8')), category='danger')
            error = True
        
        if not ip_receiver and port_receiver:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('Please enter the receiver ip address.').encode('utf8')).decode('utf8')), category='danger')
            error = True
        elif ip_receiver and not port_receiver:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('Please enter the receiver port.').encode('utf8')).decode('utf8')), category='danger')
            error = True
        
        data = {'proto': proto, 'scn':scn, 'tail':tail}
        data.update({'protoversion': protoversion, 'user':user, 'authpass':authpass, 'auth_encryp_type':auth_encryp_type, 'privpass':privpass, 'priv_encryp_type':priv_encryp_type})
        
        if not error:
            err = False
            st, snmp_proto = rtcapi.writeToDev(rtcapi.CONFIG_ID_SNMP_PROTO, data)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, snmp_proto).decode('utf8')), category='danger')
                err = True
            
            if ip_receiver and port_receiver or 1:
                st, buff = rtcapi.writeToDev(rtcapi.CONFIG_ID_SNMP_ADDRESS, {'notify_type': notify_type, 'ip': ip_receiver, 'port': port_receiver if port_receiver != None else ''})
                if st != rtcapi.RPC_OK:
                    flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, buff).decode('utf8')), category='danger')
                    err = True
            
            if not err:
                flash(gettext('Data saved.'), category='info')
            return redirect(url_for('controller_management'))
        
        data.update({'notify_type': notify_type, 'ip_receiver': ip_receiver, 'port_receiver': port_receiver if port_receiver != None else ''})
    return render_template("controller_management.html",
        title = gettext('Management controller'),
        data = data,
        pages = pages)

#----------------------------------------------------------------------
@app.route("/dynamicTableCenterlessUrl")
@limiter.limit('200/second')
@login_required
def dynamicTableCenterlessUrl():
    return Response(render_template("/js/dynamicTableCenterless.js"), mimetype = "text/javascript")

#----------------------------------------------------------------------
@app.route('/centerless_control', methods = ['GET', 'POST'])
@limiter.limit('200/second')
@login_required
def centerless_control():
    pages = {'centerless_control': 'active'}
    centerless_control = {'onoff': False, 'control_mode': '', 'master': {}, 'slave': {}}
    if request.method == 'GET':
        st, centerless_control = rtcapi.readFromDev(rtcapi.CONFIG_ID_CENTERLESS_CONTROL)
        if st != rtcapi.RPC_OK or not centerless_control:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, centerless_control).decode('utf8')), category='danger')
            centerless_control = {'onoff': False, 'control_mode': '', 'master': {}, 'slave': {}}
    
    if request.method == 'POST':
        if request.form.get('rescan', type=int) == 1:
            st, scan = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK_SCAN, 1)#1 - ip, 0 - mac
            if st != rtcapi.RPC_OK:
                ##flash(gettext('Network Scan Error! %(state)s', state = '{0}; {1};'.format(st, scan).decode('utf8')), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, scan).decode('utf8')), category='danger')
                scan = {}
            tmp_scan = {}
            if scan:
                for ip, value in sorted(scan.iteritems()):
                    #print 'IP: {:<16} MAC: {:<18} STATE: {:<8} VENDOR: {}'.format(value.get('ip'), value.get('mac'), value.get('state'), value.get('vendor'))
                    #tmp_scan[mac] = value
                    st, slave = rtcapi.readFromDev(rtcapi.CONFIG_ID_CENTERLESS_CONTROL_INIT, {'ip': ip})
                    if st == rtcapi.RPC_OK and type(slave) == dict:
                        tmp_scan[ip] = value
                        tmp_scan[ip]['centerless_control'] = slave
                        tmp_scan[ip]['host'] = request.host
            #print(str(tmp_scan))
            return jsonify(tmp_scan)
        #master
        elif request.form.get('check', type=int) == 1:
            ip = request.form.get('ip', type=str)
            st, slave = rtcapi.readFromDev(rtcapi.CONFIG_ID_CENTERLESS_CONTROL_INIT, {'ip': ip})
            if st == rtcapi.RPC_OK:
                if slave.get('onoff') == True and slave.get('control_mode') == 'slave' and slave.get('slave', {}).get('master_ip') == request.host:
                    return jsonify({ip: ['check_ok', 'check_ok']})
                else:
                    return jsonify({ip: ['check_ok', 'check_error']})
            return jsonify({ip: ['check_error', 'check_error']})
        #slave
        elif request.form.get('check', type=int) == 2:
            ip = request.form.get('ip', type=str)
            st, cntrlss_ctrl = rtcapi.readFromDev(rtcapi.CONFIG_ID_CENTERLESS_CONTROL_INIT, {'ip': ip})
            if st == rtcapi.RPC_OK:
                if cntrlss_ctrl.get('onoff') == True and cntrlss_ctrl.get('control_mode') == 'master' and request.host in map(lambda x: x.get('ip'), cntrlss_ctrl.get('master', {}).get('slaves', [])):
                    return jsonify({ip: ['check_ok', 'check_ok']})
                else:
                    return jsonify({ip: ['check_ok', 'check_error']})
            return jsonify({ip: ['check_error', 'check_error']})
        
        error = False
        onoff = request.form.get("onoff", False, type=bool)
        control_mode = request.form.get("control_mode", "", type=str)
        ## master
        master_timeout = request.form.get("master_timeout", 60, type=int)
        slave_numbers = request.form.getlist("slave_number[]", type=int)
        slave_ids = request.form.getlist("slave_id[]", type=int)
        slave_ips = request.form.getlist("slave_ip[]", type=str)
        ## slave
        master_ip = request.form.get("master_ip", "", type=str)
        slave_timeout_command = request.form.get("slave_timeout_command", 120, type=int)
        slave_timeout_link = request.form.get("slave_timeout_link", 10, type=int)
        
        centerless_control['onoff'] = onoff
        if 1:#onoff
            centerless_control['control_mode'] = control_mode
        
        if 1:#onoff
            if control_mode == 'master':
                tmp_ips = ['.'.join([j.lstrip('0') if j.lstrip('0') else '0' for j in i.split('.')]) for i in slave_ips if i != '']
                if len(tmp_ips) != len(list(set(tmp_ips))):
                    ##flash(gettext('IP addresses must be unique'), category='danger')
                    flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('IP addresses must be unique.').encode('utf8')).decode('utf8')), category='danger')
                    error = True
                if len(slave_ids) != len(list(set(slave_ids))):
                    ##flash(gettext('MAC addresses must be unique'), category='danger')
                    flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('ID number must be unique.').encode('utf8')).decode('utf8')), category='danger')
                    error = True
                
                subnets = []
                network_hub = {}
                st, network = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK)
                if st != rtcapi.RPC_OK:
                    flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, network).decode('utf8')), category='danger')
                    error = True
                elif network:
                    network_hub = network
                mask_hub = network_hub.get('mask')
                ip_hub = network_hub.get('ip')
                subnets.append(address.makeSubnet(ip_hub, mask_hub))
                for ip in tmp_ips:
                    subnets.append(address.makeSubnet(ip, mask_hub))
                if len(list(set(subnets))) > 1:
                    ##flash(gettext('The IP addresses of the countdown displays must be on the same subnet as the hub'), category='danger')
                    flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('The IP addresses must be on the same subnet as the hub.').encode('utf8')).decode('utf8')), category='danger')
                    ##error = True # 5.1.5 В случае некорректной настройки сетевых параметров бесцентровой координации на веб-интерфейс выводится соответствующее предупреждение, такие настройки при этом сохраняются.
                
                centerless_control['master'] = {}
                centerless_control['master']['master_timeout'] = master_timeout
                centerless_control['master']['slaves'] = []
                for s_id, s_ip in map(None, slave_ids, slave_ips):
                    tmp = {}
                    tmp['id'] = s_id if s_id else 0
                    tmp['ip'] = s_ip
                    centerless_control['master']['slaves'].append(tmp)
            elif control_mode == 'slave':
                centerless_control['slave'] = {}
                centerless_control['slave']['master_ip'] = master_ip
                centerless_control['slave']['timeout_command'] = slave_timeout_command
                centerless_control['slave']['timeout_link'] = slave_timeout_link
            else:
                centerless_control['onoff'] = False
                centerless_control['master'] = {}
                centerless_control['slave'] = {}
                
        #flash(str(centerless_control), category='danger')
        if not error:
            st, data = rtcapi.writeToDev(rtcapi.CONFIG_ID_CENTERLESS_CONTROL, centerless_control)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, data).decode('utf8')), category='danger')
            else:
                centerless_control = data
                flash(gettext('Data saved.'), category='info')
                
    return render_template("centerless_control.html",
        title = gettext('Centerless control'),
        enumerate=enumerate,
        data = centerless_control,
        pages = pages)

#----------------------------------------------------------------------
@app.route('/countdown_display', methods = ['GET', 'POST'])
@login_required
def countdown_display():
    pages = {'countdown_display': 'active'}
    ##data = {'onoff': True, 'groups': [1,2,3,4], 'countdown': [{'ip': '192.168.0.33', 'mac': '', 'vendor': '', 'group': ''}]}
    ##data = {'onoff': False}
    data = {}
    if request.method == 'GET':
        st, countdown = rtcapi.readFromDev(rtcapi.CONFIG_ID_COUNTDOWN_DISPLAY)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, countdown).decode('utf8')), category='danger')
        elif countdown:
            data['onoff'] = countdown.get('onoff', False)
            data['timeout'] = countdown.get('timeout', 60)
            data['countdown'] = countdown.get('countdown', [{}])
        
        st, plan = rtcapi.readFromDev(rtcapi.CONFIG_ID_PLAN)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, plan).decode('utf8')), category='danger')
        elif plan:
            data['groups'] = []
            for n in plan:
                data['groups'] = range(1, len(plan[n].get('crossColorGlob', {})) + 1)
                break
        
        data['count_groups'] = len(data.get('groups', []))
    
    if request.method == 'POST':
        if request.form.get('rescan', type=int) == 1:
            st, scan = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK_SCAN)
            if st != rtcapi.RPC_OK:
                ##flash(gettext('Network Scan Error! %(state)s', state = '{0}; {1};'.format(st, scan).decode('utf8')), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, scan).decode('utf8')), category='danger')
                scan = {}
            tmp_scan = {}
            if scan:
                for mac, value in sorted(scan.iteritems()):
                    #print 'IP: {:<16} MAC: {:<18} STATE: {:<8} VENDOR: {}'.format(value.get('ip'), value.get('mac'), value.get('state'), value.get('vendor'))
                    #tmp_scan[mac] = value
                    st, toob = rtcapi.readFromDev(rtcapi.CONFIG_ID_COUNTDOWN_DISPLAY_INIT, {'ip': value.get('ip'), 'mac':value.get('mac')})
                    if st == rtcapi.RPC_OK and toob:
                        tmp_scan[mac] = value
            return jsonify(tmp_scan)
        elif request.form.get('check', type=int) == 1:
            ip = request.form.get('ip', type=str)
            st, toob = rtcapi.readFromDev(rtcapi.CONFIG_ID_COUNTDOWN_DISPLAY_CHECK, {'ip': ip})
            if st == rtcapi.RPC_OK and toob:
                return 'check_ok'
            return 'check_error'
        
        error = False
        onoff = request.form.get("onoff", False, type=bool)
        timeout = request.form.get("timeout", 60, type=int)
        numbers = request.form.getlist("number[]", type=int)
        ips = request.form.getlist("ip[]", type=str)
        macs = request.form.getlist("mac[]", type=str)
        vendors = request.form.getlist("vendor[]", type=str)
        groups = request.form.getlist("group[]", type=int)
        count_groups = request.form.get("groups", 0, type=int)
        
        #scan = {}
        #flash(request.form)
        #if request.form.get('frescan', type=int) == 1:
        #    flash('rescan')
        #    st, scan = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK_SCAN, 1)
        #    if st != rtcapi.RPC_OK:
        #        flash(u'Ошибка сканирования сети! {0}; {1}'.format(st, scan))
        #        scan = {}
        #elif request.form.get('fsave', type=int) == 1:
        #    flash('save')
        #flash(scan)
        if onoff:
            tmp_ips = ['.'.join([j.lstrip('0') if j.lstrip('0') else '0' for j in i.split('.')]) for i in ips if i != '']
            if len(tmp_ips) != len(list(set(tmp_ips))):
                ##flash(gettext('IP addresses must be unique'), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('IP addresses must be unique.').encode('utf8')).decode('utf8')), category='danger')
                error = True
            if len(macs) != len(list(set(macs))):
                ##flash(gettext('MAC addresses must be unique'), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('MAC addresses must be unique.').encode('utf8')).decode('utf8')), category='danger')
                error = True
            st, countdown = rtcapi.readFromDev(rtcapi.CONFIG_ID_COUNTDOWN_DISPLAY)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, countdown).decode('utf8')), category='danger')
                error = True
            subnets = []
            network_hub = {}
            st, network = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, network).decode('utf8')), category='danger')
                error = True
            elif network:
                network_hub = network
            mask_hub = network_hub.get('mask')
            ip_hub = network_hub.get('ip')
            subnets.append(address.makeSubnet(ip_hub, mask_hub))
            for ip in tmp_ips:
                subnets.append(address.makeSubnet(ip, mask_hub))
            if len(list(set(subnets))) > 1:
                ##flash(gettext('The IP addresses of the countdown displays must be on the same subnet as the hub'), category='danger')
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format('', gettext('The IP addresses of the countdown displays must be on the same subnet as the hub.').encode('utf8')).decode('utf8')), category='danger')
                error = True
        
        data['onoff'] = onoff
        data['timeout'] = timeout
        data['countdown'] = []
        data['groups'] = range(1, count_groups + 1)
        data['count_groups'] = count_groups
        
        for ip, mac, vendor, group in map(None, ips, macs, vendors, groups):
            tmp = {}
            tmp['ip'] = ip
            tmp['mac'] = mac
            tmp['vendor'] = vendor if vendor else ''
            tmp['group'] = group
            data['countdown'].append(tmp)
        
        if not error:
            ##data = {'onoff': True, 'groups': [1,2,3,4], 'countdown': [{'ip': '192.168.0.33', 'mac': '', 'vendor': '', 'group': ''}]}
            countdown = {'onoff':data.get('onoff', False), 'timeout': data.get('timeout', 60), 'countdown':data.get('countdown', [{}])}
            st, countdown = rtcapi.writeToDev(rtcapi.CONFIG_ID_COUNTDOWN_DISPLAY, countdown)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, countdown).decode('utf8')), category='danger')
            else:
                flash(gettext('Data saved.'), category='info')
    
    return render_template("countdown_display.html",
        title = gettext('Countdown display'),
        enumerate=enumerate,
        data = data,
        pages = pages)

#----------------------------------------------------------------------
@app.route('/network', methods = ['GET', 'POST'])
@login_required
def network():
    pages = {'network': 'active'}
    network = {'ip':'', 'mask':'', 'gw':''}
    if request.method == 'GET':
        st, network = rtcapi.readFromDev(rtcapi.CONFIG_ID_NETWORK)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, network).decode('utf8')), category='danger')
            network = {}
    form = NetworkForm()
    if form.validate_on_submit():
        network = {'ip':form.ip.data.strip(), 'mask':form.mask.data.strip(), 'gw':form.gw.data.strip()}
        st, network = rtcapi.writeToDev(rtcapi.CONFIG_ID_NETWORK, network)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, network).decode('utf8')), category='danger')
        #else:
        #    if network:
        #        ip = '.'.join([i.lstrip('0') if i != '000' else '0' for i in network.get('ip', '192.168.0.1').split('.')])
        #        return redirect(request.url.replace(request.remote_addr, ip), code=307)
    return render_template("network.html",
        title = gettext('Network'),
        network = network,
        pages = pages,
        form = form)

#----------------------------------------------------------------------
@app.route('/log')
@app.route('/log/<string:type_log>/<int:whence>')
@login_required
def log(type_log='info', whence=0):
    global whence_min, whence_max
    if type_log not in ['info', 'warn', 'error', 'full', 'timestamp_tact'] or (g.user.role != ROLE_ADMIN and type_log == 'full') or whence not in [0, whence_min, whence_max]:
        abort(404)
    code = 0
    if type_log == 'info':
        code = 1
    elif type_log == 'warn':
        code = 2
    elif type_log == 'error':
        code = 3
    elif type_log == 'full':
        code = 4
    elif type_log == 'timestamp_tact':
        code = 5
    if rtcapi.PROTOCOL == 'xmlrpc':
        st, rtclog = rtcapi.readFromDev(rtcapi.CONFIG_ID_LOG, Binary(struct.pack('<Q', (whence << 4) + code)))
    elif rtcapi.PROTOCOL == 'tcp':
        st, rtclog = rtcapi.readFromDev(rtcapi.CONFIG_ID_LOG, (whence << 4) + code)
    if st != rtcapi.RPC_OK:
        whence = 0
        ##rtclog = [0, 0, gettext('State = %(state)s', state = '{0}; {1};'.format(st, rtclog.encode('utf8') if type(rtclog) == str else rtclog))]
        if rtcapi.PROTOCOL == 'xmlrpc':
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, rtclog).decode('utf8')), category='danger')
        elif rtcapi.PROTOCOL == 'tcp':
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, rtclog)), category='danger')
        rtclog = [0, 0, '']
    
    ##rtclog = Markup(''.join(rtclog).replace('\n', ''))
    whence_min, whence_max = 0, 0
    if rtclog:
        whence_min, whence_max, rtclog = rtclog
        whence_min = whence_min << 4
        whence_max = (whence_max << 4) + 1
        if rtcapi.PROTOCOL == 'xmlrpc':
            rtclog = rtclog.encode('utf8')
    rtclog = rtclog.split('\n')
    tmp_rtclog = []
    for line in rtclog:
        code_id = 'log'
        ln = line
        ls_ln = ln.split(';;')
        if len(ls_ln) == 4:
            date, code, text, args = ls_ln
            if type(args) != unicode:
                args = args.decode('utf8')
            code = int(code, base=16) >> 12
            if code == 1:
                code_id = 'info'
            elif code == 2:
                code_id = 'warn'
            elif code == 3:
                code_id = 'err'
            else:
                code_id = 'log'
            
            args = args.replace('\\n', '<br>')
            args = [gettext(i) if i else '' for i in args.split(',,')]
            text = text.replace('%', '%%')
            if rtcapi.PROTOCOL == 'tcp':
                ln = '[{0}] - <strong>{1}</strong>: {2}'.format(date, gettext(code_id).encode('utf8'), gettext(text).format(*args).encode('utf8'))
            elif rtcapi.PROTOCOL == 'xmlrpc':
                ln = '[{0}] - <strong>{1}</strong>: {2}'.format(date, gettext(code_id).encode('utf8'), gettext(text.decode('utf8')).format(*args).encode('utf8'))
            #ln = '[{0}] - {1}: {2}'.format(date, gettext(code_id).encode('utf8'), gettext(text.decode('utf8')).format(*args.split(',,')).encode('utf8'))
            ##if args:
                ##ln = '[{0}] - {1}: {2}'.format(date, gettext(code_id).encode('utf8'), text.format(*args.split(',,')))## добавить перевод форматированного сообщения
        else:
            code_id = 'log'
            if ln:
                #ln = '<b>{0}</b>'.format(gettext(ln.decode('utf8')).encode('utf8'))
                ln = ln.replace('%', '%%')
                ln = '<b>{0}</b>'.format(gettext(ln if type(ln) == unicode else ln.decode('utf8')).encode('utf8'))
            ##ln = '<b>{0}</b>'.format(ln)
        tmp_rtclog.append('<font class="{0}">{1}</font><br>'.format(code_id, ln))
    
    rtclog = Markup(''.join(tmp_rtclog).decode('utf8'))
    pages = {'log': 'active'}
    tab = {type_log: 'active'}
    
    return render_template("log.html",
        title = gettext('Log'),
        type_log = type_log,
        tab = tab,
        log = rtclog,
        whence_min = whence_min,
        whence_max = whence_max,
        pages = pages)

#----------------------------------------------------------------------
@app.route('/log_full_csv')
@app.route('/log_full_csv/<int:whence>')
@login_required
def log_full_csv(whence=0):
    if g.user.role == ROLE_GUEST:
        abort(404)
    
    code = 4
    if rtcapi.PROTOCOL == 'xmlrpc':
        st, rtclog = rtcapi.readFromDev(rtcapi.CONFIG_ID_LOG, Binary(struct.pack('<Q', (whence << 4) + code)))
    elif rtcapi.PROTOCOL == 'tcp':
        st, rtclog = rtcapi.readFromDev(rtcapi.CONFIG_ID_LOG, (whence << 4) + code)
    if st != rtcapi.RPC_OK:
        whence = 0
        rtclog = [0, 0, '']
    
    whence_min, whence_max = 0, 0
    if rtclog:
        whence_min, whence_max, rtclog = rtclog
        whence_min = whence_min << 4
        whence_max = (whence_max << 4) + 1
        rtclog = rtclog.encode('utf8')
    
    return jsonify({"whence_min": whence_min, "whence_max": whence_max, "rtclog": rtclog})

#----------------------------------------------------------------------
@app.route('/current', methods = ['GET', 'POST'])
@limiter.limit('200/second')
@login_required
def current():
    pages = {'current': 'active'}
    count_group = 0
    current_lamps = {'voltage_onoff': True, 'currents': {}}
    data = {'count_group': count_group, 'current_lamps': current_lamps}
    if request.method == 'GET':
        st, plan = rtcapi.readFromDev(rtcapi.CONFIG_ID_PLAN)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, plan).decode('utf8')), category='danger')
        else:
            if plan:
                data['count_group'] = len(plan.values()[0].get('crossColorGlob', []))
        st, current_lamps = rtcapi.readFromDev(rtcapi.CONFIG_ID_THRESHOLD_CURRENTS)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, current_lamps).decode('utf8')), category='danger')
        else:
            if current_lamps:
                voltage_onoff = current_lamps.get('voltage_onoff', True)
                current_lamps['voltage_onoff'] = voltage_onoff
                currents = sorted([(int(i), j) for i,j in current_lamps.get('currents', {}).items()])
                current_lamps['currents'] = currents
                data['current_lamps'] = current_lamps
    
    if request.method == 'POST':
        onoff = request.form.get("onoff", False, type=bool)
        delay = request.form.get("delay", 400, type=int)
        voltage_onoff = request.form.get("voltage_onoff", False, type=bool)
        master = request.form.get("master", 0, type=int)
        manual = request.form.get("manual", False, type=bool)
        req_currents = request.form.getlist("currents[]", type=int)
        currents = {}
        for i, curr in enumerate(req_currents):
            gr = i//4+1
            if str(gr) not in currents:
                currents[str(gr)] = []
            currents[str(gr)].append(curr)
        
        count_group = len(currents)
        error = False
        
        current_lamps = {}
        current_lamps['onoff'] = onoff
        current_lamps['delay'] = delay
        current_lamps['voltage_onoff'] = voltage_onoff
        current_lamps['master'] = master
        current_lamps['manual'] = manual
        current_lamps['currents'] = currents
        
        if not error:
            st, buff = rtcapi.writeToDev(rtcapi.CONFIG_ID_THRESHOLD_CURRENTS, current_lamps)
            if st != rtcapi.RPC_OK:
                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, buff).decode('utf8')), category='danger')
            else:
                flash(gettext('Data saved.'), category='info')
            return redirect(url_for('current'))
        
        current_lamps['currents'] = sorted([(int(i), j) for i,j in currents.items()])
        data = {'count_group': count_group, 'current_lamps': current_lamps}
    
    tl_lite = False
    if os.name == 'posix' and os.uname()[1].lower() == 'sintez-lite-3b':
        tl_lite = True
    
    return render_template("current.html",
        title = gettext('Lamps current'),
        enumerate=enumerate,
        tl_lite = tl_lite,
        data = data,
        pages = pages)

#----------------------------------------------------------------------
@app.route('/police', methods = ['GET', 'POST'])
@login_required
def police():
    pages = {'police': 'active'}
    data = {}
    if request.method == 'GET':
        # deny rcp
        st, deny_rcp = rtcapi.readFromDev(rtcapi.CONFIG_ID_DENY_RCP)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, deny_rcp).decode('utf8')), category='danger')
        elif deny_rcp != None:
            data['onoff'] = deny_rcp
        
        # deny fix mode stcip
        st, deny_fix = rtcapi.readFromDev(rtcapi.CONFIG_ID_DENY_FIX_MODE_SNMP)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, deny_fix).decode('utf8')), category='danger')
        elif deny_rcp != None:
            data['onoff_fix'] = deny_fix

        # deny remote controll if af error    
        st, deny_rc_aferror = rtcapi.readFromDev(rtcapi.CONFIG_ID_DENY_CONTROL_AFERROR)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, deny_rc_aferror).decode('utf8')), category='danger')
        elif deny_rcp != None:
            data['onoff_aferror'] = deny_rc_aferror

    if request.method == 'POST':
        error = False
        onoff = request.form.get("onoff", False, type=bool)
        onoff_fix = request.form.get("onoff_fix", False, type=bool)
        onoff_aferror = request.form.get("onoff_aferror", False, type=bool)
        data = {'onoff': onoff, 'onoff_fix': onoff_fix, 'onoff_aferror': onoff_aferror}

        # post deny rcp
        st, buff = rtcapi.writeToDev(rtcapi.CONFIG_ID_DENY_RCP, onoff)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, buff).decode('utf8')), category='danger')
            error = True
        
        # post deny fix mode stcip
        st, buff = rtcapi.writeToDev(rtcapi.CONFIG_ID_DENY_FIX_MODE_SNMP, onoff_fix)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, buff).decode('utf8')), category='danger')
            error = True
        
        # post aferror deny 
        st, buff = rtcapi.writeToDev(rtcapi.CONFIG_ID_DENY_CONTROL_AFERROR, onoff_aferror)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, buff).decode('utf8')), category='danger')
            error = True

        if not error:
            flash(gettext('Data saved.'), category='info')
            return redirect(url_for('police'))
    
    return render_template("police.html",
        title = gettext('Police'),
        data = data,
        pages = pages)

#----------------------------------------------------------------------
@app.route('/security', methods = ['GET', 'POST'])
@login_required
def security():
    if g.user.role == ROLE_GUEST:
        abort(404)
    
    form = SecurityForm()
    if form.validate_on_submit():
        #flash(u'login={0}; passwd={1}; repasswd={2};'.format(str(form.login.data), str(form.password.data), str(form.repassword.data)))
        user = User.query.filter_by(login = str(form.login.data)).first()
        #print(user.login)
        if user and str(form.login.data) in ['operator', 'guest']:
            if len(str(form.password.data)) >= 4 and len(str(form.password.data)) <=16:
                if str(form.password.data) == str(form.repassword.data):
                    user.passwd = str(form.password.data)
                    db.session.commit()
                else:
                    form.login.errors.append(gettext('Password mismatch!'))
            else:
                form.login.errors.append(gettext('The password must contain from 4 to 16 characters!'))
        else:
            form.login.errors.append(gettext('User %(nickname)s does not exist!', nickname = str(form.login.data)))
        return redirect(url_for('security'))
    
    pages = {'security': 'active'}
    return render_template("security.html",
        title = gettext('Security'),
        pages = pages,
        form = form)

#----------------------------------------------------------------------
@app.route('/localtime', methods = ['GET', 'POST'])
@login_required
def localtime():
    if g.user.role == ROLE_GUEST:
        abort(404)
    datetimenow = None
    timestamp = time.time()
    time_now = datetime.fromtimestamp(timestamp)
    time_utc = datetime.utcfromtimestamp(timestamp)
    utc_offset_secs = (time_now - time_utc).total_seconds()
    data = {'date':'', 'time':'', 'timezones':range(-12, 15, 1), 'timezone':int(utc_offset_secs)/3600}
    if request.method == 'GET':
        st, datetimenow = rtcapi.readFromDev(rtcapi.CONFIG_ID_DATETIME)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, datetimenow).decode('utf8')), category='danger')
            datetimenow = None
    
    pages = {'localtime': 'active'}
    form = DatetimeForm()
    if form.validate_on_submit():
        datetimenow = {'date':form.date.data,'time':form.time.data,'timezone':request.form.get("timezone", type=int)}
        st, datetimenow = rtcapi.writeToDev(rtcapi.CONFIG_ID_DATETIME, datetimenow)
        if st != rtcapi.RPC_OK:
            flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, datetimenow).decode('utf8')), category='danger')
        return redirect(url_for('localtime'))
    
    if datetimenow:
        data.update(datetimenow)
    return render_template("localtime.html",
        title = gettext('Date and Time'),
        time = data,
        pages = pages,
        form = form)

##----------------------------------------------------------------------
#@app.route('/upload', methods = ['GET', 'POST'])
#@login_required
#def upload():
#    if g.user.role == ROLE_GUEST:
#        abort(404)
#    if request.method == 'POST':
#        file = request.files['upfile']
#        if file and allowed_file(file.filename):
#            #print secure_filename(file.filename)
#            st, data = rtcapi.writeToDev(rtcapi.CONFIG_ID_PROGRAMM_UPDATE, Binary(file.read()))
#            if st != rtcapi.RPC_OK:
#                flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, '')))
#            ###else:
#                ##filename = secure_filename(file.filename)
#                ##file.save("C:\\Users\\eguba\\Desktop\\RTC\\web_admin\\"+filename)
#            #return redirect(url_for('upload',
#                                    #filename=filename))
#    
#    pages = {'upload': 'active'}
#    return render_template("upload.html",
#        title = gettext('Update'),
#        pages = pages)

##----------------------------------------------------------------------
#def allowed_file(filename):
#    return '.' in filename and \
#           filename.rsplit('.', 1)[1] in set(['txt', 'tlc'])

#----------------------------------------------------------------------
def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1] in ALLOWED_EXTENSIONS

#----------------------------------------------------------------------
def allowed_firmware_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1] in ALLOWED_FIRMWARE_EXTENSIONS


now = int(time.time())


#----------------------------------------------------------------------
@app.route('/upload', methods = ['GET', 'POST'])
@login_required
def upload():
    if g.user.role == ROLE_GUEST:
        abort(404)
    if request.method == 'POST':
        file = request.files['upfile']
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            print(filename)
            if filename.endswith('.tlc'):
                if rtcapi.PROTOCOL == 'xmlrpc':
                    st, data = rtcapi.writeToDev(rtcapi.CONFIG_ID_PROGRAMM_UPDATE, Binary(file.read()))
                elif rtcapi.PROTOCOL == 'tcp':
                    st, data = rtcapi.writeToDev(rtcapi.CONFIG_ID_PROGRAMM_UPDATE, file.read())
                if st != rtcapi.RPC_OK:
                    if rtcapi.PROTOCOL == 'xmlrpc':
                        flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, data).decode('utf8')), category='danger')
                    elif rtcapi.PROTOCOL == 'tcp':
                        flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, data)), category='danger')
                ###else:
                    ##filename = secure_filename(file.filename)
                    ##file.save("C:\\Users\\eguba\\Desktop\\RTC\\web_admin\\"+filename)
                #return redirect(url_for('upload',
                                        #filename=filename))
            elif filename.endswith('.rtc'):
                if not os.path.isdir(UPLOAD_FOLDER):
                    os.mkdir(UPLOAD_FOLDER)
                
                file.save(os.path.join(UPLOAD_FOLDER, filename))
        return redirect(url_for('upload'))

    global updating
    if g.user.role == ROLE_GUEST:
        abort(404)
    if os.path.exists(FIRMWARE_FILE):
        with open(FIRMWARE_FILE) as f:
            version = str(Version(f.read().split(' ')[1].split('_')[0]))
    else:
        version = 'Not found'
    pages = {'update': 'active'}
    if updating == 'Update':
        flash(gettext('Firmware update in progress.'), category='danger')
    elif updating == 'Error':
        flash(gettext('Firmware file is wrong.'), category='danger')
        updating = None
    pages = {'upload': 'active'}
    return render_template(
        "upload.html",
        title=gettext('Update'),
        pages=pages,
        now=now,
        version=version,
        updating=updating)


@limiter.exempt
@app.route('/check_status', methods=['GET'])
def check_status():
    return jsonify({"now": now})


@login_required
@app.route('/upload_firmware', methods=['POST'])
def upload_firmware():
    global updating
    if request.method == 'POST':
        file = request.files['file']
        if file and allowed_firmware_file(file.filename) and UUID:
            filename = secure_filename(file.filename)
            # Проверка файла
            file_hash = make_hash(file, UUID)
            file_tail = read_hash_from_file(file)
            if file_hash == file_tail:
                # проверка версии
                if os.path.exists(FIRMWARE_FILE):
                    with open(FIRMWARE_FILE) as f:
                        version = f.read().split(' ')[1]
                    if Version(filename.split('_')[0]) == Version(version.split('_')[0]) or \
                        FullVersion(filename).type_ != check_version():
                        status = {'status': 'error'}
                        updating = 'Error'
                    else:
                        file = get_file_content(file)
                        if not os.path.exists(UPDATE_FOLDER):
                            os.mkdir(UPDATE_FOLDER)
                        filepath = os.path.join(UPDATE_FOLDER, filename)
                        with open(filepath, 'w') as fd:
                            shutil.copyfileobj(file, fd)
                        status = {'status': 'success'}
                        updating = 'Update'
            else:
                status = {'status': 'error'}
                updating = 'Error'
            return jsonify(status)
        else:
            status = {'status': 'error'}
            updating = 'Error'
    return jsonify({'status': 'Not allowed'})


@app.route('/log/full/info_bakup', methods=['GET', 'POST'])
@login_required
def info_bakup():
    if g.user.role == ROLE_GUEST:
        abort(404)

    now_date = datetime.strftime(datetime.now(), "%d.%m.%Y_%H:%M:%S")
    zip_filename = "info_bakup_{0}.zip".format(now_date)

    def iter_file(file_path):
        max_size = 10000000
        if os.path.exists(file_path):
            with open(file_path, 'rb') as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                if size > max_size:
                    f.seek(size - max_size)
                else:
                    f.seek(0)
                return f.read()

    memory_file = BytesIO()
    with zipfile.ZipFile(memory_file, 'w', zipfile.ZIP_DEFLATED) as z:
        log_adaptive_path = os.path.join(MAIN_PATH, 'log_adaptive.log')
        z.writestr('log_adaptive.log', iter_file(log_adaptive_path))

        full_log_path = os.path.join(MAIN_PATH, 'full.log')
        z.writestr('full.log', iter_file(full_log_path))

        config_path = os.path.join(MAIN_PATH, 'config')
        with open(config_path, 'rb') as f:
            config_file = io.BytesIO(f.read())
        encrypted_config = encrypt_file(PASSWORD, config_file)
        z.writestr('config', encrypted_config.read())

        # SERVICE_PATH
        timestamp_path = os.path.join(SERVICE_PATH, 'timestamp.log')
        z.writestr('timestamp.log', iter_file(timestamp_path))

        ac_path = os.path.join(SERVICE_PATH, 'ac.log')
        z.writestr('ac.log', iter_file(ac_path))

        log_restart = os.path.join(MAIN_PATH, 'log_restart.log')
        if os.path.exists(log_restart):
            z.writestr('log_restart.log', iter_file(log_restart))

    memory_file.seek(0)
    return send_file(memory_file, attachment_filename=zip_filename, as_attachment=True)


#----------------------------------------------------------------------
@app.route('/config_bakup', methods = ['GET', 'POST'])
@login_required
def config_bakup():
    if g.user.role == ROLE_GUEST:
        abort(404)
    
    st, tlc = rtcapi.readFromDev(rtcapi.CONFIG_ID_GET_CURRENT_PROGRAMM)
    if st != rtcapi.RPC_OK:
        flash(gettext('Error! %(state)s', state = '{0}; {1};'.format(st, tlc).decode('utf8')), category='danger')
        return tlc
    
    # We need to modify the response, so the first thing we 
    # need to do is create a response out of the CSV string
    if rtcapi.PROTOCOL == 'xmlrpc':
        response = make_response(tlc.data)
    elif rtcapi.PROTOCOL == 'tcp':
        response = make_response(tlc)
    # This is the key: Set the right header for the response
    # to be downloaded, instead of just printed on the browser
    response.headers["Content-type"] ="multipart/form-data"
    response.headers["Content-Disposition"] = "attachment; filename=config_bakup_{0}.tlc".format(datetime.strftime(datetime.now(), "%d.%m.%Y_%H:%M:%S"))
    return response
    
    #pages = {'upload': 'active'}
    #return render_template("upload.html",
        #title = u'Обновление',
        #pages = pages)

#----------------------------------------------------------------------
@app.route('/system_reboot', methods = ['GET', 'POST'])
@login_required
def system_reboot():
    if g.user.role == ROLE_GUEST:
        abort(404)
    
    ##os.system('/usr/bin/sudo /usr/sbin/reboot')
    ##os.system("sudo shutdown -r now &")
    subprocess.Popen(['/usr/bin/sudo', '/usr/sbin/reboot'], stdout=subprocess.PIPE).communicate()
    ##rtcapi.systemReboot()
    return redirect(url_for('index'))

#----------------------------------------------------------------------
@app.route('/system_reboot_resident', methods = ['GET', 'POST'])
@login_required
def system_reboot_resident():
    if g.user.role == ROLE_GUEST:
        abort(404)
    ##os.system("sudo reboot")
    rtcapi.systemReboot()
    return redirect(url_for('index'))

#----------------------------------------------------------------------
def set_detectors(detectors, state):
    """detector = номеру детектора или список детекторов от 201 по 328 включительно"""
    if type(detectors) != list:
        detectors = [detectors]
    st, inputs = rtcapi.writeToDev(rtcapi.CONFIG_ID_ETH_INPUTS, [detectors, state])
    if st != rtcapi.RPC_OK:
        st, inputs = rtcapi.writeToDev(rtcapi.CONFIG_ID_ETH_INPUTS, [detectors, state])
    ##pass

#----------------------------------------------------------------------
def connectionCameras(number, value):
    """"""
    timer = TIMERS_FOR_CAMERAS.get(number)
    if not value:
        list_detectors = LIST_NUM_DETECTORS_FOR_CAMERAS.get(number, [])
        set_detectors(list_detectors, False)
        ##for d in list_detectors:
            ##set_detectors(d, False)#написать отправку рпц в резидент
        return
    if timer and timer.isAlive():
        timer.cancel()
    timer = threading.Timer(60, connectionCameras, [number, False])
    timer.start()
    TIMERS_FOR_CAMERAS[number] = timer

#----------------------------------------------------------------------
@app.route('/detect', methods = ['POST'])
@limiter.limit('200/second')
##@limiter.limit("180000/hour;3000/minute;50/second")
##@limiter.exempt # без ограничений
def detect():
    ##r = requests.post('http://localhost:5000/detect', data={"cars_detect":[True, False, True, True]})
    ##requests.post('http://192.168.0.108:5000/detect', json={"cars_detect":[True, False, True, True]}).text
    ##requests.post('https://192.168.0.111/detect', json={"cars_detect":[flag, True, False, False]}, verify=False)
    if request.method == 'POST':
        cars_detect = request.json.get('cars_detect')
        ##cameras = Camera.query.all()
        
        eth_detectors = {}
        st, eth_detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_ETH_DETECTORS)
        if st != rtcapi.RPC_OK:
            st, eth_detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_ETH_DETECTORS)
            if st != rtcapi.RPC_OK:
                eth_detectors = {}
        
        if cars_detect and type(cars_detect) == list and eth_detectors:
            ips = eth_detectors.get('ip', [])
            aliases = eth_detectors.get('alias', [])
            numbers = eth_detectors.get('number', [])
            for ip, alias, number in map(None, ips, aliases, numbers):
            ##for camera in cameras:
                ##if ip == request.remote_addr:
                if ip != '' and ip == request.environ.get('HTTP_X_FORWARDED_FOR', request.environ.get('HTTP_X_REAL_IP', request.remote_addr)):
                    for i, value in enumerate(cars_detect):
                        list_detectors = LIST_NUM_DETECTORS_FOR_CAMERAS.get(number)
                        if not list_detectors or i > MAX_AMOUNT_FRAMES_ONE_CAMERA-1:
                            break
                        set_detectors(list_detectors[i], bool(value))#написать отправку рпц в резидент
                        ##app.logger.info('ip = {0}; GPIO = {1}; state = {2}'.format(camera.ip, list_gpio[i], bool(value)))
                    connectionCameras(number, True)
                    break
            else:
                return jsonify(error='ip = {0} not found in the database;'.format(request.remote_addr))
        else:
            return jsonify(error='cars_detect = {0}; type = {1};'.format(cars_detect, str(type(cars_detect))))
        
        return jsonify(status=cars_detect) ##'{0}, {1}'.format(request.json, request.remote_addr)

#----------------------------------------------------------------------
@app.route('/lang')
@app.route('/lang/<string:lng>')
def lang(lng='ru'):
    with open(LANGUAGE_DIR, 'w') as f:
        f.write(lng)
    
    g.locale = lng
    response = make_response(lng)
    response.headers["Content-type"] ="text/plain"
    return response

#----------------------------------------------------------------------
@app.errorhandler(404)
def not_found_error(error):
    return render_template('404.html',
                           title = gettext('Not found')), 404

#----------------------------------------------------------------------
@app.errorhandler(429)
def ratelimit_handler(e):
    return make_response(jsonify(error="ratelimit exceeded %s" % e.description), 429)

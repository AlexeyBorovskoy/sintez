# -*- coding: utf-8 -*-

import os
from flask import flash, request, g, abort, make_response, jsonify

from app import app, limiter
from engine import rtcapi
from engine import my_threading as threading


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

NETVISION_THOR_X_MODULE = 8
MAX_AMOUNT_FRAMES_ONE_CAMERA_NETVISION_THOR_X = 12*4
MAX_AMOUNT_CAMERAS_NETVISION_THOR_X = 12
LIST_NUM_DETECTORS_FOR_CAMERAS_NETVISION_THOR_X = dict(map(None, range(1,MAX_AMOUNT_CAMERAS_NETVISION_THOR_X+1), [[1300+ii+(MAX_AMOUNT_FRAMES_ONE_CAMERA_NETVISION_THOR_X*i) for ii in range(1,MAX_AMOUNT_FRAMES_ONE_CAMERA_NETVISION_THOR_X+1)] for i in range(MAX_AMOUNT_CAMERAS_NETVISION_THOR_X)]))


def set_detectors(detectors, statuses, module=0):
    """detector = номеру детектора или список детекторов от 201 по 328 включительно"""
    if type(detectors) != list:
        detectors = [detectors]
    st, inputs = rtcapi.writeToDev(rtcapi.CONFIG_ID_ETH_INPUTS, [detectors, statuses], module)
    if st != rtcapi.RPC_OK:
        st, inputs = rtcapi.writeToDev(rtcapi.CONFIG_ID_ETH_INPUTS, [detectors, statuses], module)
    ##pass

#----------------------------------------------------------------------
def connectionCameras(number, value):
    """"""
    timer = TIMERS_FOR_CAMERAS.get(number)
    if not value:
        list_detectors = LIST_NUM_DETECTORS_FOR_CAMERAS.get(number, [])
        set_detectors(list_detectors, [0]*MAX_AMOUNT_FRAMES_ONE_CAMERA)
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
    ##data = {"complex_id":"CompleXXX", "cameras" :[{"zones":[{"id":1, "type":"stop", "value":0}, {"id":2, "type":"occupancy", "value":0}, {"id":3, "type":"loop", "value":1},]}]}
    ##requests.post('http://192.168.0.33/detect', json=data).text
    if request.method == 'POST':
        json_data = request.json
        if json_data is None:
            return jsonify(error="Not json data")
        #cars_detect = request.json.get('cars_detect')
        
        cars_detect = json_data.get('cars_detect')
        if cars_detect:
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
                    remote_header_ip = request.environ.get('HTTP_X_FORWARDED_FOR', request.environ.get('HTTP_X_REAL_IP', request.remote_addr)).split(',')[0]
                    if ip != '' and ip == remote_header_ip:
                        list_detectors = LIST_NUM_DETECTORS_FOR_CAMERAS.get(number)
                        statuses = map(lambda x,y: x if x != None else y, cars_detect[:MAX_AMOUNT_FRAMES_ONE_CAMERA], [0]*MAX_AMOUNT_FRAMES_ONE_CAMERA)
                        set_detectors(list_detectors, statuses)
                        connectionCameras(number, True)
                        break
                else:
                    return jsonify(error='ip = {0} not found in the database;'.format(request.remote_addr))
            else:
                return jsonify(error='cars_detect = {0}; type = {1};'.format(cars_detect, str(type(cars_detect))))
            
            return jsonify(status=cars_detect) ##'{0}, {1}'.format(request.json, request.remote_addr)
        # netvision_thor_x
        else:
            cameras = json_data.get('cameras')
            eth_detectors = {}
            st, eth_detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_ETH_DETECTORS)
            if st != rtcapi.RPC_OK:
                st, eth_detectors = rtcapi.readFromDev(rtcapi.CONFIG_ID_ETH_DETECTORS)
                if st != rtcapi.RPC_OK:
                    eth_detectors = {}
            
            if cameras and type(cameras) == list and eth_detectors:
                ips = eth_detectors.get('ip_netvision_thor_x', [])
                aliases = eth_detectors.get('alias_netvision_thor_x', [])
                numbers = eth_detectors.get('number_netvision_thor_x', [])
                num_cameras = eth_detectors.get('num_cams_netvision_thor_x', [])
                for ip, alias, number, num_cam in map(None, ips, aliases, numbers, num_cameras):
                ##for camera in cameras:
                    ##if ip == request.remote_addr:
                    remote_header_ip = request.environ.get('HTTP_X_FORWARDED_FOR', request.environ.get('HTTP_X_REAL_IP', request.remote_addr)).split(',')[0]
                    if ip != '' and ip == remote_header_ip:
                        # TODO обработать ту саму деревянную таблицу.
                        list_detectors = LIST_NUM_DETECTORS_FOR_CAMERAS_NETVISION_THOR_X.get(number)
                        tmp = {k:0 for k in list_detectors}
                        for cam in cameras:
                            zones = cam.get('zones', [])
                            for zone in zones[:12]:
                                num_zone = zone.get('id')
                                if num_zone in tmp:
                                    tmp[num_zone] = zone.get('value')
                        statuses = [v for k, v in sorted(tmp.items(), key = lambda item: item[0])]
                        #statuses = []
                        #for cam in cameras:
                        #    zones = cam.get('zones', [])
                        #    statuses.extend(map(lambda x,y: x.get('value') if x != None else y, zones[:12], [0]*12))
                        #statuses = map(lambda x,y: x if x != None else y, statuses, [0]*MAX_AMOUNT_FRAMES_ONE_CAMERA_NETVISION_THOR_X)
                        set_detectors(list_detectors, statuses, NETVISION_THOR_X_MODULE)
                        #connectionCameras(number, True) # TODO
                        break
                else:
                    return jsonify(error='ip = {0} not found in the database;'.format(request.remote_addr))
            else:
                return jsonify(error='cameras = {0}; type = {1};'.format(cameras, str(type(cameras))))
            
            return jsonify(status=cameras) ##'{0}, {1}'.format(request.json, request.remote_addr)

#----------------------------------------------------------------------
@app.errorhandler(404)
def not_found_error(error):
    return make_response(jsonify(error="Not found"), 404)

#----------------------------------------------------------------------
@app.errorhandler(429)
def ratelimit_handler(e):
    return make_response(jsonify(error="ratelimit exceeded %s" % e.description), 429)

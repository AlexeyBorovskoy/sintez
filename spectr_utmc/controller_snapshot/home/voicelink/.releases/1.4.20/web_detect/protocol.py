import os


PROTOCOL_FILE_PATH = '/home/voicelink/rtc/protocol'


data = ['tcp', '57384', 'multithreaded']
if os.path.exists(PROTOCOL_FILE_PATH):
    with open(PROTOCOL_FILE_PATH, 'r') as f:
        data = f.read().strip().split(',')

protocol = 'tcp'
listen_port = 57384
request_handler = 'multithreaded'  # singlethreaded

if len(data) == 3:
    if data[0] in ('tcp', 'xmlrpc'):
        protocol = data[0]
    if data[1].isdigit() and int(data[1]) in range(1024, 65536):
        listen_port = int(data[1])
    if data[2] in ('multithreaded', 'singlethreaded'):
        request_handler = data[2]

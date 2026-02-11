# -*- coding: utf-8 -*-
import socket

from IPy import IP
import subprocess, re, os
from ping import scan, do_one


#----------------------------------------------------------------------
def ping(addr, timeout = 1):
    if os.name == 'posix':
        pipe = subprocess.Popen(['ping', '-c', '1', '-W', str(timeout), str(addr)], stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        output, err = pipe.communicate()
        if output != None and output != '':
            lines = output.split('\n')
            if lines[5].find('rtt') == 0:
                return True
    elif os.name == 'nt':
        try:
            delay = do_one(addr, timeout)
            if delay != None:
                return True
        except socket.gaierror as e:
            pass
        except socket.error as e:
            if e.errno != 10065:
                raise e
            pass
    return False

#----------------------------------------------------------------------
def makeSubnet(ip, mask):
    try:
        return str(IP(ip).make_net(mask))
    except:
        return None

#----------------------------------------------------------------------
def broadcast(subnet):
    return str(IP(subnet).broadcast())

#----------------------------------------------------------------------
def ipInSubnet(ip, subnet):
    subnet = IP(subnet)
    return subnet.__contains__(ip)

#----------------------------------------------------------------------
def isValidIp(ip):
    try:
        ip = IP(ip)
        return True
    except:
        return False

#----------------------------------------------------------------------
def arping(iface, ip, count = 4):
    """"""
    if os.name == 'posix':
        subprocess.Popen(['arping', '-c', str(count), '-A', '-I', iface, ip], stdout=subprocess.PIPE).communicate()
        return True
    elif os.name == 'nt':
        return True

#----------------------------------------------------------------------
def getNetwork():
    """"""
    result = {}
    if os.name == 'posix':
        try:
            try:
                ifconfig_ce = subprocess.check_output(['ifconfig', '--version'], stderr=subprocess.PIPE,
                                                      universal_newlines=True)
                if ifconfig_ce:
                    ifconfig_output = ifconfig_ce
                    ifconfig_output = ifconfig_output[ifconfig_output.find('net-tools'):]
                    ifconfig_output = ifconfig_output[:ifconfig_output.find('\n')]
                    version_number = ifconfig_output.split()[1]
                    main_version_number = version_number.split('.')[0]
                else:
                    main_version_number = '1'
            except Exception as exc:
                main_version_number = '1'

            ifconfig = subprocess.Popen('ifconfig', stdout=subprocess.PIPE).communicate()[0].decode()

            if main_version_number == '1':
                # ifconfig v1.60
                res = re.search(r'^(?P<iface>eth\d+|eth\d+:\d+)\s+' +
                                r'Link encap:(?P<link_encap>\S+)\s+' +
                                r'(HWaddr\s+(?P<mac>\S+))?' +
                                r'(\s+inet addr:(?P<ip>\S+))?' +
                                r'(\s+Bcast:(?P<broadcast>\S+)\s+)?' +
                                r'(Mask:(?P<mask>\S+)\s+)?' +
                                r'(inet6 addr:[\s\S].*\s+)*' +
                                r'(UP\s+BROADCAST\s+(?P<status_link>\S+)\s+MULTICAST\s+)?',
                                ifconfig, re.MULTILINE)
            elif main_version_number == '2':
                # ifconfig v2.10
                res = re.search(
                    r'^(?P<iface>eth\d+):.*' +
                    r'flags=\d+<UP,BROADCAST,(?P<status_link>[A-Z]+),MULTICAST>.*\n' +
                    r'\s+inet\s+(?P<ip>(\d+\.){3}\d+).*' +
                    r'netmask\s+(?P<mask>(\d+\.){3}\d+).*' +
                    r'broadcast\s+(?P<broadcast>(\d+\.){3}\d+).*\n' +
                    r'\s+inet6.*\n' +
                    r'\s+ether\s+(?P<mac>[0-9a-f:]+).*\((?P<link_encap>[A-Za-z]+)\).*\n' +
                    r'.*',
                    ifconfig,
                    re.MULTILINE
                )
            else:
                res = ''

            if res:
                result = res.groupdict()
            
                gw = subprocess.Popen(['ip', 'r'], stdout=subprocess.PIPE).communicate()[0]
                m = re.search(r'^(default via\s+(?P<gw>\S+)\s+dev\s+(?P<iface>eth\d+|eth\d+:\d+)?)?.*?$',
                              gw, re.MULTILINE)
                temp = m.groupdict()
                if temp.get('iface') == result.get('iface'):
                    result.update(temp)
                ##result = res.groupdict()
        except Exception as e:
            print(e)
    elif os.name == 'nt':
        ifconfig = subprocess.Popen('ipconfig', stdout=subprocess.PIPE).communicate()[0]
        res = [('eth0', '02:59:06:c2:f3:e1', '192.168.1.254', '255.255.255.0', '')]
        key = ['iface', 'mac', 'ip', 'mask', 'gw']
        value = res[0]
        result = dict(map(None, key, value[:len(key)]))
    
    return result

#----------------------------------------------------------------------
def setNetwork(data):
    """"""
    if os.name == 'posix':
        gw = data.get('gw', '0.0.0.0')
        if not gw:
            gw = '0.0.0.0'
        iface = data.get('iface', 'eth0')
        _ip = '.'.join([str(int(i)) for i in data.get('ip', '192.168.0.1').split('.')])
        subprocess.Popen(['ifconfig',
                          iface,
                          'inet',
                          _ip,
                          'netmask',
                          '.'.join([str(int(i)) for i in data.get('mask', '255.255.255.0').split('.')])], stdout=subprocess.PIPE).communicate()
        subprocess.Popen(['ip', 'r', 'del', 'default'], stdout=subprocess.PIPE).communicate()
        subprocess.Popen(['ip', 'r', 'add', 'default',
                          'via', '.'.join([str(int(i)) for i in gw.split('.')]),
                          'dev', iface], stdout=subprocess.PIPE).communicate()
        arping(iface, _ip, 1)
        return True
    elif os.name == 'nt':
        return True
    
    return False

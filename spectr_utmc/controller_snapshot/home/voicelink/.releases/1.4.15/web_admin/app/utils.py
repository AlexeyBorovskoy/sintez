import os
import io
import struct
from hashlib import md5
import cStringIO
import random
from Crypto.Cipher import DES
from semantic_version import Version


SYNC_TIMES = ('1 hour', '6 hours', '12 hours', '1 day', '1 week', 'disabled')


def get_file_content(file):
    file.seek(0)
    res_file = cStringIO.StringIO()
    res_file.write(file.read()[:-20])
    res_file.seek(0)
    return res_file


def read_hash_from_file(file):
    # file = open(fname, 'rb')
    file.seek(-20, os.SEEK_END)
    tail = file.read()
    # magic = tail[-4:]
    head = tail[:-4]
    hash_str = ''
    for i in range(0, len(head), 4):
        hash_str += hex(struct.unpack('>L', head[i:i + 4])[0]).replace('0x', '').zfill(8).rstrip('L')
    return hash_str


def make_hash(f, uuid):
    if len(uuid) < 32:
        return ""
    m = md5()
    for i in range(0, len(uuid), 8):
        m.update(struct.pack(">L", int(uuid[i:i + 8], 16)))
    while True:
        d = f.read()[:-20]
        if not d:
            break
        m.update(d)
    # f.close()

    return m.hexdigest()


class WrongVersionError(Exception):

    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)


class FullVersion(Version):
    def __init__(self, version_str):
        version, self.type_ = version_str.replace('.tar', '').split('_')
        super(FullVersion, self).__init__(version)

    def __repr__(self):
        return '{}_{}'.format(
            super(FullVersion, self).__str__(),
            self.type_
        )

    def __str__(self):
        return '{}_{}'.format(
            super(FullVersion, self).__str__(),
            self.type_
        )


def encrypt_file(key, infile, chunksize=64 * 1024):
    iv = ''.join(chr(random.randint(0, 0xFF)) for i in range(8))
    encryptor = DES.new(key, DES.MODE_CBC, iv)

    outfile = io.BytesIO()
    filesize = len(infile.getvalue())
    outfile.write(struct.pack('<Q', filesize))
    outfile.write(iv)

    while True:
        chunk = infile.read(chunksize)
        if len(chunk) == 0:
            break
        elif len(chunk) % 8 != 0:
            chunk += ' ' * (8 - len(chunk) % 8)
        outfile.write(encryptor.encrypt(chunk))
    outfile.seek(0)
    return outfile


def check_version():
    if os.path.isdir('/usr/share/xsessions'):
        version = 'f'
    else:
        version = 'l'
    return version

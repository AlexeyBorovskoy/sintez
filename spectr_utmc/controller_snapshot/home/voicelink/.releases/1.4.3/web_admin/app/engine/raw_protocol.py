import sys
import struct
import json


class Header():
    '''
    Header
    rpc - 2 byte
    module - 1 byte
    act (status if server) - 1 byte
    '''

    def __init__(self, rpc, module, act):
        self.rpc = rpc
        self.module = module
        self.act = act

    def make_head(self):
        head = struct.pack('hbb', self.rpc, self.module, self.act)
        return head

    @classmethod
    def read_head(cls, bytes_):
        rpc, module, act = struct.unpack('hbb', bytes_)
        return Header(rpc, module, act)


class AuthFields():
    '''
    user - str
    password - str
    '''
    def __init__(self, user, password):
        self.user = user
        self.password = password

    def pack_string(self, str_):
        if sys.version_info.major == 3:
            bytes_string = bytes(str_, 'utf-8')
        else:
            bytes_string = bytes(str_)
        return struct.pack("I%ds" % (len(bytes_string),), len(bytes_string), bytes_string)

    @classmethod
    def unpack_string(cls, string_size, string_):
        (i,), data = struct.unpack("I", string_size), string_[4:]
        s, data = str(data[:i]), data[i:]
        return s, data

    def write(self):
        user = self.pack_string(self.user)
        password = self.pack_string(self.password)
        return user + password

    @classmethod
    def read(cls, bytes_):
        user, bytes_ = AuthFields.unpack_string(bytes_[:4], bytes_)
        password, bytes_ = AuthFields.unpack_string(bytes_[:4], bytes_)
        return user, password, bytes_


class Package():
    '''
    Client package
    size - 4 byte
    Header - 4 byte
    buffer - size-header bytes
    '''

    def __init__(self, rpc, module, act, buffer_, user, password):
        self.rpc = rpc
        self.module = module
        self.act = act
        self.buffer_ = buffer_
        self.user = user
        self.password = password

    def make_buffer(self):
        if sys.version_info.major == 3:
            json_string = bytes(json.dumps(self.buffer_), 'utf-8')
        else:
            json_string = bytes(json.dumps(self.buffer_))
        return struct.pack("I%ds" % (len(json_string),), len(json_string), json_string)

    @classmethod
    def read_buffer(cls, buffer_):
        (i,), data = struct.unpack("I", buffer_[:4]), buffer_[4:]
        s, data = json.loads(data[:i]), data[i:]
        return s

    def write(self):
        auth = AuthFields(self.user, self.password)
        header = Header(self.rpc, self.module, self.act)
        if self.rpc == 19:  # upload config
            buffer_ = self.buffer_
        else:
            buffer_ = self.make_buffer()
        data = auth.write() + header.make_head() + buffer_
        size = struct.pack('<I', len(data))
        return size + data

    @classmethod
    def read(cls, bytes_):
        user, password, bytes_ = AuthFields.read(bytes_)
        header = Header.read_head(bytes_[:4])
        if header.rpc == 19:  # upload config
            buffer_ = bytes_[4:]
        else:
            buffer_ = Package.read_buffer(bytes_[4:])
        return header.rpc, header.module, header.act, buffer_


class ServerPackage():
    '''
    Server package
    size - 4 byte
    Header - 4 byte
    buffer - size-header bytes
    '''

    def __init__(self, rpc, module, act, buffer_):
        self.rpc = rpc
        self.module = module
        self.act = act
        self.buffer_ = buffer_

    def make_buffer(self):
        if sys.version_info.major == 3:
            json_string = bytes(json.dumps(self.buffer_), 'utf-8')
        else:
            json_string = bytes(json.dumps(self.buffer_))
        return struct.pack("I%ds" % (len(json_string),), len(json_string), json_string)

    @classmethod
    def read_buffer(cls, buffer_):
        (i,), data = struct.unpack("I", buffer_[:4]), buffer_[4:]
        s, data = json.loads(data[:i]), data[i:]
        return s

    def write(self):
        header = Header(self.rpc, self.module, self.act)
        if self.rpc == 20:  # download config
            buffer_ = str(self.buffer_)
        else:
            buffer_ = self.make_buffer()
        data = header.make_head() + buffer_
        size = struct.pack('<I', len(data))
        return size + data

    @classmethod
    def read(cls, bytes_):
        header = Header.read_head(bytes_[:4])
        if header.rpc == 20:  # download config
            buffer_ = bytes_[4:]
        else:
            buffer_ = Package.read_buffer(bytes_[4:])
        return header.rpc, header.module, header.act, buffer_


if __name__ == "__main__":
    data = Package(47, 1, 1, 'test')
    result = Package.read(data.write()[4:])
    print(result[3], len(result[3]))
    print(result)

from OpenSSL import crypto, SSL
from socket import gethostname
from pprint import pprint
from time import gmtime, mktime

CERT_FILE = "web_admin.crt"
KEY_FILE = "web_admin.key"
organizationName = 'VoiceLink'
applicationName = 'WEB'
organizationDomain = 'http://voice-link.ru/contacts/'


#----------------------------------------------------------------------
def create_self_signed_cert():
    """"""
    # create a key pair
    key = crypto.PKey()
    key.generate_key(crypto.TYPE_RSA, 1024)

    # create a self-signed cert
    cert = crypto.X509()
    cert.get_subject().C = 'RU'
    cert.get_subject().ST = 'Russian Federation'
    cert.get_subject().L = 'Moscow'
    cert.get_subject().O = organizationName
    cert.get_subject().OU = organizationName
    cert.get_subject().CN = gethostname()
    cert.set_serial_number(3422617582)
    cert.gmtime_adj_notBefore(0)
    cert.gmtime_adj_notAfter(10*365*24*60*60)
    cert.set_issuer(cert.get_subject())
    cert.set_pubkey(key)
    cert.sign(key, 'md5')

    open(CERT_FILE, "wt").write(
        crypto.dump_certificate(crypto.FILETYPE_PEM, cert))
    open(KEY_FILE, "wt").write(
        crypto.dump_privatekey(crypto.FILETYPE_PEM, key))

create_self_signed_cert()
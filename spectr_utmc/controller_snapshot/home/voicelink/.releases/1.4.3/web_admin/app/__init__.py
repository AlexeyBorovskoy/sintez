# -*- coding: utf-8 -*-
from flask import Flask
try:
    from flask_sqlalchemy import SQLAlchemy
    from flask_login import LoginManager
    from flask_babel import Babel
except ImportError:
    from flask.ext.sqlalchemy import SQLAlchemy
    from flask.ext.login import LoginManager
    from flask.ext.babel import Babel
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
##from datetime import timedelta
#from flask_sslify import SSLify
import logging


#from OpenSSL import SSL
#context = SSL.Context(SSL.SSLv23_METHOD)
#context.use_privatekey_file('web_admin.key')
#context.use_certificate_file('web_admin.crt')


app = Flask(__name__)
app.config.from_object('config') # Используем настройки в config.py
##app.permanent_session_lifetime = timedelta(seconds=120) # Через 120 секунд неактивности пользователя сессия отвалится
#sslify = SSLify(app, permanent=True)
#app.logger.setLevel(logging.CRITICAL)
#log = logging.getLogger('werkzeug')
#log.setLevel(logging.ERROR)


##if not app.debug:
    ##import logging
    ##from logging.handlers import RotatingFileHandler
    ##file_handler = RotatingFileHandler('home/pi/hub_cameras.log', 'a', 1 * 1024 * 1024, 10)
    ##file_handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s: %(message)s [in %(pathname)s:%(lineno)d]'))
    ##app.logger.setLevel(logging.INFO)
    ##file_handler.setLevel(logging.INFO)
    ##app.logger.addHandler(file_handler)
    ##app.logger.info('hub cameras startup')

babel = Babel(app)

limiter = Limiter(app,
                  key_func=get_remote_address,
                  default_limits=["4000 per day", "500 per hour", "250 per minute", "125 per second"])

db = SQLAlchemy(app)

lm = LoginManager()
lm.init_app(app)
lm.login_view = 'login'

from app import views, models

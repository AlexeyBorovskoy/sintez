# -*- coding: utf-8 -*-
try:
    from flask_wtf import FlaskForm as Form
except ImportError:
    from flask.ext.wtf import Form

from wtforms import TextField, BooleanField, SelectField
from wtforms.validators import Required, Length, Regexp


class LoginForm(Form):
    login = TextField('login', validators = [Required()])
    password = TextField('password', validators = [Required()])
    remember_me = BooleanField('remember_me', default = False)


class DetectorsForm(Form):
    onoff = BooleanField('onoff', default = False)
    time_on = TextField('time_on', validators = [Required()])
    time_off = TextField('time_off', validators = [Required()])


class NetworkForm(Form):
    ip = TextField('ip', validators = [Required()])
    mask = TextField('mask', validators = [Required()])
    gw = TextField('gw', default = '0.0.0.0')


class SecurityForm(Form):
    login = TextField('login', validators = [Required()])
    password = TextField('password', validators = [Required()])
    repassword = TextField('repassword', validators = [Required()])


class DatetimeForm(Form):
    date = TextField('date', validators = [Required()])
    time = TextField('time', validators = [Required()])

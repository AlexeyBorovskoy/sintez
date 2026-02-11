# -*- coding: utf-8 -*-
import socket
try:
    from flask_wtf import FlaskForm as Form
    from flask_babel import lazy_gettext
except ImportError:
    from flask.ext.wtf import Form
    from flask.ext.babel import lazy_gettext


from wtforms import TextField, BooleanField, SelectField, StringField, IntegerField
from wtforms.validators import Required, Length, Regexp, IPAddress, InputRequired, ValidationError, NumberRange
from utils import SYNC_TIMES


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


SYNC_TIMES = [
    ('1h', lazy_gettext('1 hour')),
    ('6h', lazy_gettext('6 hours')),
    ('12h', lazy_gettext('12 hours')),
    ('1d', lazy_gettext('1 day')),
    ('1w', lazy_gettext('1 week')),
    ('disabled', lazy_gettext('disabled')),
]


class DatetimeForm(Form):
    date = TextField('date', validators=[Required()])
    time = TextField('time', validators=[Required()])
    ntpserver = TextField('ntpserver', validators=[])
    # time_mode = TextField('time_mode', validators=[Required()])
    time_mode = SelectField(
        lazy_gettext('Time mode:'),
        validators=[Required()],
        choices=[
            ('manual', lazy_gettext('Manual')),
            ('auto', lazy_gettext('Auto')),
        ]
    )
    synctime = SelectField(
        lazy_gettext('Sync time:'),
        choices=SYNC_TIMES,
        validators=[],
        default='disabled',
    )
    synctimentp = SelectField(
        lazy_gettext('Sync time:'),
        choices=SYNC_TIMES,
        validators=[],
        default='disabled',
    )

    sync_fallback = BooleanField(
        lazy_gettext('Backup sync with RTC:'),
        default=False,
        validators=[]
    )

    dst_enabled = BooleanField(
        lazy_gettext('Daylight Saving Time:'),
        default=False,
        validators=[]
    )

    time_migration = TextField(
        lazy_gettext('Time migration (min):'),
        # choices=[('30m', '30 min'), ('1h', '1 hour'), ('2h', '2 hours')],
        # validators=[],
        validators=[],
        default=60,
    )

    start_month = SelectField(
        lazy_gettext('Start:'),
        choices=[
            ('1', lazy_gettext('January')),
            ('2', lazy_gettext('February')),
            ('3', lazy_gettext('March')),
            ('4', lazy_gettext('April')),
            ('5', lazy_gettext('May')),
            ('6', lazy_gettext('June')),
            ('7', lazy_gettext('July')),
            ('8', lazy_gettext('August')),
            ('9', lazy_gettext('September')),
            ('10', lazy_gettext('October')),
            ('11', lazy_gettext('November')),
            ('12', lazy_gettext('December'))],
        default='mar.',
        validators=[])
    start_day_of_the_week = SelectField(
        'start_day_of_the_week',
        choices=[
            ('0', lazy_gettext('Monday')),
            ('1', lazy_gettext('Tuesday')),
            ('2', lazy_gettext('Wednesday')),
            ('3', lazy_gettext('Thursday')),
            ('4', lazy_gettext('Friday')),
            ('5', lazy_gettext('Saturday')),
            ('6', lazy_gettext('Sunday'))],
        validators=[])
    start_day = SelectField(
        'start_day',
        choices=[
            ('1', lazy_gettext('First')),
            ('2', lazy_gettext('2nd')),
            ('3', lazy_gettext('3rd')),
            ('4', lazy_gettext('4th')),
            ('-1', lazy_gettext('Last')),
        ],
        validators=[])
    start_time = SelectField(
        'start_time',
        choices=list(((str(i), '{}:00'.format(i).zfill(5)) for i in range(0, 24))),
        validators=[])

    end_month = SelectField(
        lazy_gettext('End:'),
        choices=[
            ('1', lazy_gettext('January')),
            ('2', lazy_gettext('February')),
            ('3', lazy_gettext('March')),
            ('4', lazy_gettext('April')),
            ('5', lazy_gettext('May')),
            ('6', lazy_gettext('June')),
            ('7', lazy_gettext('July')),
            ('8', lazy_gettext('August')),
            ('9', lazy_gettext('September')),
            ('10', lazy_gettext('October')),
            ('11', lazy_gettext('November')),
            ('12', lazy_gettext('December'))],
        default='oct.',
        validators=[])
    end_day_of_the_week = SelectField(
        'end_day_of_the_week',
        choices=[
            ('0', lazy_gettext('Monday')),
            ('1', lazy_gettext('Tuesday')),
            ('2', lazy_gettext('Wednesday')),
            ('3', lazy_gettext('Thursday')),
            ('4', lazy_gettext('Friday')),
            ('5', lazy_gettext('Saturday')),
            ('6', lazy_gettext('Sunday'))],
        validators=[])
    end_day = SelectField(
        'end_day',
        choices=[
            ('1', lazy_gettext('First')),
            ('2', lazy_gettext('2nd')),
            ('3', lazy_gettext('3rd')),
            ('4', lazy_gettext('4th')),
            ('-1', lazy_gettext('Last')),
        ],
        validators=[]
        )
    end_time = SelectField(
        'end_time',
        choices=list(((str(i), '{}:00'.format(i).zfill(5)) for i in range(0, 24))),
        validators=[]
    )

    def validate_ntpserver(form, field):
        try:
            socket.gethostbyname(field.data)
        except Exception:
            raise ValidationError("Invalid ntpserver.")


class PingForm(Form):
    ip_address_str = StringField("Is ip address: ", validators= 
       [InputRequired(), IPAddress(message="Should be ip!")])

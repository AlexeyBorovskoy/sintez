# -*- coding: utf-8 -*-
import os
from datetime import timedelta
BASEDIR = os.path.abspath(os.path.dirname(__file__))

CSRF_ENABLED = False# True
# SECRET_KEY = 'ae935880-238f-4164-ab78-cf3a5f7cc405'
SECRET_KEY = os.urandom(32)

SQLALCHEMY_DATABASE_URI = 'sqlite:///' + os.path.join(BASEDIR, 'app.db')
SQLALCHEMY_MIGRATE_REPO = os.path.join(BASEDIR, 'db_repository')

PERMANENT_SESSION_LIFETIME = timedelta(seconds=600) # Через 600 секунд неактивности пользователя сессия отвалится
MAX_SESSIONS_COUNT = 10 # максимальное количество одновременных сессий

#MAX_CONTENT_LENGTH = 1 * 1024 * 1024 # Ограничение загружаемого файла в 1M. генерирует ошибку 413, если больше 1M

LANGUAGES = {
    'en': 'English',
    'ru': 'Русский',
    'es': 'Español',
    'md': 'Moldovenească',
    'bg': 'Български'
}

LANGUAGE_DIR = os.path.join(BASEDIR, 'language')

UPLOAD_FOLDER = '/home/voicelink/rtc_uploads'
UPDATE_FOLDER = '/home/voicelink/.uploads'
FIRMWARE_FILE = '/home/voicelink/.firmware_status'
MAIN_PATH = '/home/voicelink/rtc/resident'
PASSWORD = 'z95mImh0'
SERVICE_PATH = '/home/voicelink/.service'

ALLOWED_EXTENSIONS = set(['tlc', 'rtc', 'zip'])
MAX_CONTENT_LENGTH = 300 * 1024 * 1024
SQLALCHEMY_TRACK_MODIFICATIONS = False
from uuid_id import UUID
MAGIC = '0x00c0ffee'
ALLOWED_FIRMWARE_EXTENSIONS = {'tar', }

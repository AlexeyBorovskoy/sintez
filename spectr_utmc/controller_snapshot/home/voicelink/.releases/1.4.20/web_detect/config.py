# -*- coding: utf-8 -*-
import os
from datetime import timedelta
BASEDIR = os.path.abspath(os.path.dirname(__file__))

CSRF_ENABLED = False# True
# SECRET_KEY = 'ae935880-238f-4164-ab78-cf3a5f7cc405'
SECRET_KEY = os.urandom(32)

PERMANENT_SESSION_LIFETIME = timedelta(seconds=600) # Через 600 секунд неактивности пользователя сессия отвалится
#MAX_CONTENT_LENGTH = 1 * 1024 * 1024 # Ограничение загружаемого файла в 1M. генерирует ошибку 413, если больше 1M

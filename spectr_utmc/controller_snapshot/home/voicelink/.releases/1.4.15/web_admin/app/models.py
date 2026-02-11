# -*- coding: utf-8 -*-
from app import db

ROLE_GUEST    = 0
ROLE_OPERATOR = 1
ROLE_ADMIN    = 2


class User(db.Model):
    id = db.Column(db.Integer, primary_key = True)
    login = db.Column(db.String(64), index = True, unique = True)
    passwd = db.Column(db.String(64))
    role = db.Column(db.SmallInteger, default = ROLE_GUEST)

    def is_authenticated(self):
        return True

    def is_active(self):
        return True

    def is_anonymous(self):
        return False

    def get_id(self):
        return unicode(self.id)

    def __repr__(self):
        return '<User %r>' % (self.login)


class Camera(db.Model):
    id = db.Column(db.Integer, primary_key = True)
    ip = db.Column(db.String(16), index = True, unique = True)
    alias = db.Column(db.Integer, unique = True)
    number = db.Column(db.Integer, unique = True)

    def __repr__(self):
        return '<Camera %s, %s, %s>' % (self.ip, self.alias, self.number)

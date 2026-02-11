#!flask/bin/python
from app import app#, context
##app.run(host='0.0.0.0', debug = True)
#app.run(host='0.0.0.0', port=443, ssl_context=context)#, use_reloader=True)


#def http_app():
#    app.run(host='0.0.0.0', port=80)
    #app.run(ssl_context=context, **kwargs)


if __name__ == "__main__":
    #from multiprocessing import Process
    
    #proc = Process(target=http_app)
    #proc.daemon = True
    #proc.start()
    app.run(host='0.0.0.0', port=8000, threaded=True, debug = True)
    ##app.run(host='0.0.0.0', port=443, threaded=True, ssl_context=('web_admin.crt', 'web_admin.key'), debug = True)
    #app.run(host='0.0.0.0', port=443, ssl_context=context)#, use_reloader=True)

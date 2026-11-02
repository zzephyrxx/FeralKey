#!/usr/bin/env python3
"""Local protocol fixture; never reads credentials or accesses the network."""
import json, os, sys, time
mode = os.environ.get('FERALKEY_TEST_MODE', 'ok')
assert sys.argv[1:] == ['app-server', '--listen', 'stdio://']
def read(): return json.loads(sys.stdin.readline())
def send(obj):
    line = json.dumps(obj) + '\n'
    # Exercise fragmented reads and multiple notifications between responses.
    sys.stdout.write(line[:7]); sys.stdout.flush()
    sys.stdout.write(line[7:]); sys.stdout.flush()
assert read()['method'] == 'initialize'
if mode == 'exit': sys.exit(0)
if mode == 'timeout': time.sleep(20); sys.exit(0)
send({'method':'ignored/notification','params':{}})
if mode == 'broken-pipe': os.close(sys.stdin.fileno())
send({'id':1,'result':{'userAgent':'fixture'}})
if mode == 'broken-pipe': time.sleep(0.1); sys.exit(0)
assert read()['method'] == 'initialized'
assert read()['method'] == 'account/rateLimits/read'
if mode == 'error':
    send({'id':2,'error':{'code':-32000,'message':'SECRET_MUST_NOT_BE_LOGGED'}})
elif mode == 'malformed': send({'id':2,'result':{'rateLimits':42}})
else:
    send({'id':2,'result':{'rateLimitsByLimitId':{'codex':{'primary':{'usedPercent':25,'windowDurationMins':300,'resetsAt':time.time()+3600},'secondary':{'usedPercent':60,'windowDurationMins':10080,'resetsAt':time.time()+86400}}}}})
sys.stdin.read()  # Client closes its own process and pipe.

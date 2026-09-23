#!/usr/bin/python3
"""SYNTHETIC curl transport: never opens a socket or delegates to real curl."""
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit


def main():
    root = Path(os.environ['BLEND_FIXTURE_ROOT'])
    assert root.is_absolute() and str(root).startswith('/extra/')
    assert (root / 'SYNTHETIC_FIXTURE').is_file()
    args = sys.argv[1:]
    method, body, writeout = 'GET', '', False
    urls = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ('-X', '--request', '-d', '--data', '--data-raw', '-w', '--write-out', '-H', '--header', '-m', '--max-time', '--connect-timeout'):
            value = args[i + 1]
            if arg in ('-X', '--request'):
                method = value
            elif arg in ('-d', '--data', '--data-raw'):
                body = value
            elif arg in ('-w', '--write-out'):
                assert value == '\n%{http_code}', 'Unsupported writeout'
                writeout = True
            i += 2
        elif arg in ('-s', '-S', '-sS', '--silent', '--show-error', '-f', '--fail'):
            i += 1
        elif arg.startswith('http'):
            urls.append(arg)
            i += 1
        else:
            raise AssertionError('Unexpected curl argument: ' + arg)
    assert len(urls) == 1
    url = urlsplit(urls[0])
    assert url.scheme == 'http' and url.netloc == '127.0.0.1:8080' and not url.query
    routes = json.loads((root / 'responses.json').read_text())
    key = method + ' ' + url.path
    assert key in routes, 'Unapproved fixture route: ' + key
    assert not any(k in os.environ for k in ('LD_LIBRARY_PATH', 'LD_PRELOAD', 'QT_PLUGIN_PATH', 'QML2_IMPORT_PATH')), 'Loader env not stripped'
    response = routes[key]
    if method != 'GET':
        assert method == 'POST' and url.path in ('/sdp/set-declaration-id', '/sdp/withdrawal', '/blend/join'), 'Forbidden mutation route'
        actual = json.loads(body)
        expected = response.get('expect_body', 'b' * 64 if url.path == '/sdp/set-declaration-id' else None)
        assert expected is not None and actual == expected, 'POST body differs from exact authorized fixture'
        if url.path in ('/sdp/set-declaration-id', '/sdp/withdrawal'):
            assert actual == 'b' * 64, 'Body must be bare synthetic owned DeclarationId JSON string'
        else:
            assert set(actual) == {'locator', 'locked_note_id'}, 'Join request must match pinned JoinBlendRequestBody'
    with (root / 'requests.jsonl').open('a') as out:
        out.write(json.dumps({'method': method, 'path': url.path, 'body': body}) + '\n')
    # A received mutation whose response is lost: no stdout or HTTP status. The
    # production request/pending-journal implementation handles this uncertainty.
    if response.get('exit'):
        assert response['exit'] == 28, 'Only curl timeout injection is supported'
        sys.exit(28)
    sys.stdout.write(response['raw'] if 'raw' in response else json.dumps(response['body']))
    if writeout:
        sys.stdout.write('\n' + str(response.get('code', 200)))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        root = Path(os.environ['BLEND_FIXTURE_ROOT'])
        with (root / 'transport-errors.log').open('a') as out:
            out.write(str(error) + '\n')
        print('FIXTURE REJECTED: ' + str(error), file=sys.stderr)
        sys.exit(99)

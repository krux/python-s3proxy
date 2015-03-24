import logging
import os
import sys

import boto.s3.connection
from flask import Flask, Response, redirect


import ssl
### XXX: Hack to fix issues with validating dotted bucket hostnames in newer versions of python
if sys.version_info >= (2, 7, 9):
    _old_match_hostname = ssl.match_hostname
    def _new_match_hostname(cert, hostname):
        if hostname.endswith('.s3.amazonaws.com'):
            pos = hostname.find('.s3.amazonaws.com')
            hostname = hostname[:pos].replace('.', '') + hostname[pos:]
        return _old_match_hostname(cert, hostname)
    ssl.match_hostname = _new_match_hostname


class S3Proxy(object):
    def __init__(self, bucket_name, path, key, secret, host, port):
        self.bucket_name = bucket_name
        self.path = path
        self.key = key
        self.secret = secret
        self.host = host
        self.port = port

        logging.basicConfig(
            format='%(asctime)s: %(name)s/%(levelname)-9s: %(message)s', level=logging.INFO)

        self.s3 = boto.s3.connection.S3Connection(self.key, self.secret)
        self.bucket = self.s3.get_bucket(self.bucket_name)

        self.app = Flask(self.__class__.__name__)
        #self.app.debug = True

        self.status = self.app.route('/__status')(self.status)
        self.handle = self.app.route('/<path:path>')(self.handle)

    def run(self):
        return self.app.run(
            host=self.host,
            port=self.port,
        )

    def status(self):
        return Response('{"status": "ok"}', mimetype='application/json')

    def handle(self, path):
        self.app.logger.debug('Request for path %r', path)
        self.app.logger.debug('s3://%s/%s%s', self.bucket_name, self.path, path)
        try:
            full_path = self.path + path
            self.app.logger.debug('full_path %r', full_path)
            if path.endswith('/'):
                return self.handle_directory(path)

            key = self.bucket.get_key(full_path)
            if key is None:
                # If we can't find a file, try it as a directory
                ### Note: Some versions of pip will make some requests for what
                ### should be directories without the trailing slash.
                keys = self.bucket.list(full_path + '/', '/')
                try:
                    iter(keys).next()
                    # there are keys to list, so send back a redirect so the client
                    # knows it should be treating this as a directory.
                    self.app.logger.warning(
                        'path does not end in / but is a directory, redirecting %r', path)
                    return redirect(path + '/')
                except StopIteration:
                    self.app.logger.warning('Key not found for path and not a directory %r', path)
                    return ('', 404)

            self.app.logger.info('Found key for path %r', path)
            return Response(key, mimetype='application/octet-stream')
        except Exception, e:
            return (str(e), 404)

    def handle_directory(self, path):
        full_path = self.path + path
        self.app.logger.debug('Path ends in /, checking for index.html')
        key = self.bucket.get_key(full_path + 'index.html')
        if key is not None:
            self.app.logger.info('Found index.html for %r', path)
            return Response(key, mimetype='text/html')

        self.app.logger.debug('index.html not found, trying a manual listing')
        keys = self.bucket.list(full_path, '/')
        keyiter = iter(keys)
        try:
            key = keyiter.next()
        except StopIteration:
            self.app.logger.warning('path has no keys %r', path)
            return ('', 404)

        self.app.logger.info('Generating index for path %r', path)

        def generate(key, keys):
            yield ('<html><head><title>Simple Index</title>'
                   '<meta name="api-version" value="2" /></head><body>\n')
            try:
                while True:
                    name = str(key.name)[len(full_path):]
                    if name.endswith('/'):
                        name = name[:-1]
                    yield "<a href='%s'>%s</a><br/>\n" % (name, name)
                    key = keyiter.next()
            except StopIteration:
                pass
            yield '</body></html>'
        return Response(generate(key, keys), mimetype='text/html')


def main():
    def getenv(name, default):
        return os.environ[name] if name in os.environ and len(os.environ[name]) > 0 else default
    S3Proxy(
        os.environ['S3_BUCKET'],
        os.environ['S3_PREFIX'],
        getenv('IAM_KEY', None),
        getenv('IAM_SECRET', None),
        getenv('BIND_HOST', '127.0.0.1'),
        int(getenv('BIND_PORT', 5000)),
    ).run()


if __name__ == '__main__':
    main()

"""Local static server with the production Hosting /privacy rewrite."""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Handler(SimpleHTTPRequestHandler):
    def send_head(self):
        if urlsplit(self.path).path == '/privacy':
            self.path = '/index.html'
        return super().send_head()


ThreadingHTTPServer(
    ('127.0.0.1', 8092), partial(Handler, directory='build/web_oct02')
).serve_forever()

import http.server
import socketserver
import webbrowser
import os

PORT = 3000
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        url = f"http://localhost:{PORT}"
        print(f"=======================================================")
        print(f"🌸 BukuPinkKu Web App sedang berjalan di: {url}")
        print(f"Tekan Ctrl+C untuk hentikan pelayan.")
        print(f"=======================================================")
        try:
            webbrowser.open(url)
        except Exception:
            pass
        httpd.serve_forever()
